#requires -Version 7.4
# Run only in a new empty lesson folder, using PowerShell 7.4+.
param([string]$Root=(Join-Path $PSScriptRoot 'notes'))
$ErrorActionPreference='Stop'
try {
 if (($Root -split '[\\/]') -contains '..') { throw 'Parent-traversal setup paths are not supported.' }
 $Root=[IO.Path]::GetFullPath($Root)
 if ($null -ne (Get-Item -LiteralPath $Root -Force -ErrorAction SilentlyContinue)) { throw 'Sample path already exists. Nothing replaced.' }
 $p=[IO.Path]::GetDirectoryName($Root)
 while ($p) {
  $i=Get-Item -LiteralPath $p -Force
  if (($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $i.LinkType) { throw 'Linked parents are not supported.' }
  $p=[IO.Path]::GetDirectoryName($p)
 }
 $null=[IO.Directory]::CreateDirectory($Root)
 $null=[IO.Directory]::CreateDirectory((Join-Path $Root 'archive'))
 $utf8=[Text.UTF8Encoding]::new($false,$true)
 $data=[ordered]@{
  'readme.txt'="Project Bluebird kickoff`r`nOwner: fictional team`r`n"
  'todo.txt'="Review Project Bluebird notes`nKeep project bluebird unchanged`n"
  'archive/old-plan.txt'="Project Bluebird + Project Bluebird`r`nLiteral tokens: [draft] and `$5`r`n"
 }
 foreach ($rel in $data.Keys) {
  $stream=[IO.File]::Open((Join-Path $Root $rel),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try { $b=$utf8.GetBytes($data[$rel]);$stream.Write($b,0,$b.Length) } finally { $stream.Dispose() }
 }
 'Created three fictional UTF-8 files. Existing paths are refused.'
 exit 0
} catch { 'Stopped: '+$_.Exception.Message; exit 1 }
