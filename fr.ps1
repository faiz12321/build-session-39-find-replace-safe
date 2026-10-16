#requires -Version 7.4
# PowerShell 7.4+. Small local UTF-8 .txt trees only. Stop editors/sync first.
# A retained, root-bound backup and journal allow conflict-checked undo.
# Not transactional, not a security boundary, no concurrent/hostile change guarantee.
param(
 [Parameter(Mandatory, Position=0)]
 [ValidateSet('count','preview','backup','apply','diff','undo')][string]$Mode,
 [Parameter(Position=1)][string]$Find='',
 [Parameter(Position=2)][AllowEmptyString()][string]$Replace='',
 [string]$Root=(Join-Path $PSScriptRoot 'notes')
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$utf8=[Text.UTF8Encoding]::new($false,$true)
function Hash([byte[]]$bytes) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)) }
function Item([string]$p) { Get-Item -LiteralPath $p -Force -ErrorAction Stop }
function No-Link([string]$p) {
 $i=Item $p
 if (-not $IsWindows) {
  & /usr/bin/test -f $p; $file=($LASTEXITCODE -eq 0)
  & /usr/bin/test -d $p; $dir=($LASTEXITCODE -eq 0)
  if (-not ($file -or $dir)) { throw 'Special filesystem entries are not supported.' }
 }
 if (($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $i.LinkType) { throw 'Links/reparse points are not supported.' }
 return $i
}
function Check-Ancestors([string]$p) {
 while ($p) { $null=No-Link $p; $p=[IO.Path]::GetDirectoryName($p) }
}
function Exists([string]$p) {
 # Get-Item also sees dangling symbolic links, unlike File.Exists.
 return $null -ne (Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue)
}
function New-Bytes([string]$p,[byte[]]$bytes) {
 if (Exists $p) { throw 'Output path already exists.' }
 $stream=[IO.File]::Open($p,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
}
function Write-Json([string]$p,$obj) {
 New-Bytes $p ($utf8.GetBytes(($obj | ConvertTo-Json -Depth 12 -Compress)))
}
function Read-Bytes([string]$p) {
 $i=No-Link $p
 if ($i.PSIsContainer -or $i.Length -gt 1MB) { throw 'Expected a regular file no larger than 1 MiB.' }
 return ,([IO.File]::ReadAllBytes($p))
}
function Text([byte[]]$bytes) {
 $t=$utf8.GetString($bytes)
 if ($t.Contains([char]0)) { throw 'NUL text is unsupported. Use UTF-8 text, not UTF-16/binary.' }
 return $t
}
function Inventory([string]$dir) {
 $item=No-Link $dir
 if (-not $item.PSIsContainer) { throw 'Root must be a directory.' }
 $stack=[Collections.Generic.Stack[string]]::new(); $stack.Push($dir)
 $result=[Collections.Generic.List[string]]::new()
 $visited=0
 while ($stack.Count) {
  foreach ($i in Get-ChildItem -LiteralPath $stack.Pop() -Force) {
   $visited++; if ($visited -gt 2000) { throw 'Tree exceeds 2000 entries.' }
   $null=No-Link $i.FullName
   if ($i.PSIsContainer) { $stack.Push($i.FullName) }
   elseif ($i.Extension -ieq '.txt') { $result.Add([IO.Path]::GetRelativePath($dir,$i.FullName).Replace('\','/')) }
  }
 }
 return @($result | Sort-Object -CaseSensitive)
}
function Snapshot([string]$dir) {
 $map=[ordered]@{}; $total=0
 foreach ($rel in Inventory $dir) {
  $bytes=Read-Bytes (Join-Path $dir $rel); $total+=$bytes.Length
  if ($total -gt 10MB) { throw 'Selected text exceeds 10 MiB.' }
  $null=Text $bytes
  if ($map.Contains($rel)) { throw 'Case-colliding file names are unsupported.' }
  $map[$rel]=$bytes
 }
 if ($map.Count -eq 0 -or $map.Count -gt 1000) { throw 'Need 1 to 1000 .txt files.' }
 return $map
}
function Same-Names($actual,$expected) {
 if ($actual.Count -ne $expected.Count) { throw 'File inventory changed.' }
 for ($i=0;$i -lt $actual.Count;$i++) { if ($actual[$i] -cne $expected[$i]) { throw 'File inventory changed.' } }
}
function Load-Backup($current) {
 Check-Ancestors $backup
 $m=$utf8.GetString((Read-Bytes (Join-Path $backup 'manifest.json'))) | ConvertFrom-Json
 if ($m.version -ne 1 -or $m.root -cne $Root -or @($m.files).Count -ne $current.Count) { throw 'Invalid or wrong-root backup manifest.' }
 $saved=Snapshot (Join-Path $backup 'files')
 $names=@($current.Keys); Same-Names @($saved.Keys) $names
 Same-Names @($m.files | ForEach-Object { $_.path }) $names
 foreach ($f in $m.files) {
  if ($f.hash -cne (Hash $saved[$f.path])) { throw 'Backup bytes do not match manifest.' }
 }
 return $saved
}
function Replace-One([string]$p,[byte[]]$expected,[byte[]]$next) {
 # Stage then rename, rather than truncate an inode that might have other links.
 if ((Hash (Read-Bytes $p)) -cne (Hash $expected)) { throw 'File changed before write.' }
 $tmp=Join-Path ([IO.Path]::GetDirectoryName($p)) ('.fr-'+[guid]::NewGuid().ToString('N')+'.tmp')
 try { New-Bytes $tmp $next; [IO.File]::Move($tmp,$p,$true) }
 finally { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) } }
}
try {
 if (-not $IsWindows -and -not [IO.File]::Exists('/usr/bin/test')) { throw 'This Unix workflow requires /usr/bin/test.' }
 if (($Root -split '[\\/]') -contains '..') { throw 'Parent-traversal roots are not supported.' }
 $Root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Root))
 Check-Ancestors $Root
 $backup=$Root+'.fr-backup'
 $current=Snapshot $Root
 if ($Mode -in 'count','preview','apply') {
  if (-not $Find -or $Find.IndexOfAny([char[]]"`r`n`0") -ge 0 -or $Replace.IndexOfAny([char[]]"`r`n`0") -ge 0) { throw 'Use nonempty, single-line find text and single-line replacement.' }
 }
 switch ($Mode) {
  { $_ -in 'count','preview' } {
   $total=0; $matched=0
   foreach ($rel in $current.Keys) {
    $t=Text $current[$rel]; $n=[regex]::Matches($t,[regex]::Escape($Find)).Count
    if (-not $n) { continue }; $total+=$n; $matched++
    "${rel}: $n matches"
    if ($Mode -eq 'preview') {
     $lineNo=0
     foreach ($line in ($t -split "`r`n|`n|`r")) {
      $lineNo++; if ($line.Contains($Find)) { "  line ${lineNo}: $line"; '       -> '+$line.Replace($Find,$Replace) }
     }
    }
   }
   "Total: $total matches in $matched files"
   if ($Mode -eq 'preview') { 'Preview only. No file was written.' }
  }
  'backup' {
   if (Exists $backup) { throw 'Backup path already exists. Keep it; use a new practice folder.' }
   $null=[IO.Directory]::CreateDirectory($backup)
   $filesDir=Join-Path $backup 'files'; $null=[IO.Directory]::CreateDirectory($filesDir)
   $entries=@()
   foreach ($rel in $current.Keys) {
    $dest=Join-Path $filesDir $rel; $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest))
    New-Bytes $dest $current[$rel]
    if ((Hash (Read-Bytes $dest)) -cne (Hash $current[$rel])) { throw 'Backup verification failed.' }
    $entries+=@{path=$rel;hash=(Hash $current[$rel])}
   }
   Write-Json (Join-Path $backup 'manifest.json') @{version=1;root=$Root;files=$entries}
   "Backed up and verified $($current.Count) files. Backup retained beside root."
  }
  'apply' {
   $saved=Load-Backup $current
   foreach ($rel in $current.Keys) { if ((Hash $current[$rel]) -cne (Hash $saved[$rel])) { throw 'Source changed since backup.' } }
   $journal=Join-Path $backup 'journal.json'
   if ((Exists $journal) -or (Exists (Join-Path $backup 'restored.json'))) { throw 'This backup already has an operation. Apply refused.' }
   $planned=[ordered]@{}; $total=0; $changed=0; $outputBytes=0
   foreach ($rel in $current.Keys) {
    $t=Text $current[$rel];$total+=[regex]::Matches($t,[regex]::Escape($Find)).Count
    $planned[$rel]=$utf8.GetBytes($t.Replace($Find,$Replace))
    $outputBytes+=$planned[$rel].Length
    if ($planned[$rel].Length -gt 1MB -or $outputBytes -gt 10MB) { throw 'Replacement exceeds the size limits.' }
    if ((Hash $planned[$rel]) -cne (Hash $current[$rel])) { $changed++ }
   }
   # Save the plan BEFORE writing any source. Undo can handle a partially applied plan.
   Write-Json $journal @{version=1;root=$Root;find=$Find;replace=$Replace}
   foreach ($rel in $current.Keys) { if ((Hash $planned[$rel]) -cne (Hash $current[$rel])) { Replace-One (Join-Path $Root $rel) $current[$rel] $planned[$rel] } }
   "Total: $total matches; $changed files changed. Backup and journal retained."
  }
  'diff' {
   $saved=Load-Backup $current; $changed=0
   foreach ($rel in $current.Keys) {
    if ((Hash $current[$rel]) -ceq (Hash $saved[$rel])) { "${rel}: byte-identical" }
    else { "${rel}: bytes changed"; $changed++ }
   }
   "Diff: $changed files changed, $($current.Count-$changed) unchanged"
  }
  'undo' {
   $saved=Load-Backup $current
   if (Exists (Join-Path $backup 'restored.json')) { throw 'Undo already completed. Backup retained.' }
   $j=$utf8.GetString((Read-Bytes (Join-Path $backup 'journal.json'))) | ConvertFrom-Json
   if ($j.version -ne 1 -or $j.root -cne $Root -or -not ($j.find -is [string]) -or -not $j.find -or -not ($j.replace -is [string])) { throw 'Invalid operation journal.' }
   foreach ($rel in $current.Keys) {
    $before=Hash $saved[$rel]; $after=Hash ($utf8.GetBytes((Text $saved[$rel]).Replace($j.find,$j.replace))); $now=Hash $current[$rel]
    if ($now -cne $before -and $now -cne $after) { throw 'Undo conflict: a file has other edits. No restore started.' }
   }
   foreach ($rel in $current.Keys) { if ((Hash $current[$rel]) -cne (Hash $saved[$rel])) { Replace-One (Join-Path $Root $rel) $current[$rel] $saved[$rel] } }
   Write-Json (Join-Path $backup 'restored.json') @{version=1;restored=$true}
   "Restored $($current.Count) files byte-for-byte. Backup and journal retained."
  }
 }
 exit 0
} catch {
 'Stopped: '+$_.Exception.Message
 'If a write failed, keep the backup and journal. Multi-file writes are not transactional.'
 exit 1
}
