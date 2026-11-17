# Builds, assembles and archives a release of the modkit engine for one profile. Entry point: publish-engine.cmd.
#
# Stages (each writes a marker under <WorkDir>\state and is skipped on the next run while the engine and Suzie commits are unchanged):
#   source    copy of the engine tree without .git/Intermediate/Saved, plus Suzie and the profile's game plugin under Engine\Plugins\Modkit
#   build     BuildGraph "Make Installed Build Win64" (build-installed.cmd)
#   assemble  trimmed engine, profile, tools, Register Engine.bat, project template, setup guide, VERSION.txt under <WorkDir>\Release
#   safety    removes forbidden files (game data, key files, machine local ini) from the release folder, checks required files
#   smoke     optional: project setup and one editor start (verify, tag probe, golden dump) from the release folder
#   archive   encrypted .7z (AES-256, encrypted file names) with .sha256 and .password.txt next to it
#
# Game specific values come from <profile>\packaging.json and <profile>\project.json.
# Runs on Windows PowerShell 5.1.
param(
  [string]$ProfileName = '',        # profile folder under Suzie-fork\Profiles; default: the only one
  [string]$WorkDir = '',            # default: <workspace>-Publish next to the workspace root
  [string]$OutDir = '',             # default: <WorkDir>\Releases
  [string]$EngineSource = '',       # default: the only UnrealEngine-*-fork folder in the workspace root
  [string]$Password = '',           # archive password; default: random 16 characters A-Za-z0-9
  [switch]$SmokeTest,
  [switch]$NoSmokeTest,
  [string]$SmokeData = '',          # a ModkitData folder whose ModkitLocal.ini supplies GameRoot, KeyFile, Jmap; default: the only one in the workspace root
  [string]$UbaHost = '',
  [switch]$Clean,                   # forget all stage markers and the BuildGraph cache
  [switch]$RemoveBuildFiles,        # after a successful run delete the build copy and the raw installed build
  [switch]$NonInteractive
)
$ErrorActionPreference = 'Stop'

$SuzieRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Root = if ($env:MODKIT_ROOT) { $env:MODKIT_ROOT } else { (Resolve-Path (Join-Path $SuzieRoot '..')).Path }
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogDir = Join-Path $Root "logs\publish-$Stamp"
New-Item -ItemType Directory -Force $LogDir | Out-Null
$Timings = New-Object System.Collections.ArrayList

function Fail($msg) { Write-Host ''; Write-Host "ERROR: $msg" -ForegroundColor Red; try { Stop-Transcript | Out-Null } catch {}; exit 1 }
function Warn($msg) { Write-Host "WARNING: $msg" -ForegroundColor Yellow }
function Info($msg) { Write-Host $msg }
function Head($msg) { Write-Host ''; Write-Host "== $msg" -ForegroundColor Cyan }
function Ask($prompt) { if ($NonInteractive) { return '' }; (Read-Host $prompt).Trim() }
# git writes warnings to stderr; with 'Stop' Windows PowerShell would turn them into terminating errors.
function Git($repo) {
  $ErrorActionPreference = 'Continue'
  $out = @(& git -C $repo @args 2>&1 | ForEach-Object { "$_" })
  if ($LASTEXITCODE) { Fail "git -C $repo $($args -join ' '): $($out -join ' ')" }
  $out | Where-Object { $_ -and $_ -notmatch '^warning: ' }
}
function Test-Ancestor($repo, $branch) { $ErrorActionPreference = 'Continue'; & git -C $repo merge-base --is-ancestor $branch HEAD 2>$null; $LASTEXITCODE -eq 0 }

function Robo($from, $to, [string[]]$opts) {
  $log = Join-Path $LogDir ("robocopy-{0}.log" -f ($Timings.Count))
  & robocopy $from $to @opts /NP /NFL /NDL "/UNILOG+:$log" | Out-Null
  if ($LASTEXITCODE -ge 8) { Fail "robocopy $from -> $to failed (exit $LASTEXITCODE), see $log" }
}

