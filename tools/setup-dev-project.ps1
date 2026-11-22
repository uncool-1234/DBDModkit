# Prepares the dev project of the folder layout (README.md): copies the template's Config into the project when it has none,
# and links Plugins\Suzie and Plugins\<game plugin> to their sources with directory junctions. Existing items are left alone.
param(
  [string]$ProjectDir = '',      # default: DBDMount next to this script's tools folder
  [string]$SuzieRoot = '',       # default: the only folder in the root with Suzie.uplugin
  [string]$ProfileName = 'DBD'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
if (-not $ProjectDir) { $ProjectDir = Join-Path $root 'DBDMount' }
if (-not (Get-ChildItem $ProjectDir -Filter *.uproject -ErrorAction SilentlyContinue)) { throw "no .uproject in $ProjectDir" }
if (-not $SuzieRoot) {
  $s = @(Get-ChildItem $root -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'Suzie.uplugin') })
  if ($s.Count -ne 1) { throw "pass -SuzieRoot (folders with Suzie.uplugin in $root`: $($s.Count))" }
  $SuzieRoot = $s[0].FullName
}
$prof = Join-Path $root "Profiles\$ProfileName"
$pkg = Get-Content (Join-Path $prof 'packaging.json') -Raw | ConvertFrom-Json
$template = (Resolve-Path (Join-Path $prof $pkg.template)).Path
$gamePlugin = (Resolve-Path (Join-Path $prof $pkg.game_plugin)).Path

$config = Join-Path $ProjectDir 'Config'
if (Test-Path $config) { "Config: present" } else { Copy-Item (Join-Path $template 'Config') $config -Recurse; "Config: copied from $template" }

$plugins = Join-Path $ProjectDir 'Plugins'
New-Item -ItemType Directory -Force $plugins | Out-Null
foreach ($link in @(@{ Name = 'Suzie'; Target = $SuzieRoot }, @{ Name = (Split-Path -Leaf $gamePlugin); Target = $gamePlugin })) {
  $path = Join-Path $plugins $link.Name
  if (Test-Path $path) { "Plugins\$($link.Name): present" }
  else { New-Item -ItemType Junction -Path $path -Target $link.Target | Out-Null; "Plugins\$($link.Name) -> $($link.Target)" }
}
