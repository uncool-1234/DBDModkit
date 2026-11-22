# Runs the Suzie repository's layer check with this game's names. Exit 1 when a tracked Suzie file names the game or studio.
param([string]$SuzieRoot = '')
$root = Split-Path $PSScriptRoot
if (-not $SuzieRoot) {
  $s = @(Get-ChildItem $root -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'Suzie.uplugin') })
  if ($s.Count -ne 1) { Write-Host "pass -SuzieRoot (folders with Suzie.uplugin in $root`: $($s.Count))"; exit 2 }
  $SuzieRoot = $s[0].FullName
}
& (Join-Path $SuzieRoot 'Tools\check-layers.ps1') -Pattern 'DBD|BHVR|Bhvr|DeadByDaylight|Dead by Daylight'
exit $LASTEXITCODE