function New-Password {
  $chars = [char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  $b = New-Object byte[] 1
  $s = ''
  while ($s.Length -lt 16) { $rng.GetBytes($b); if ($b[0] -lt 248) { $s += $chars[$b[0] % 62] } }   # 248 = 4 * 62: no modulo bias
  $s
}

# ---------------------------------------------------------------- configuration

$profiles = @(Get-ChildItem (Join-Path $SuzieRoot 'Profiles') -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'packaging.json') } | ForEach-Object Name)
if (-not $ProfileName) {
  if ($profiles.Count -ne 1) { Fail "pass -ProfileName (profiles with packaging.json: $($profiles -join ', '))" }
  $ProfileName = $profiles[0]
}
$Prof = Join-Path $SuzieRoot "Profiles\$ProfileName"
if (-not (Test-Path (Join-Path $Prof 'packaging.json'))) { Fail "$Prof\packaging.json does not exist" }
$Pkg = Get-Content (Join-Path $Prof 'packaging.json') -Raw | ConvertFrom-Json
$Proj = Get-Content (Join-Path $Prof 'project.json') -Raw | ConvertFrom-Json
$Template = (Resolve-Path (Join-Path $Prof $Pkg.template)).Path
$Guide = (Resolve-Path (Join-Path $Prof $Pkg.setup_guide)).Path
$GamePlugin = (Resolve-Path (Join-Path $Prof $Pkg.game_plugin)).Path
$GamePluginName = Split-Path -Leaf $GamePlugin

if (-not $EngineSource) {
  $forks = @(Get-ChildItem $Root -Directory -Filter 'UnrealEngine-*-fork')
  if ($forks.Count -ne 1) { Fail "pass -EngineSource (UnrealEngine-*-fork folders in $Root`: $($forks.Count))" }
  $EngineSource = $forks[0].FullName
}
if (-not $WorkDir) { $WorkDir = Join-Path (Split-Path -Parent $Root) ((Split-Path -Leaf $Root) + '-Publish') }
if (-not $OutDir) { $OutDir = Join-Path $WorkDir 'Releases' }
$Src = Join-Path $WorkDir 'Source'
$Installed = Join-Path $WorkDir 'Installed'
$Release = Join-Path $WorkDir "Release\$($Pkg.release_name)"
$EngOut = Join-Path $Release $Pkg.engine_folder
$TemplateOut = Join-Path $Release (Split-Path -Leaf $Template)
$StateDir = Join-Path $WorkDir 'state'
$SevenZip = @((Get-Command 7z.exe -ErrorAction SilentlyContinue | ForEach-Object Source), "$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
$PdbCopy = @("${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\pdbcopy.exe", "$env:ProgramFiles\Windows Kits\10\Debuggers\x64\pdbcopy.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($SmokeTest -and $NoSmokeTest) { Fail 'pass -SmokeTest or -NoSmokeTest, not both' }
$RunSmoke = [bool]$SmokeTest
if (-not $SmokeTest -and -not $NoSmokeTest -and -not $NonInteractive) {
  $RunSmoke = (Ask 'Run the smoke test (project setup and one editor start from the release folder; the first start builds its DDC, 15 to 30 minutes)? [y/N]') -match '^[yY]'
}
if ($RunSmoke -and -not $SmokeData) {
  $cands = @(Get-ChildItem $Root -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'ModkitData\ModkitLocal.ini') } | ForEach-Object { Join-Path $_.FullName 'ModkitData' })
  if ($cands.Count -ne 1) { Fail "pass -SmokeData <ModkitData folder> (folders with ModkitData\ModkitLocal.ini in $Root`: $($cands.Count))" }
  $SmokeData = $cands[0]
}
if (-not $Password -and -not $NonInteractive) { $Password = Ask 'Archive password (Enter for a random 16 character password)' }
if (-not $Password) { $Password = New-Password }
if ($Password -match '"') { Fail 'the password must not contain a double quote' }

Start-Transcript -Path (Join-Path $LogDir 'publish.log') | Out-Null
Head 'Configuration'
Info "Profile:        $Prof"
Info "Engine source:  $EngineSource ($($Pkg.engine_branch))"
Info "Suzie:          $SuzieRoot"
Info "Work folder:    $WorkDir"
Info "Archive folder: $OutDir"
Info "Smoke test:     $(if ($RunSmoke) { "yes, game data from $SmokeData" } else { 'no' })"
Info "pdbcopy:        $(if ($PdbCopy) { $PdbCopy } else { 'not found: symbols are copied unstripped' })"
Info "Logs:           $LogDir"
if (-not $NonInteractive -and (Ask 'Continue? [Y/n]') -match '^[nN]') { Fail 'cancelled' }

# ---------------------------------------------------------------- preflight

