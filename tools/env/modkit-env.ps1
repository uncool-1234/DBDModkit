# Dot-source: . "<root>\tools\env\modkit-env.ps1"  -> sets $env:MODKIT_ROOT (the project root, two levels above this file) unless it is already set.
if (-not $env:MODKIT_ROOT) { $env:MODKIT_ROOT = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
$script:Root = $env:MODKIT_ROOT
