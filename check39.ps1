# Independent check of the three known fictional files, not a real-data validator.
# Run snapshot before apply, then verify after undo. No existing manifest replaced.
#requires -Version 7.4
param([ValidateSet('snapshot','verify')][string]$Mode)
$ErrorActionPreference='Stop'
try {
 $root=Join-Path $PSScriptRoot 'notes'
 $names=@('archive/old-plan.txt','readme.txt','todo.txt')
 $actual=@(Get-ChildItem -LiteralPath $root -File -Recurse -Force | ForEach-Object { [IO.Path]::GetRelativePath($root,$_.FullName).Replace('\','/') } | Sort-Object -CaseSensitive)
 if (($actual -join '|') -cne ($names -join '|')) { throw 'Unexpected fictional-file inventory.' }
 $hashes=[ordered]@{}
 foreach ($rel in $names) { $hashes[$rel]=(Get-FileHash -LiteralPath (Join-Path $root $rel) -Algorithm SHA256).Hash }
 $manifest=Join-Path $PSScriptRoot 'fixture-digests.json'
 $utf8=[Text.UTF8Encoding]::new($false,$true)
 if ($Mode -eq 'snapshot') {
  if ($null -ne (Get-Item -LiteralPath $manifest -Force -ErrorAction SilentlyContinue)) { throw 'Digest manifest exists.' }
  $stream=[IO.File]::Open($manifest,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try { $b=$utf8.GetBytes(($hashes | ConvertTo-Json -Compress));$stream.Write($b,0,$b.Length) } finally { $stream.Dispose() }
  'Saved all three fictional-file SHA256 digests in a new manifest.'
 } else {
  $before=[IO.File]::ReadAllText($manifest) | ConvertFrom-Json -AsHashtable
  if ($before.Count -ne 3) { throw 'Unexpected digest manifest.' }
  foreach ($rel in $names) { if ($before[$rel] -cne $hashes[$rel]) { throw 'Fixture bytes differ.' }; "${rel}: original bytes match" }
  'PASS: all three original digests and selected names match. This is a fictional fixture check only.'
 }
 exit 0
} catch { 'Stopped: '+$_.Exception.Message;exit 1 }