Head 'Preflight'
$branch = (Git $EngineSource rev-parse --abbrev-ref HEAD) | Select-Object -First 1
if ($branch -ne $Pkg.engine_branch) { Fail "$EngineSource is on '$branch', expected '$($Pkg.engine_branch)'" }
foreach ($b in $Pkg.engine_merged_branches) {
  if (-not (Test-Ancestor $EngineSource $b)) { Fail "$b is not merged into $($Pkg.engine_branch)" }
}
foreach ($repo in @($EngineSource, $SuzieRoot)) {
  $dirty = @(Git $repo status --porcelain)
  if ($dirty.Count) { Fail "$repo has uncommitted changes:`n$($dirty -join "`n")" }
}
$EngineCommit = (Git $EngineSource rev-parse HEAD) | Select-Object -First 1
$SuzieCommit = (Git $SuzieRoot rev-parse HEAD) | Select-Object -First 1
$Fingerprint = "engine=$EngineCommit suzie=$SuzieCommit profile=$ProfileName"
$assoc = (Get-Content (Get-ChildItem $Template -Filter *.uproject | Select-Object -First 1).FullName -Raw | ConvertFrom-Json).EngineAssociation
if ($assoc -ne $Proj.engine_id) { Fail "the template's EngineAssociation '$assoc' differs from project.json engine_id '$($Proj.engine_id)'" }
if (-not $SevenZip) { Fail '7-Zip (7z.exe) not found' }
Info "Engine $EngineCommit, Suzie $SuzieCommit, 7-Zip $SevenZip"

New-Item -ItemType Directory -Force $StateDir, $OutDir | Out-Null
$stale = @(Get-ChildItem $StateDir -Filter *.done | Where-Object { (Get-Content $_.FullName -Raw).Trim() -ne $Fingerprint })
if ($Clean -or $stale.Count) {
  if ($stale.Count -and -not $Clean) { Warn 'the commits changed since the last run: all stages run again' }
  Get-ChildItem $StateDir -Filter *.done | Remove-Item -Force
  $bgCache = Join-Path $Src 'Engine\Saved'
  if (Test-Path $bgCache) { Info "Removing the BuildGraph cache $bgCache"; cmd /c rmdir /s /q "`"$bgCache`"" }
}
function Done($stage) { Test-Path (Join-Path $StateDir "$stage.done") }

if (-not (Done 'build')) {
  $ubt = @(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'UnrealBuildTool|AutomationTool' })
  if ($ubt.Count) { Fail "UnrealBuildTool/AutomationTool is running (pid $(($ubt | ForEach-Object ProcessId) -join ', ')); one build at a time" }
  $need = 350GB
} else { $need = 60GB }
$drive = Get-PSDrive -Name (Split-Path -Qualifier $WorkDir).TrimEnd(':')
if ($drive.Free -lt $need) { Fail ("{0} has {1:N0} GB free, the remaining stages need about {2:N0} GB" -f $WorkDir, ($drive.Free / 1GB), ($need / 1GB)) }

$Tag = @(Git $EngineSource tag --points-at HEAD | Where-Object { $_ -like "$($Pkg.release_name)-*" }) | Select-Object -First 1
if (-not $Tag) {
  $base = "$($Pkg.release_name)-$(Get-Date -Format yyyyMMdd)"; $Tag = $base; $n = 2
  while (@(Git $EngineSource tag --list $Tag).Count -or @(Git $SuzieRoot tag --list $Tag).Count) { $Tag = "$base-$n"; $n++ }
  Git $EngineSource tag $Tag | Out-Null
  Info "Tagged the engine commit $Tag"
}
if (-not @(Git $SuzieRoot tag --list $Tag).Count) { Git $SuzieRoot tag $Tag | Out-Null; Info "Tagged the Suzie commit $Tag" }

function Stage($name, [scriptblock]$body, [switch]$Always) {
  Head $name
  if (-not $Always -and (Done $name)) { Info 'done in an earlier run, skipped'; [void]$Timings.Add([pscustomobject]@{ Stage = $name; Result = 'skipped'; Minutes = 0 }); return }
  $t = Get-Date
  & $body
  Set-Content (Join-Path $StateDir "$name.done") $Fingerprint
  [void]$Timings.Add([pscustomobject]@{ Stage = $name; Result = 'ok'; Minutes = [math]::Round(((Get-Date) - $t).TotalMinutes, 1) })
}

