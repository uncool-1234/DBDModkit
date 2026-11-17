# Project setup and editor start of a modkit project, called by "Setup Project.bat" (-Action setup) and "Start Editor.bat" (-Action start).
# setup writes ModkitData\ModkitLocal.ini: the engine, the profile, the game install and the user supplied files in ModkitData.
# start launches the editor with the paths from that file. Editor arguments come from MODKIT_EDITOR_ARGS (the .bat passes %* through it,
# because PowerShell would try to bind editor switches such as -foo as script parameters).
# Runs on Windows PowerShell 5.1.
param(
  [Parameter(Mandatory = $true)][ValidateSet('setup', 'start')][string]$Action,
  [switch]$NonInteractive
)
$ErrorActionPreference = 'Stop'

$ProjectDir = $PSScriptRoot
$DataDir    = Join-Path $ProjectDir 'ModkitData'
$LocalIni   = Join-Path $DataDir 'ModkitLocal.ini'
$BuildsKey  = 'HKCU:\Software\Epic Games\Unreal Engine\Builds'
$IniHeader  = '; Machine local paths of this project, written by "Setup Project.bat". Run it again after moving the engine, the game or the files in ModkitData.'

function Fail($msg) { Write-Host ''; Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }
function Warn($msg) { Write-Host "WARNING: $msg" -ForegroundColor Yellow }
function Info($msg) { Write-Host $msg }
function Slash($p) { if ($p) { $p.Replace('\', '/') } else { $p } }
function Full($p) { [IO.Path]::GetFullPath($p).TrimEnd('\', '/') }

function Ask($prompt) {
  if ($NonInteractive) { Fail "input needed ($prompt) but -NonInteractive is set" }
  (Read-Host $prompt).Trim().Trim('"')
}

function Get-Uproject {
  $u = @(Get-ChildItem -LiteralPath $ProjectDir -Filter *.uproject -File)
  if ($u.Count -ne 1) { Fail "expected exactly one .uproject in $ProjectDir, found $($u.Count)" }
  $u[0].FullName
}

function Read-Local {
  $h = @{}
  if (Test-Path -LiteralPath $LocalIni) {
    foreach ($l in Get-Content -LiteralPath $LocalIni) {
      if ($l -match '^\s*([^;#\[=][^=]*)=(.*)$') { $h[$matches[1].Trim()] = $matches[2].Trim() }
    }
  }
  $h
}

function Test-EngineDir($d) { $d -and (Test-Path -LiteralPath (Join-Path $d 'Engine\Binaries\Win64\UnrealEditor.exe')) }

# EngineAssociation is either a path (relative to the project) or a registered engine id.
function Get-Association($uproject) {
  $ea = (Get-Content -LiteralPath $uproject -Raw | ConvertFrom-Json).EngineAssociation
  if (-not $ea) { return $null }
  if ($ea -match '[\\/]' -or $ea.StartsWith('.')) {
    $p = if ([IO.Path]::IsPathRooted($ea)) { $ea } else { Join-Path $ProjectDir $ea }
    return [pscustomobject]@{ Id = $null; Path = (Full $p) }
  }
  $reg = $null
  $k = Get-ItemProperty -LiteralPath $BuildsKey -ErrorAction SilentlyContinue
  if ($k -and ($k.PSObject.Properties.Name -contains $ea)) { $reg = $k.$ea }
  [pscustomobject]@{ Id = $ea; Path = $reg }
}

function Find-Engine($uproject, $local, [switch]$Search) {
  $cands = @()
  if ($env:MODKIT_ENGINE) { $cands += ,@($env:MODKIT_ENGINE, 'MODKIT_ENGINE') }
  if ($local['EngineDir']) { $cands += ,@($local['EngineDir'], 'ModkitLocal.ini EngineDir') }
  $a = Get-Association $uproject
  if ($a -and $a.Path) { $cands += ,@($a.Path, $(if ($a.Id) { "registered engine '$($a.Id)'" } else { 'EngineAssociation of the .uproject' })) }
  if ($Search) {
    $parent = Split-Path -Parent $ProjectDir
    foreach ($d in Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue) { $cands += ,@($d.FullName, 'folder next to the project') }
  }
  foreach ($c in $cands) { if (Test-EngineDir $c[0]) { return [pscustomobject]@{ Dir = (Full $c[0]); Source = $c[1] } } }
  $null
}

function Find-Profiles($engine) {
  $roots = @((Join-Path $ProjectDir 'Plugins\Suzie'), (Join-Path $engine 'Engine\Plugins\Modkit\Suzie'))
  foreach ($r in $roots) {
    if (Test-Path -LiteralPath (Join-Path $r 'Suzie.uplugin')) {
      $p = @(Get-ChildItem -LiteralPath (Join-Path $r 'Profiles') -Directory -ErrorAction SilentlyContinue |
             Where-Object { (Test-Path (Join-Path $_.FullName 'profile.json')) -and (Test-Path (Join-Path $_.FullName 'engine.ini')) -and (Test-Path (Join-Path $_.FullName 'project.json')) } |
             ForEach-Object { Full $_.FullName })
      return $p
    }
  }
  @()
}

function Choose($title, $items) {
  if ($items.Count -eq 1) { return $items[0] }
  Info $title
  for ($i = 0; $i -lt $items.Count; $i++) { Info ("  [{0}] {1}" -f ($i + 1), $items[$i]) }
  while ($true) {
    $n = Ask 'Number'
    if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $items.Count) { return $items[[int]$n - 1] }
  }
}

function Find-GameInstalls($game) {
  $found = @()
  $steam = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
  if ($steam -and $game.steam_app_id) {
    $libs = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
      foreach ($l in Get-Content -LiteralPath $vdf) { if ($l -match '^\s*"path"\s+"(.+)"') { $libs += $matches[1].Replace('\\', '\') } }
    }
    foreach ($lib in ($libs | Select-Object -Unique)) {
      $acf = Join-Path $lib "steamapps\appmanifest_$($game.steam_app_id).acf"
      if (Test-Path -LiteralPath $acf) {
        $m = Select-String -LiteralPath $acf -Pattern '^\s*"installdir"\s+"(.+)"' | Select-Object -First 1
        if ($m) { $found += ,@((Join-Path $lib "steamapps\common\$($m.Matches[0].Groups[1].Value)"), 'Steam') }
      }
    }
  }
  if ($game.epic_display_name) {
    $man = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    foreach ($f in Get-ChildItem -LiteralPath $man -Filter *.item -ErrorAction SilentlyContinue) {
      try { $j = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json } catch { continue }
      if ($j.DisplayName -eq $game.epic_display_name -and $j.InstallLocation) { $found += ,@($j.InstallLocation, 'Epic Games') }
    }
  }
  $found
}

function Test-GameRoot($game, $d) { $d -and (Test-Path -LiteralPath (Join-Path $d $game.probe)) }

function Invoke-Setup {
  $uproject = Get-Uproject
  Info "Project: $uproject"
  if (-not (Test-Path -LiteralPath $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null; Info "Created $DataDir" }
  $local = Read-Local

  # Engine
  $eng = Find-Engine $uproject $local -Search
  if (-not $eng) {
    Info 'No engine found (MODKIT_ENGINE, the .uproject EngineAssociation, folders next to the project).'
    while (-not $eng) {
      $d = Ask 'Path of the engine folder (the folder that contains Engine)'
      if (Test-EngineDir $d) { $eng = [pscustomobject]@{ Dir = (Full $d); Source = 'entered' } } else { Warn "no Engine\Binaries\Win64\UnrealEditor.exe under '$d'" }
    }
  }
  Info "Engine: $($eng.Dir) ($($eng.Source))"
  $a = Get-Association $uproject
  if ($a -and $a.Id -and $eng.Source -ne 'MODKIT_ENGINE' -and ((-not $a.Path) -or ((Full $a.Path) -ne $eng.Dir))) {
    if ($NonInteractive) { Warn "engine id '$($a.Id)' is not registered to $($eng.Dir); run Setup Project.bat interactively or 'Register Engine.bat' in the engine folder to register it." }
    elseif ((Ask "Register this engine as '$($a.Id)' for the current user (double-click the .uproject, Switch Engine Version)? [Y/n]") -notmatch '^[nN]') {
      if (-not (Test-Path -LiteralPath $BuildsKey)) { New-Item -Path $BuildsKey -Force | Out-Null }
      Set-ItemProperty -LiteralPath $BuildsKey -Name $a.Id -Value $eng.Dir
      Info "Registered '$($a.Id)' = $($eng.Dir)"
    }
  }

  # Profile
  $profiles = @(Find-Profiles $eng.Dir)
  if ($profiles.Count -eq 0) { Fail "no profile (a folder with profile.json, engine.ini and project.json) under the Suzie plugin of the project or of $($eng.Dir)" }
  $prof = $null
  if ($local['Profile']) { $cur = Full $local['Profile']; if ($profiles -contains $cur) { $prof = $cur } }
  if (-not $prof) { $prof = Choose 'Profiles:' $profiles }
  Info "Profile: $prof"
  $spec = Get-Content -LiteralPath (Join-Path $prof 'project.json') -Raw | ConvertFrom-Json

  # Files in ModkitData: at most one file per expected extension, keyed by extension.
  $files = @(Get-ChildItem -LiteralPath $DataDir -File | Where-Object { $_.Name -ne 'ModkitLocal.ini' })
  $exts = @($spec.data_files | ForEach-Object { $_.extension.ToLowerInvariant() })
  $errors = @()
  foreach ($df in $spec.data_files) {
    $m = @($files | Where-Object { $_.Extension.ToLowerInvariant() -eq $df.extension.ToLowerInvariant() })
    if ($m.Count -gt 1) { $errors += "ModkitData holds $($m.Count) *$($df.extension) files ($(($m | ForEach-Object Name) -join ', ')); keep exactly one ($($df.description))." }
  }
  foreach ($f in $files) { if ($exts -notcontains $f.Extension.ToLowerInvariant()) { Warn "ModkitData\$($f.Name) is not an expected file (expected: $(($exts | ForEach-Object { "*$_" }) -join ', ')); it is ignored." } }
  foreach ($d in Get-ChildItem -LiteralPath $DataDir -Directory) { Warn "ModkitData\$($d.Name)\ is a folder; it is ignored." }
  if ($errors.Count) { foreach ($e in $errors) { Write-Host "ERROR: $e" -ForegroundColor Red }; Fail 'fix ModkitData and run Setup Project.bat again' }

  $values = [ordered]@{}
  foreach ($df in $spec.data_files) {
    $m = @($files | Where-Object { $_.Extension.ToLowerInvariant() -eq $df.extension.ToLowerInvariant() })
    $v = $null
    if ($m.Count -eq 1) { $v = $m[0].FullName; Info "$($df.key): $v (ModkitData)" }
    elseif ($local[$df.key] -and (Test-Path -LiteralPath $local[$df.key] -PathType Leaf)) { $v = Full $local[$df.key]; Info "$($df.key): $v (existing ModkitLocal.ini)" }
    elseif ($df.required) {
      Info "No *$($df.extension) file in $DataDir. Put the $($df.description) there, or enter its path."
      while (-not $v) {
        $p = Ask "Path of the $($df.key) file"
        if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { $v = Full $p } else { Warn "file not found: '$p'" }
      }
      Info "$($df.key): $v"
    }
    else { Info "$($df.key): not set (optional: $($df.description))" }
    if ($v) { $values[$df.key] = $v }
  }

  # Game install
  $game = $spec.game
  $root = $null
  if (Test-GameRoot $game $local['GameRoot']) { $root = Full $local['GameRoot']; Info "GameRoot: $root (existing ModkitLocal.ini)" }
  else {
    $found = @(Find-GameInstalls $game | Where-Object { Test-GameRoot $game $_[0] })
    $paths = @($found | ForEach-Object { Full $_[0] } | Select-Object -Unique)
    if ($paths.Count -ge 1) {
      $root = Choose "$($game.name) installs found:" $paths
      $via = @($found | Where-Object { (Full $_[0]) -eq $root } | ForEach-Object { $_[1] })[0]
      Info "GameRoot: $root (found via $via)"
    }
    else {
      Info "$($game.name) was not found in the Steam or Epic Games libraries."
      while (-not $root) {
        $p = Ask "Path of the $($game.name) install folder (it contains $($game.probe.Replace('/', '\')))"
        if (Test-GameRoot $game $p) { $root = Full $p } else { Warn "'$p' does not contain $($game.probe)" }
      }
      Info "GameRoot: $root"
    }
  }

  # Write, keeping lines this script does not manage (other keys, comments).
  $managed = @('Profile', 'EngineDir', 'GameRoot') + @($spec.data_files | ForEach-Object { $_.key })
  $keep = @()
  if (Test-Path -LiteralPath $LocalIni) {
    foreach ($l in Get-Content -LiteralPath $LocalIni) {
      if ($l -eq $IniHeader -or $l.Trim() -eq '[Local]') { continue }
      if ($l -match '^\s*([^;#\[=][^=]*)=' -and ($managed -contains $matches[1].Trim())) { continue }
      $keep += $l
    }
    while ($keep.Count -and -not $keep[0].Trim()) { $keep = @($keep | Select-Object -Skip 1) }
  }
  $out = @($IniHeader, '[Local]', "Profile=$(Slash $prof)", "EngineDir=$(Slash $eng.Dir)", "GameRoot=$(Slash $root)")
  foreach ($k in $values.Keys) { $out += "$k=$(Slash $values[$k])" }
  if ($keep.Count) { $out += ''; $out += $keep }
  Set-Content -LiteralPath $LocalIni -Value $out -Encoding UTF8
  Info ''
  Info "Wrote $LocalIni"
  Info 'Start the editor with "Start Editor.bat".'
}

function Invoke-Start {
  $uproject = Get-Uproject
  if (-not (Test-Path -LiteralPath $LocalIni)) { Fail "$LocalIni does not exist. Run ""Setup Project.bat"" first." }
  $local = Read-Local
  $eng = Find-Engine $uproject $local
  if (-not $eng) { Fail 'engine not found. Run "Setup Project.bat" again.' }
  $missing = @()
  foreach ($k in @('Profile', 'GameRoot')) { if (-not $local[$k] -or -not (Test-Path -LiteralPath $local[$k])) { $missing += "$k=$($local[$k])" } }
  $pj = if ($local['Profile']) { Join-Path $local['Profile'] 'project.json' } else { $null }
  if ($pj -and (Test-Path -LiteralPath $pj)) {
    foreach ($df in (Get-Content -LiteralPath $pj -Raw | ConvertFrom-Json).data_files) {
      $v = $local[$df.key]
      if (($df.required -and -not $v) -or ($v -and -not (Test-Path -LiteralPath $v -PathType Leaf))) { $missing += "$($df.key)=$v" }
    }
  }
  if ($missing.Count) { Fail "ModkitData\ModkitLocal.ini points to missing paths: $($missing -join '; '). Run ""Setup Project.bat"" again." }
  ${env:UE-LocalDataCachePath} = Join-Path $ProjectDir 'DDC'
  $exe = Join-Path $eng.Dir 'Engine\Binaries\Win64\UnrealEditor.exe'
  $editorArgs = "`"$uproject`" -log -d3d12 -sm5"
  if ($env:MODKIT_EDITOR_ARGS) { $editorArgs += " $env:MODKIT_EDITOR_ARGS" }
  Info "Starting $exe"
  Start-Process -FilePath $exe -ArgumentList $editorArgs -WorkingDirectory $ProjectDir | Out-Null
}

if ($Action -eq 'setup') { Invoke-Setup } else { Invoke-Start }
