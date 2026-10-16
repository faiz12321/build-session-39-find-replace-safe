# Independent end-to-end fixtures. Never deletes a fixed lesson/user path.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$fr=Join-Path $PSScriptRoot 'fr.ps1'
$sample=Join-Path $PSScriptRoot 'make_sample.ps1'
$utf8=[Text.UTF8Encoding]::new($false,$true)
$temp=Join-Path ([IO.Path]::GetTempPath()) ('fr-tests-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($temp)
$script:n=0; $script:bad=0; $script:skipped=0
function Check([string]$name,[bool]$ok) {
 $script:n++
 if ($ok) { "ok $($script:n) - $name" } else { $script:bad++; "NOT OK $($script:n) - $name" }
}
function Run([string[]]$ArgList) {
 $o=& pwsh -NoLogo -NoProfile -File $fr @ArgList 2>&1 | ForEach-Object { "$_" }
 return @{Code=$LASTEXITCODE;Text=($o -join "`n")}
}
function Setup([string]$root) {
 $o=& pwsh -NoLogo -NoProfile -File $sample -Root $root 2>&1 | ForEach-Object { "$_" }
 return @{Code=$LASTEXITCODE;Text=($o -join "`n")}
}
function Digest([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function Fresh([string]$name) {
 $r=Join-Path $temp $name; $s=Setup $r
 if ($s.Code) { throw $s.Text }
 return $r
}
function Save([string]$r) { $o=Run @('backup','-Root',$r); if ($o.Code) { throw $o.Text } }
function Apply([string]$r) { return Run @('apply','Project Bluebird','Project Heron','-Root',$r) }
function Put([string]$p,[string]$text) { [IO.File]::WriteAllText($p,$text,$utf8) }
function Manifest([string]$r) { return Join-Path ($r+'.fr-backup') 'manifest.json' }
try {
 $r=Fresh 'main[fixture]'; $a=Join-Path $r 'readme.txt'; $b=Join-Path $r 'archive/old-plan.txt'; $c=Join-Path $r 'todo.txt'
 $hashes=@((Digest $a),(Digest $b),(Digest $c));$mtime=(Get-Item -LiteralPath $a).LastWriteTimeUtc.Ticks
 $o=Setup $r;Check 'setup repeat refuses' ($o.Code -eq 1)
 Check 'setup preserves existing bytes and mtime' ((Digest $a) -eq $hashes[0] -and (Get-Item -LiteralPath $a).LastWriteTimeUtc.Ticks -eq $mtime)
 $o=Run @('count','Project Bluebird','-Root',$r);Check 'count 4 literal case-sensitive matches' ($o.Code -eq 0 -and $o.Text.Contains('Total: 4 matches in 3 files'))
 $o=Run @('preview','Project Bluebird','Project Heron','-Root',$r);Check 'preview shows before and after' ($o.Code -eq 0 -and $o.Text.Contains('-> Project Heron kickoff'))
 Check 'read-only modes preserve all bytes' ((Digest $a) -eq $hashes[0] -and (Digest $b) -eq $hashes[1] -and (Digest $c) -eq $hashes[2])
 $o=Apply $r;Check 'no backup refuses' ($o.Code -eq 1)
 Check 'no-backup refusal leaves bytes' ((Digest $a) -eq $hashes[0])
 Save $r
 $o=Run @('backup','-Root',$r);Check 'repeat backup refuses' ($o.Code -eq 1)
 $o=Apply $r;Check 'apply changes three files' ($o.Code -eq 0 -and $o.Text.Contains('4 matches; 3 files changed'))
 Check 'literal case preserved' ([IO.File]::ReadAllText($c).Contains('Keep project bluebird unchanged'))
 Check 'CRLF retained' ([IO.File]::ReadAllText($a).Contains("kickoff`r`n"))
 $o=Apply $r;Check 'repeat apply refuses' ($o.Code -eq 1)
 $o=Run @('diff','-Root',$r);Check 'diff counts byte changes' ($o.Code -eq 0 -and $o.Text.Contains('Diff: 3 files changed, 0 unchanged'))
 $o=Run @('undo','-Root',$r);Check 'undo succeeds' ($o.Code -eq 0)
 Check 'all three original digests restored' ((Digest $a) -eq $hashes[0] -and (Digest $b) -eq $hashes[1] -and (Digest $c) -eq $hashes[2])
 Check 'backup retained after undo' (Test-Path -LiteralPath (Manifest $r))
 $o=Run @('undo','-Root',$r);Check 'second undo refuses' ($o.Code -eq 1)
 $r=Fresh 'newfile';Save $r;Put (Join-Path $r 'new.txt') 'Project Bluebird';$before=Digest (Join-Path $r 'readme.txt')
 $o=Apply $r;Check 'new file after backup refuses before writes' ($o.Code -eq 1 -and (Digest (Join-Path $r 'readme.txt')) -eq $before)
 $r=Fresh 'missing';Save $r;[IO.File]::Delete((Join-Path $r 'todo.txt'));$o=Apply $r;Check 'missing source refuses' ($o.Code -eq 1)
 $r=Fresh 'edit';Save $r;Put (Join-Path $r 'todo.txt') 'edited';$o=Apply $r;Check 'source edit after backup refuses' ($o.Code -eq 1)
 $r=Fresh 'tamper';Save $r;Put (Join-Path ($r+'.fr-backup') 'files/readme.txt') 'bad';$o=Apply $r;Check 'tampered backup refuses' ($o.Code -eq 1)
 $r=Fresh 'extra-backup';Save $r;Put (Join-Path ($r+'.fr-backup') 'files/extra.txt') 'extra';$o=Apply $r;Check 'extra backup file refuses' ($o.Code -eq 1)
 $r=Fresh 'wrongroot';Save $r;$m=[IO.File]::ReadAllText((Manifest $r)) | ConvertFrom-Json;$m.root=$temp;Put (Manifest $r) ($m|ConvertTo-Json -Depth 8);$o=Apply $r;Check 'wrong root manifest refuses' ($o.Code -eq 1)
 $r=Fresh 'emptybackup';$null=[IO.Directory]::CreateDirectory($r+'.fr-backup');$o=Apply $r;Check 'empty unrelated backup refuses' ($o.Code -eq 1)
 $r=Fresh 'conflict';Save $r;$o=Apply $r;Put (Join-Path $r 'todo.txt') 'later user edit';$before=Digest (Join-Path $r 'readme.txt');$o=Run @('undo','-Root',$r)
 Check 'undo conflict refuses before any restore' ($o.Code -eq 1 -and (Digest (Join-Path $r 'readme.txt')) -eq $before)
 Check 'undo preserves later edit' ([IO.File]::ReadAllText((Join-Path $r 'todo.txt')) -ceq 'later user edit')
 $r=Fresh 'partial';Save $r;$o=Apply $r
 [IO.File]::Copy((Join-Path ($r+'.fr-backup') 'files/todo.txt'),(Join-Path $r 'todo.txt'),$true)
 $o=Run @('undo','-Root',$r);Check 'undo accepts mixed before/after state' ($o.Code -eq 0)
 $r=Fresh 'bom';$a=Join-Path $r 'readme.txt';$raw=[byte[]](0xef,0xbb,0xbf)+$utf8.GetBytes("Project Bluebird`r`n");[IO.File]::WriteAllBytes($a,$raw);$h=Digest $a;Save $r;$o=Apply $r
 Check 'UTF8 BOM preserved after apply' ([IO.File]::ReadAllBytes($a)[0] -eq 239)
 $o=Run @('undo','-Root',$r);Check 'BOM bytes exactly restored' ($o.Code -eq 0 -and (Digest $a) -eq $h)
 $r=Fresh 'invalid';[IO.File]::WriteAllBytes((Join-Path $r 'todo.txt'),[byte[]](0xc3,0x28));$o=Run @('backup','-Root',$r);Check 'invalid UTF8 refuses before backup creation' ($o.Code -eq 1 -and -not (Test-Path -LiteralPath ($r+'.fr-backup')))
 $r=Fresh 'utf16';[IO.File]::WriteAllBytes((Join-Path $r 'todo.txt'),[byte[]](65,0,66,0));$o=Run @('count','A','-Root',$r);Check 'NUL UTF16-like content refused' ($o.Code -eq 1)
 $r=Fresh 'same';Save $r;$o=Run @('apply','Project Bluebird','Project Bluebird','-Root',$r);Check 'same replacement changes zero bytes' ($o.Code -eq 0 -and $o.Text.Contains('0 files changed'))
 $r=Fresh 'emptyreplace';Save $r;$o=Run @('apply','Project Bluebird','','-Root',$r);Check 'empty replacement supported' ($o.Code -eq 0)
 $r=Fresh 'emptyfind';$o=Run @('count','','-Root',$r);Check 'empty find refused' ($o.Code -eq 1)
 $o=Run @('preview',"a`nb",'x','-Root',$r);Check 'multiline find refused' ($o.Code -eq 1)
 $r=Fresh 'literal';$a=Join-Path $r 'todo.txt';Put $a 'a.* $5 a.*';Save $r;$o=Run @('apply','a.*','$1','-Root',$r);Check 'regex and dollar tokens treated literally' ($o.Code -eq 0 -and [IO.File]::ReadAllText($a) -ceq '$1 $5 $1')
 $existing=Join-Path $temp 'existing-file';Put $existing 'KEEP';$h=Digest $existing;$o=Setup $existing;Check 'setup existing regular file preserved' ($o.Code -eq 1 -and (Digest $existing) -eq $h)
 $r=Fresh 'nested';$keep=Join-Path $r 'keep.bin';[IO.File]::WriteAllBytes($keep,[byte[]](0,1,255));$h=Digest $keep;$o=Setup $r;Check 'setup nested unrelated bytes preserved' ($o.Code -eq 1 -and (Digest $keep) -eq $h)
 $r=Fresh 'hardlink';$outside=Join-Path $temp 'outside.txt';Put $outside 'Project Bluebird';$h=Digest $outside
 $null=New-Item -ItemType HardLink -Path (Join-Path $r 'hard.txt') -Target $outside
 $o=Run @('backup','-Root',$r);Check 'hardlink refused and external bytes unchanged' ($o.Code -eq 1 -and (Digest $outside) -eq $h)
 $r=Fresh 'symlink'
 try { $null=New-Item -ItemType SymbolicLink -Path (Join-Path $r 'link.txt') -Target $outside; $can=$true } catch { $can=$false }
 if ($can) {
  $o=Run @('backup','-Root',$r);Check 'file symlink refuses before backup' ($o.Code -eq 1 -and -not (Test-Path -LiteralPath ($r+'.fr-backup')))
  $linkroot=Join-Path $temp 'root-link';$null=New-Item -ItemType SymbolicLink -Path $linkroot -Target $r
  $o=Run @('count','Project Bluebird','-Root',$linkroot);Check 'linked root refused' ($o.Code -eq 1)
  $r=Fresh 'dangling';$null=New-Item -ItemType SymbolicLink -Path ($r+'.fr-backup') -Target (Join-Path $temp 'missing-target')
  $o=Run @('backup','-Root',$r);Check 'dangling backup link refused without target creation' ($o.Code -eq 1 -and -not [IO.Directory]::Exists((Join-Path $temp 'missing-target')))
 } else { $script:skipped++; 'SKIP: symbolic links unavailable in this runner' }
 if (-not $IsWindows) {
  $r=Fresh 'case-collision';Put (Join-Path $r 'READMe.txt') 'other';$o=Run @('backup','-Root',$r);Check 'case-colliding names refused' ($o.Code -eq 1)
  $r=Fresh 'pipe'; & mkfifo (Join-Path $r 'pipe.txt');$o=Run @('count','x','-Root',$r);Check 'named pipe rejected without blocking' ($o.Code -eq 1)
 } else { $script:skipped++; 'SKIP: Unix case-collision and pipe checks not applicable' }
 $r=Fresh 'failure';Save $r
 # Test-only copied script injects a deterministic second-write failure.
 $fault=Join-Path $temp 'fault.ps1'
 $source=[IO.File]::ReadAllText($fr)
 $needle='[IO.File]::Move($tmp,$p,$true)'
 $injection='$script:writes++; if ($script:writes -eq 2) { throw "fixture write failure" }; [IO.File]::Move($tmp,$p,$true)'
 # Initializer must follow param block. Use declaration at existing ErrorAction line.
 Put $fault ($source.Replace("$"+'ErrorActionPreference=',"$"+'script:writes=0; $ErrorActionPreference=').Replace($needle,$injection))
 $o=& pwsh -NoProfile -File $fault apply 'Project Bluebird' 'Project Heron' -Root $r 2>&1
 Check 'injected mid-apply failure returns nonzero' ($LASTEXITCODE -eq 1 -and ($o -join "`n").Contains('fixture write failure'))
 Check 'journal retained after partial failure' (Test-Path -LiteralPath (Join-Path ($r+'.fr-backup') 'journal.json'))
 $o=Run @('diff','-Root',$r);Check 'partial apply changed exactly first file' ($o.Code -eq 0 -and $o.Text.Contains('Diff: 1 files changed, 2 unchanged'))
 $o=Run @('undo','-Root',$r);Check 'original tool recovers injected partial operation' ($o.Code -eq 0)
 $o=Run @('diff','-Root',$r);Check 'partial-failure recovery restores every selected byte' ($o.Code -eq 0 -and $o.Text.Contains('Diff: 0 files changed, 3 unchanged'))
 $r=Fresh 'missingjournal';Save $r;$o=Run @('undo','-Root',$r);Check 'undo without operation refuses' ($o.Code -eq 1)
 $r=Fresh 'traversal'; $o=Run @('count','x','-Root',(Join-Path $r '../traversal'));Check 'parent-traversal root refused' ($o.Code -eq 1 -and $o.Text.Contains('Parent-traversal'))
 $r=Fresh 'large';[IO.File]::WriteAllBytes((Join-Path $r 'large.txt'),[byte[]]::new(1048577));$o=Run @('backup','-Root',$r);Check 'oversized selected file refused' ($o.Code -eq 1)
} catch { $script:bad++; 'TEST HARNESS ERROR: '+$_.Exception.Message }
finally { Remove-Item -LiteralPath $temp -Recurse -Force }
"Results: $script:n checks, $script:bad failures, $script:skipped skipped groups"
if ($script:bad) { exit 1 };exit 0