# ---------------------------------------------------------------- stages

Stage 'source' {
  Info "Copying $EngineSource -> $Src"
  Robo $EngineSource $Src @('/MIR', '/MT:16', '/R:2', '/W:5', '/XD', (Join-Path $EngineSource '.git'), 'Intermediate', 'Saved', '/XF', '.git')
  $modkit = Join-Path $Src 'Engine\Plugins\Modkit'
  Info "Copying Suzie -> $modkit\Suzie"
  Robo $SuzieRoot (Join-Path $modkit 'Suzie') @('/MIR', '/MT:16', '/XD', (Join-Path $SuzieRoot '.git'), (Join-Path $SuzieRoot 'Packaging'), (Join-Path $SuzieRoot 'Profiles'), (Join-Path $SuzieRoot 'Tools'), 'Binaries', 'Intermediate', '__pycache__', '/XF', '.git*')
  Info "Copying $GamePluginName -> $modkit\$GamePluginName"
  Robo $GamePlugin (Join-Path $modkit $GamePluginName) @('/MIR', '/XD', 'Binaries', 'Intermediate', '__pycache__')
  if (-not $PdbCopy) {
    $xml = Join-Path $Src 'Engine\Build\InstalledEngineBuild.xml'
    $s = [IO.File]::ReadAllText($xml)
    $re = '<Strip Files="#Strip Tools for Installed Win64"[^>]*/>'
    if ([regex]::Matches($s, $re).Count -ne 1) { Fail "expected one '#Strip Tools for Installed Win64' step in $xml" }
    $s = [regex]::Replace($s, $re, '<Copy Files="#Strip Tools for Installed Win64" From="$(RootDir)" To="$(LocalInstalledDir)" Tag="#Installed Build Win64 Files"/>')
    [IO.File]::WriteAllText($xml, $s)
    Info 'InstalledEngineBuild.xml of the build copy: the strip step copies symbols unstripped (no pdbcopy.exe)'
  }
}

Stage 'build' {
  Info 'BuildGraph: Make Installed Build Win64 (several hours)'
  $env:BUILD_SRC = $Src; $env:OUT_DIR = $Installed; $env:LOG_DIR = $LogDir; $env:UBA_HOST = $UbaHost; $env:MODKIT_ROOT = $Root
  & cmd /c "`"$PSScriptRoot\build-installed.cmd`""
  $rc = $LASTEXITCODE
  $log = Join-Path $LogDir 'installed_build.log'
  if ($rc -ne 0 -or -not (Select-String -Path $log -Pattern 'BUILD SUCCESSFUL' -SimpleMatch -Quiet)) { Fail "the installed build failed (exit $rc), see $log" }
  if (-not (Test-Path (Join-Path $Installed 'Windows\Engine\Binaries\Win64\UnrealEditor.exe'))) { Fail "no UnrealEditor.exe under $Installed\Windows" }
}

Stage 'assemble' {
  $raw = Join-Path $Installed 'Windows'
  Info "Trimmed engine: $raw -> $EngOut (without *.pdb, *.obj, Documentation, Templates, FeaturePacks)"
  Robo $raw $EngOut @('/MIR', '/XJ', '/COPY:DAT', '/DCOPY:DAT', '/R:2', '/W:5', '/MT:16', '/XF', '*.pdb', '*.obj', '/XD', 'Documentation', 'Templates', 'FeaturePacks')
  $suzieOut = Join-Path $EngOut 'Engine\Plugins\Modkit\Suzie'
  Info "Profile $ProfileName and Tools -> $suzieOut"
  Robo $Prof (Join-Path $suzieOut "Profiles\$ProfileName") @('/MIR', '/XD', (Join-Path $Prof 'Plugin'), '__pycache__')
  Robo (Join-Path $SuzieRoot 'Tools') (Join-Path $suzieOut 'Tools') @('/MIR', '/XD', 'bin', 'obj', '__pycache__')
  $reg = (Get-Content (Join-Path $PSScriptRoot 'EngineRoot\Register Engine.bat') -Raw).Replace('@ENGINE_ID@', $Proj.engine_id)
  [IO.File]::WriteAllText((Join-Path $EngOut 'Register Engine.bat'), $reg)
  Info "Template -> $TemplateOut"
  Robo $Template $TemplateOut @('/MIR', '/XD', 'ModkitData', 'DDC', 'DerivedDataCache', 'Saved', 'Intermediate', 'Binaries')
  Copy-Item $Guide (Join-Path $Release (Split-Path -Leaf $Guide)) -Force
  $suzieLog = (Git $SuzieRoot log -1 --format='%h %s') | Select-Object -First 1
  $engineLog = (Git $EngineSource log -1 --format='%h %s') | Select-Object -First 1
  @(
    "$($Pkg.release_name) ($Tag)",
    "Built:            $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    "Engine:           $($Pkg.engine_branch) $engineLog",
    "Suzie:            $suzieLog",
    "Profile:          $ProfileName",
    "Game version:     $($Pkg.game_version)",
    "Engine folder:    $($Pkg.engine_folder) (registered as $($Proj.engine_id) by 'Register Engine.bat' or 'Setup Project.bat')",
    "Not included:     debug symbols (*.pdb), *.obj, engine Documentation, Templates and FeaturePacks, the game's files, the AES key, the jmap",
    "Symbols:          $(if ($PdbCopy) { 'stripped by pdbcopy, then removed' } else { 'removed' })"
  ) | Set-Content (Join-Path $Release 'VERSION.txt') -Encoding ASCII
}

Stage 'safety' -Always {
  $removed = 0
  foreach ($d in @(Get-ChildItem $Release -Recurse -Force -Directory | Where-Object { $n = $_.Name; @($Pkg.forbidden_folders | Where-Object { $n -like $_ }).Count })) {
    if (Test-Path $d.FullName) { Warn "removing folder $($d.FullName) (forbidden in a release)"; Remove-Item $d.FullName -Recurse -Force; $removed++ }
  }
  foreach ($f in Get-ChildItem $Release -Recurse -Force -File) {
    $n = $f.Name; $why = $null
    $hit = @($Pkg.forbidden_files | Where-Object { $n -like $_ }) | Select-Object -First 1
    if ($hit) { $why = "matches $hit" }
    elseif ($f.Length -le 100 -and ([IO.File]::ReadAllText($f.FullName).Trim() -match '^0[xX][0-9A-Fa-f]{64}$')) { $why = 'content has the shape of an AES key' }
    if ($why) { Warn "removing $($f.FullName) ($why)"; Remove-Item $f.FullName -Force; $removed++ }
  }
  Info "$removed forbidden item(s) removed"
  $required = @(
    "$EngOut\Engine\Binaries\Win64\UnrealEditor.exe",
    "$EngOut\Register Engine.bat",
    "$EngOut\Engine\Plugins\Modkit\Suzie\Suzie.uplugin",
    "$EngOut\Engine\Plugins\Modkit\Suzie\Profiles\$ProfileName\profile.json",
    "$EngOut\Engine\Plugins\Modkit\Suzie\Profiles\$ProfileName\engine.ini",
    "$EngOut\Engine\Plugins\Modkit\Suzie\Profiles\$ProfileName\project.json",
    "$EngOut\Engine\Plugins\Modkit\$GamePluginName\$GamePluginName.uplugin",
    "$TemplateOut\ModkitProject.ps1", "$TemplateOut\Setup Project.bat", "$TemplateOut\Start Editor.bat",
    "$Release\VERSION.txt", (Join-Path $Release (Split-Path -Leaf $Guide)))
  $missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_) })
  if (-not @(Get-ChildItem $TemplateOut -Filter *.uproject).Count) { $missing += "$TemplateOut\*.uproject" }
  if ($missing.Count) { Fail "missing in the release:`n$($missing -join "`n")" }
  Info 'required files present'
}

if ($RunSmoke) {
  Stage 'smoke' {
    $proj = Join-Path $WorkDir ("SmokeTest\" + (Split-Path -Leaf $Template))
    Robo $TemplateOut $proj @('/MIR', '/XD', 'DDC', 'Saved')
    $data = Join-Path $proj 'ModkitData'
    New-Item -ItemType Directory -Force $data | Out-Null
    Copy-Item (Join-Path $SmokeData 'ModkitLocal.ini') (Join-Path $data 'ModkitLocal.ini') -Force
    Info 'Project setup (non-interactive, engine from the release folder)'
    $env:MODKIT_ENGINE = $EngOut
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $proj 'ModkitProject.ps1') -Action setup -NonInteractive
    $rc = $LASTEXITCODE
    Remove-Item Env:\MODKIT_ENGINE
    if ($rc) { Fail 'project setup failed' }
    $uproject = (Get-ChildItem $proj -Filter *.uproject | Select-Object -First 1).FullName
    $out = Join-Path $LogDir 'smoke'
    New-Item -ItemType Directory -Force $out | Out-Null
    $dump = Join-Path $out 'golden.txt'
    $golden = Join-Path $EngOut 'Engine\Plugins\Modkit\Suzie\Tools\sweep\golden.ps1'
    Info "Editor start from the release (timeout $($Pkg.smoke_test.timeout_minutes) minutes)"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $golden -Tag smoke -Out $dump -Project $uproject -LogDir $out -TimeoutSec ([int]$Pkg.smoke_test.timeout_minutes * 60)
    if (Test-Path (Join-Path $out 'smoke.timeout')) { Fail "the editor did not exit within the timeout, see $out\smoke.log" }
    $exit = (Get-Content (Join-Path $out 'smoke.done') -Raw).Trim()
    if ($exit -ne 'exit=0') { Fail "editor $exit, see $out\smoke.log" }
    $log = Join-Path $out 'smoke.log'
    $bad = 0
    foreach ($c in $Pkg.smoke_test.log_checks) {
      $n = @(Select-String -Path $log -Pattern $c.pattern).Count
      $ok = if ($null -ne $c.count) { $n -eq [int]$c.count } else { $n -ge [int]$c.min }
      $want = if ($null -ne $c.count) { "$($c.count)" } else { ">= $($c.min)" }
      if ($ok) { Info "ok   $($c.name): $n" } else { Write-Host "FAIL $($c.name): $n lines match '$($c.pattern)', expected $want" -ForegroundColor Red; $bad++ }
    }
    $goldenRef = Join-Path $Prof 'data\golden\golden.txt.gz'
    if (Test-Path $goldenRef) {
      & python (Join-Path $SuzieRoot 'Tools\sweep\golden_diff.py') $goldenRef $dump > (Join-Path $out 'golden_diff.txt') 2>&1
      if ($LASTEXITCODE) { Write-Host "FAIL golden dump differs from $goldenRef, see $out\golden_diff.txt" -ForegroundColor Red; $bad++ } else { Info 'ok   golden dump identical' }
    }
    if ($bad) { Fail "$bad smoke test check(s) failed, see $log" }
  }
}

$Archive = Join-Path $OutDir "$Tag.7z"
if (-not (Test-Path $Archive)) { Remove-Item (Join-Path $StateDir 'archive.done') -Force -ErrorAction SilentlyContinue }
Stage 'archive' {
  if (Test-Path $Archive) { Remove-Item $Archive -Force }
  Info "Compressing $Release -> $Archive (AES-256, encrypted file names)"
  & $SevenZip a -t7z -mx=5 -mmt=on -mhe=on "-p$Password" $Archive $Release *> (Join-Path $LogDir '7z.log')
  if ($LASTEXITCODE) { Fail "7-Zip failed (exit $LASTEXITCODE), see $LogDir\7z.log" }
  Info 'Testing the archive'
  & $SevenZip t "-p$Password" $Archive *> (Join-Path $LogDir '7z-test.log')
  if ($LASTEXITCODE) { Fail "the archive test failed, see $LogDir\7z-test.log" }
  $hash = (Get-FileHash $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
  Set-Content "$Archive.sha256" "$hash *$(Split-Path -Leaf $Archive)" -Encoding ASCII
  Set-Content "$Archive.password.txt" $Password -Encoding ASCII -NoNewline
}

if ($RemoveBuildFiles) {
  Head 'Removing build files'
  foreach ($d in @($Src, $Installed)) { if (Test-Path $d) { Info "Removing $d"; cmd /c rmdir /s /q "`"$d`"" } }
  foreach ($s in @('source', 'build')) { Remove-Item (Join-Path $StateDir "$s.done") -Force -ErrorAction SilentlyContinue }
}

Head 'Summary'
$Timings | Format-Table -AutoSize | Out-String | Write-Host
if (Test-Path $Archive) {
  Info ("Archive:   {0} ({1:N1} GB)" -f $Archive, ((Get-Item $Archive).Length / 1GB))
  Info "SHA-256:   $Archive.sha256"
  Info "Password:  $Archive.password.txt"
}
Info "Logs:      $LogDir"
Stop-Transcript | Out-Null
Write-Host ''
Write-Host "Archive password: $Password" -ForegroundColor Green
exit 0
