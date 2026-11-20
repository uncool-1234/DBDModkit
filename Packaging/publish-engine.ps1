# Builds, assembles and archives a release of the modkit engine for one profile. Entry point: publish-engine.cmd.
#
# Stages (each writes a marker under <WorkDir>\state and is skipped on the next run while its inputs are unchanged: source and build
# depend on the engine commit and the compiled Suzie and game plugin files, the later stages on the engine and Suzie commits):
#   source    copy of the engine tree without .git/Intermediate/Saved and with only the build inputs of Binaries/bin/obj folders, plus Suzie and the profile's game plugin under Engine\Plugins\Modkit
#   build     BuildGraph "Make Installed Build Win64" (build-installed.cmd)
#   assemble  trimmed engine, profile, tools, Register Engine.bat, project template, VERSION.txt under <WorkDir>\Release
#   safety    removes forbidden files (game data, key files, machine local ini) from the release folder, checks required files
#   archive   encrypted .7z (AES-256, encrypted file names) with .sha256 and .password.txt next to it
#   smoke     optional: project setup and one editor start (verify, tag probe, golden dump) from the release folder; runs after the
#             archive so that nothing the editor writes reaches it; a failure deletes the archive
# Preflight compiles the Suzie and game plugin modules without unity build and PCH in the dev project before a build.
# The release tag is created on the engine and Suzie commits once every stage passed.
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
  [string]$Jmap = '',               # the game's jmap, read for the build change list; default: Jmap= of the same ModkitLocal.ini
  [string]$UbaHost = '',
  [string]$DevProject = '',         # .uproject for the compile check; default: the only project in the workspace root with Plugins\Suzie
  [switch]$WithDebugInfo,           # build with full debug info (BuildGraph WithFullDebugInfo=true, full PDBs in the raw build); default: none (-nodebuginfo)
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

# The transcript header records the command line, which can carry -Password.
function Close-Log {
  try { Stop-Transcript | Out-Null } catch {}
  $f = Join-Path $LogDir 'publish.log'
  if ($Password -and (Test-Path $f)) { [IO.File]::WriteAllText($f, [IO.File]::ReadAllText($f).Replace($Password, '<password>')) }
}
function Fail($msg) { Write-Host ''; Write-Host "ERROR: $msg" -ForegroundColor Red; Close-Log; exit 1 }
function Warn($msg) { Write-Host "WARNING: $msg" -ForegroundColor Yellow }
function Info($msg) { Write-Host $msg }
function Head($msg) { Write-Host ''; Write-Host "== $msg" -ForegroundColor Cyan }
function Ask($prompt) { if ($NonInteractive) { return '' }; (Read-Host $prompt).Trim() }
# git writes warnings to stderr; with 'Stop' Windows PowerShell would turn them into terminating errors.
function GitOut($repo) {
  $ErrorActionPreference = 'Continue'
  $out = @(& git.exe -C $repo @args 2>&1 | ForEach-Object { "$_" })
  if ($LASTEXITCODE) { Fail "git -C $repo $($args -join ' '): $($out -join ' ')" }
  $out | Where-Object { $_ -and $_ -notmatch '^warning: ' }
}
function Test-Ancestor($repo, $branch) { $ErrorActionPreference = 'Continue'; & git.exe -C $repo merge-base --is-ancestor $branch HEAD 2>$null; $LASTEXITCODE -eq 0 }

function Join-Args([string[]]$list) { ($list | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' ' }

# Progress of a running program, read from the log it writes. Recognised lines: BuildGraph nodes ("****** [n/m] Node"),
# UBT actions ("[n/m] Compile ..."), BuildGraph copies, 7-Zip percentages, robocopy file lines and editor log lines; any
# other line is shown as the latest output.
function Update-WatchState($s, [string]$line) {
  $line = $line.Trim()
  if (-not $line) { return }
  if ($line -match '^\*{6} \[(\d+/\d+)\] (.+)$') { $s.Node = "[$($Matches[1])] $($Matches[2])"; $s.Action = ''; return }
  if ($line -match '^\[(\d+/\d+)\] (.+)$') { $s.Action = "[$($Matches[1])] $($Matches[2])"; return }
  if ($line -match '^Copying (\d+) files from .+ to (.+?)\.*$') { $s.Action = "copying $($Matches[1]) files to $($Matches[2])"; return }
  if ($line -match '^(\d{1,3})%\s*(?:\d+\s*)?(?:[+=UT-]\s+)?(.*)$') { $s.Action = "$($Matches[1])% $($Matches[2])"; return }
  if ($line -match '^(New File|Newer|Older|Changed|\*EXTRA File)\b') { $s.Files++; $s.Action = "$($s.Files) files, $(($line -split "`t")[-1].Trim())"; return }
  if ($line -match '^\[\d{4}\.\d\d\.\d\d-[\d.:]+\]\[\s*\d+\](.+)$') { $line = $Matches[1] }
  $s.Last = $line
}

# Runs a program, waits for it and prints what it is doing while it runs: a line whenever the status read from
# $WatchLog changes (at most every 5 s) and at least every 30 s. Returns the exit code. stdout and stderr go to $OutLog.
# -FromEnd ignores what $WatchLog holds when the program starts.
function Invoke-Watched {
  param([string]$Label, [string]$FilePath, [string]$Arguments, [string]$OutLog, [string]$WatchLog = '',
        [switch]$FromEnd)
  if (-not $WatchLog) { $WatchLog = $OutLog }
  $pos = 0L
  if ($FromEnd -and (Test-Path -LiteralPath $WatchLog)) { $pos = (Get-Item -LiteralPath $WatchLog).Length }
  $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -PassThru -RedirectStandardOutput $OutLog -RedirectStandardError "$OutLog.err"
  $null = $p.Handle
  $s = @{ Node = ''; Action = ''; Last = ''; Files = 0 }
  $carry = ''; $t0 = Get-Date; $shown = ''; $lastPrint = [datetime]::MinValue
  $width = try { [Math]::Max(80, $Host.UI.RawUI.WindowSize.Width - 1) } catch { 160 }
  while ($true) {
    $exited = $p.WaitForExit(1000)
    if (Test-Path -LiteralPath $WatchLog) {
      try {
        $fs = [IO.File]::Open($WatchLog, 'Open', 'Read', 'ReadWrite, Delete')
        try {
          if ($fs.Length -lt $pos) { $pos = 0; $carry = '' }
          $bom = New-Object byte[] 2
          $unicode = $fs.Read($bom, 0, 2) -eq 2 -and $bom[0] -eq 0xFF -and $bom[1] -eq 0xFE
          $enc = if ($unicode) { [Text.Encoding]::Unicode } else { [Text.Encoding]::UTF8 }
          $n = [int][Math]::Min($fs.Length - $pos, 4MB)
          if ($unicode) { $n -= $n % 2 }
          if ($n -gt 0) {
            $buf = New-Object byte[] $n
            [void]$fs.Seek($pos, 'Begin'); $n = $fs.Read($buf, 0, $n); $pos += $n
            $parts = ($carry + $enc.GetString($buf, 0, $n)) -split "[\r\n\b]+"
            $carry = $parts[-1]
            for ($i = 0; $i -lt $parts.Count - 1; $i++) { Update-WatchState $s $parts[$i] }
            if ($carry -match '^\s*\d{1,3}%') { Update-WatchState $s $carry }
          }
        } finally { $fs.Dispose() }
      } catch {}
    }
    if ($exited) { break }
    $status = @($s.Node, $(if ($s.Action) { $s.Action } else { $s.Last })) | Where-Object { $_ }
    $status = $status -join ' | '
    $now = Get-Date
    if (($status -ne $shown -and ($now - $lastPrint).TotalSeconds -ge 5) -or ($now - $lastPrint).TotalSeconds -ge 30) {
      $e = $now - $t0
      $line = '  {0,3}:{1:00} {2}  {3}' -f [int][Math]::Floor($e.TotalMinutes), $e.Seconds, $Label, $(if ($status) { $status } else { 'running' })
      if ($line.Length -gt $width) { $line = $line.Substring(0, $width - 3) + '...' }
      Write-Host $line -ForegroundColor DarkGray
      $shown = $status; $lastPrint = $now
    }
  }
  $p.WaitForExit()
  $err = "$OutLog.err"
  if ((Test-Path $err) -and (Get-Item $err).Length) { Get-Content $err | Add-Content $OutLog }
  Remove-Item $err -Force -ErrorAction SilentlyContinue
  $p.ExitCode
}

function Robo($from, $to, [string[]]$opts) {
  $log = Join-Path $LogDir ("robocopy-{0}.log" -f ($Timings.Count))
  $rc = Invoke-Watched -Label 'robocopy' -FilePath robocopy.exe -Arguments (Join-Args (@($from, $to) + $opts + @('/NP', '/NDL', "/UNILOG+:$log"))) -OutLog "$log.out" -WatchLog $log -FromEnd
  Remove-Item "$log.out" -Force -ErrorAction SilentlyContinue
  if ($rc -ge 8) { Fail "robocopy $from -> $to failed (exit $rc), see $log" }
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
# The build change list is in the jmap's metadata, which starts the file.
if (-not $Jmap) {
  $jmapIni = if ($SmokeData) { Join-Path $SmokeData 'ModkitLocal.ini' } else {
    $c = @(Get-ChildItem $Root -Directory | ForEach-Object { Join-Path $_.FullName 'ModkitData\ModkitLocal.ini' } | Where-Object { Test-Path $_ })
    if ($c.Count -eq 1) { $c[0] } else { '' } }
  $jmapLine = if ($jmapIni -and (Test-Path $jmapIni)) { Select-String -Path $jmapIni -Pattern '^Jmap=(.+)$' | Select-Object -First 1 }
  if (-not $jmapLine) { Fail 'pass -Jmap <jmap> (no Jmap= in a ModkitLocal.ini)' }
  $Jmap = $jmapLine.Matches[0].Groups[1].Value.Trim()
}
if (-not (Test-Path -LiteralPath $Jmap)) { Fail "the jmap $Jmap does not exist" }
$sr = New-Object IO.StreamReader($Jmap)
try { $buf = New-Object char[] 65536; $n = $sr.Read($buf, 0, $buf.Length); $jmapHead = [string]::new($buf, 0, $n) } finally { $sr.Dispose() }
$cl = [regex]::Match($jmapHead, '"build_change_list"\s*:\s*"([^"]+)"')
if (-not $cl.Success) { Fail "no build_change_list in the metadata of $Jmap" }
$BuildChangeList = $cl.Groups[1].Value

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
Info "Debug info:     $(if ($WithDebugInfo) { 'full (-WithDebugInfo)' } else { 'none' })"
Info "pdbcopy:        $(if ($PdbCopy) { $PdbCopy } else { 'not found: the strip steps copy symbols unstripped' })"
Info "Logs:           $LogDir"
if (-not $NonInteractive -and (Ask 'Continue? [Y/n]') -match '^[nN]') { Fail 'cancelled' }

# The cleanup answers are carried out only after every stage passed (see the end of the script).
$DeleteOld = $false; $DeleteInstalled = [bool]$RemoveBuildFiles; $DeleteSource = [bool]$RemoveBuildFiles
if (-not $NonInteractive) {
  $oldFiles = @(Get-ChildItem $OutDir -File -ErrorAction SilentlyContinue)
  $oldGB = [double](($oldFiles | Measure-Object Length -Sum).Sum) / 1GB
  $DeleteOld = (Ask ("Delete the older archives in $OutDir after this run succeeds ({0} files, {1:N1} GB; the archive this run creates is kept)? [y/N]" -f $oldFiles.Count, $oldGB)) -match '^[yY]'
  if (-not $RemoveBuildFiles) {
    $DeleteInstalled = (Ask "Delete the raw installed build $Installed after this run succeeds? The next run rebuilds it. Its PDBs symbolize crash dumps of a -WithDebugInfo release. [y/N]") -match '^[yY]'
  }
}

# ---------------------------------------------------------------- preflight

Head 'Preflight'
$branch = (GitOut $EngineSource rev-parse --abbrev-ref HEAD) | Select-Object -First 1
if ($branch -ne $Pkg.engine_branch) { Fail "$EngineSource is on '$branch', expected '$($Pkg.engine_branch)'" }
foreach ($b in $Pkg.engine_merged_branches) {
  if (-not (Test-Ancestor $EngineSource $b)) { Fail "$b is not merged into $($Pkg.engine_branch)" }
}
foreach ($repo in @($EngineSource, $SuzieRoot)) {
  $dirty = @(GitOut $repo status --porcelain)
  if ($dirty.Count) { Fail "$repo has uncommitted changes:`n$($dirty -join "`n")" }
}
$EngineCommit = (GitOut $EngineSource rev-parse HEAD) | Select-Object -First 1
$SuzieCommit = (GitOut $SuzieRoot rev-parse HEAD) | Select-Object -First 1
$Fingerprint = "engine=$EngineCommit suzie=$SuzieCommit profile=$ProfileName debuginfo=$([bool]$WithDebugInfo)"
# The build copy holds Suzie without Packaging, Profiles and Tools plus the game plugin: hash exactly those trees.
$suzieTree = @(GitOut $SuzieRoot ls-tree HEAD | Where-Object { ($_ -split "`t")[-1] -notin @('Packaging', 'Profiles', 'Tools') }) -join "`n"
$sha = [Security.Cryptography.SHA1]::Create()
$suzieTreeHash = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($suzieTree)) | ForEach-Object { $_.ToString('x2') })
$gamePluginRel = $GamePlugin.Substring($SuzieRoot.Length).TrimStart('\').Replace('\', '/')
$gamePluginTree = (GitOut $SuzieRoot rev-parse "HEAD:$gamePluginRel") | Select-Object -First 1
$BuildFingerprint = "engine=$EngineCommit suzie-build=$suzieTreeHash game-plugin=$gamePluginTree debuginfo=$([bool]$WithDebugInfo)"
$BuildStages = @('source', 'build')
$assoc = (Get-Content (Get-ChildItem $Template -Filter *.uproject | Select-Object -First 1).FullName -Raw | ConvertFrom-Json).EngineAssociation
if ($assoc -ne $Proj.engine_id) { Fail "the template's EngineAssociation '$assoc' differs from project.json engine_id '$($Proj.engine_id)'" }
if (-not $SevenZip) { Fail '7-Zip (7z.exe) not found' }
Info "Engine $EngineCommit, Suzie $SuzieCommit, 7-Zip $SevenZip"

New-Item -ItemType Directory -Force $StateDir, $OutDir | Out-Null
function StageFingerprint($stage) { if ($BuildStages -contains $stage) { $BuildFingerprint } else { $Fingerprint } }
$markers = @(Get-ChildItem $StateDir -Filter *.done)
$staleBuild = @($markers | Where-Object { $BuildStages -contains $_.BaseName -and (Get-Content $_.FullName -Raw).Trim() -ne $BuildFingerprint })
$staleLate = @($markers | Where-Object { $BuildStages -notcontains $_.BaseName -and (Get-Content $_.FullName -Raw).Trim() -ne $Fingerprint })
if (-not $Clean -and -not $staleBuild.Count -and $staleLate.Count) {
  Warn 'packaging, profile or tools changed since the last run: the stages after build run again'
  $staleLate | Remove-Item -Force
}
if ($Clean -or $staleBuild.Count) {
  if ($staleBuild.Count -and -not $Clean) { Warn 'the engine or the compiled Suzie files changed since the last run: all stages run again' }
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
# The release tag names one engine commit and one Suzie commit: reuse a tag that is on both HEADs, else a free name, created at the end.
$both = @(GitOut $SuzieRoot tag --points-at HEAD)
$Tag = @(GitOut $EngineSource tag --points-at HEAD | Where-Object { $_ -like "$($Pkg.release_name)-*" -and $both -contains $_ }) | Select-Object -First 1
$NewTag = -not $Tag
if ($NewTag) {
  $base = "$($Pkg.release_name)-$(Get-Date -Format yyyyMMdd)"; $Tag = $base; $n = 2
  while (@(GitOut $EngineSource tag --list $Tag).Count -or @(GitOut $SuzieRoot tag --list $Tag).Count) { $Tag = "$base-$n"; $n++ }
}
Info "Release tag: $Tag$(if ($NewTag) { ' (created when every stage passed)' })"

# Deletions chosen at the start run before the disk check, so they free the space the build needs. The raw installed
# build is removed only when the build stage is due; it is rebuilt there.
if ($DeleteOld) {
  Head 'Removing older archives'
  $archLeaf = "$Tag.7z"
  $keep = @($archLeaf, "$archLeaf.sha256", "$archLeaf.password.txt")
  foreach ($f in @(Get-ChildItem $OutDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.7z(\.sha256|\.password\.txt)?$' -and $_.Name -notin $keep })) {
    Info "Removing $($f.FullName)"; Remove-Item $f.FullName -Force
  }
}
if ($DeleteInstalled -and -not (Done 'build') -and (Test-Path $Installed)) {
  Head 'Removing the raw installed build'
  Info "Removing $Installed"; cmd /c rmdir /s /q "`"$Installed`""
}

$drive = Get-PSDrive -Name (Split-Path -Qualifier $WorkDir).TrimEnd(':')
if ($drive.Free -lt $need) { Fail ("{0} has {1:N0} GB free, the remaining stages need about {2:N0} GB" -f $WorkDir, ($drive.Free / 1GB), ($need / 1GB)) }

if (-not (Done 'build')) {
  # Unity batches and the PCH hide missing includes; the installed build batches differently and fails late on them.
  if (-not $DevProject) {
    $devs = @(Get-ChildItem $Root -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'Plugins\Suzie') } | ForEach-Object { Get-ChildItem $_.FullName -Filter *.uproject } | ForEach-Object FullName)
    if ($devs.Count -ne 1) { Fail "pass -DevProject <uproject> (projects with Plugins\Suzie in $Root`: $($devs.Count))" }
    $DevProject = $devs[0]
  }
  $modules = @(@((Join-Path $SuzieRoot 'Suzie.uplugin'), (Get-ChildItem $GamePlugin -Filter *.uplugin | Select-Object -First 1).FullName) |
    ForEach-Object { (Get-Content $_ -Raw | ConvertFrom-Json).Modules | ForEach-Object Name })
  $target = [IO.Path]::GetFileNameWithoutExtension($DevProject) + 'Editor'
  $clog = Join-Path $LogDir 'compile_check.log'
  Info "Compile check: $($modules -join ', ') without unity build and PCH ($target)"
  $cargs = @($target, 'Win64', 'Development', "-Project=$DevProject") + @($modules | ForEach-Object { "-Module=$_" }) + @('-DisableUnity', '-NoPCH', '-WaitMutex')
  $rc = Invoke-Watched -Label 'compile check' -FilePath (Join-Path $EngineSource 'Engine\Build\BatchFiles\Build.bat') -Arguments (Join-Args $cargs) -OutLog $clog
  if ($rc) { Fail "the compile check failed (exit $rc; often a missing #include that unity builds hide), see $clog" }
  Info 'Compile check passed'
}

$StageNames = @('source', 'build', 'assemble', 'safety', 'archive') + @(if ($RunSmoke) { 'smoke' })
$RunStart = Get-Date
function Stage($name, [scriptblock]$body, [switch]$Always) {
  Head ("{0} (stage {1} of {2}, {3:N0} min since start, {4:HH:mm})" -f $name, ([array]::IndexOf($StageNames, $name) + 1), $StageNames.Count, ((Get-Date) - $RunStart).TotalMinutes, (Get-Date))
  if (-not $Always -and (Done $name)) { Info 'done in an earlier run, skipped'; [void]$Timings.Add([pscustomobject]@{ Stage = $name; Result = 'skipped'; Minutes = 0 }); return }
  $t = Get-Date
  & $body
  Set-Content (Join-Path $StateDir "$name.done") (StageFingerprint $name)
  [void]$Timings.Add([pscustomobject]@{ Stage = $name; Result = 'ok'; Minutes = [math]::Round(((Get-Date) - $t).TotalMinutes, 1) })
}

# ---------------------------------------------------------------- stages

# Folders named Binaries (C++ build output) and bin/obj (C# build output) hold build inputs and build outputs side by
# side. Only the inputs are copied: files tracked by git and files installed by Setup (.uedependencies). The build copy
# keeps its own outputs: outputs of the source tree's dev build in their place make UBT relink every module and
# AutomationTool rebuild its C# tools.
$OutputDirNames = @('Binaries', 'bin', 'obj')
function Copy-BinariesInputs {
  $rels = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $specs = $OutputDirNames | ForEach-Object { ":(glob,icase)**/$_/**" }
  foreach ($f in (GitOut $EngineSource -c core.quotepath=false ls-files -- @specs)) { [void]$rels.Add($f) }
  $deps = Join-Path $EngineSource '.uedependencies'
  if (-not (Test-Path $deps)) { Fail "$deps does not exist (written by the engine's Setup)" }
  $re = '(^|/)(' + ($OutputDirNames -join '|') + ')/'
  $r = [Xml.XmlReader]::Create($deps)
  try { while ($r.ReadToFollowing('File')) { $n = $r.GetAttribute('Name'); if ($n -match $re) { [void]$rels.Add($n) } } } finally { $r.Dispose() }
  Info "Inputs in $($OutputDirNames -join '/') folders: $($rels.Count) files tracked by git or installed by Setup"
  $copied = 0; $i = 0; $t0 = Get-Date; $last = $t0
  foreach ($rel in $rels) {
    $i++
    $a = New-Object IO.FileInfo (Join-Path $EngineSource $rel)
    if ($a.Exists) {
      $b = New-Object IO.FileInfo (Join-Path $Src $rel)
      if (-not ($b.Exists -and $b.Length -eq $a.Length -and $b.LastWriteTimeUtc -eq $a.LastWriteTimeUtc)) {
        [void][IO.Directory]::CreateDirectory($b.DirectoryName)
        if ($b.Exists -and $b.IsReadOnly) { $b.IsReadOnly = $false }
        [IO.File]::Copy($a.FullName, $b.FullName, $true)
        $copied++
      }
    }
    $now = Get-Date
    if (($now - $last).TotalSeconds -ge 5) {
      $e = $now - $t0
      Write-Host ('  {0,3}:{1:00} binaries  {2} of {3} checked, {4} copied' -f [int][Math]::Floor($e.TotalMinutes), $e.Seconds, $i, $rels.Count, $copied) -ForegroundColor DarkGray
      $last = $now
    }
  }
  Info "$copied input file(s) copied"
}

Stage 'source' {
  $modkit = Join-Path $Src 'Engine\Plugins\Modkit'
  Info "Copying $EngineSource -> $Src ($($OutputDirNames -join '/') folders: inputs only)"
  Robo $EngineSource $Src (@('/MIR', '/MT:16', '/R:2', '/W:5', '/XD', (Join-Path $EngineSource '.git'), $modkit, 'Intermediate', 'Saved') + $OutputDirNames + @('/XF', '.git'))
  Copy-BinariesInputs
  Info "Copying Suzie -> $modkit\Suzie"
  Robo $SuzieRoot (Join-Path $modkit 'Suzie') @('/MIR', '/MT:16', '/XD', (Join-Path $SuzieRoot '.git'), (Join-Path $SuzieRoot 'Packaging'), (Join-Path $SuzieRoot 'Profiles'), (Join-Path $SuzieRoot 'Tools'), 'Binaries', 'Intermediate', '__pycache__', '/XF', '.git*')
  Info "Copying $GamePluginName -> $modkit\$GamePluginName"
  Robo $GamePlugin (Join-Path $modkit $GamePluginName) @('/MIR', '/XD', 'Binaries', 'Intermediate', '__pycache__')
  if (-not $PdbCopy) {
    # Every Win64 <Strip> step becomes a <Copy> of the same files (Strip needs pdbcopy.exe).
    $xml = Join-Path $Src 'Engine\Build\InstalledEngineBuild.xml'
    $s = [IO.File]::ReadAllText($xml)
    $re = '<Strip\s[^>]*Platform="Win64"[^>]*/>'
    $n = [regex]::Matches($s, $re).Count
    if ($n -eq 0) { Fail "no Win64 Strip step in $xml" }
    $s = [regex]::Replace($s, $re, {
      param($m)
      $a = @{}; foreach ($x in [regex]::Matches($m.Value, '(\w+)="([^"]*)"')) { $a[$x.Groups[1].Value] = $x.Groups[2].Value }
      if (-not $a.Files -or -not $a.BaseDir -or -not $a.OutputDir) { Fail "unexpected Strip step in $xml`: $($m.Value)" }
      $t = if ($a.Tag) { " Tag=`"$($a.Tag)`"" } else { '' }
      "<Copy Files=`"$($a.Files)`" From=`"$($a.BaseDir)`" To=`"$($a.OutputDir)`"$t/>"
    })
    [IO.File]::WriteAllText($xml, $s)
    Info "InstalledEngineBuild.xml of the build copy: $n Win64 strip step(s) copy symbols unstripped (no pdbcopy.exe)"
  }
}

Stage 'build' {
  Info 'BuildGraph: Make Installed Build Win64 (several hours)'
  $env:BUILD_SRC = $Src; $env:OUT_DIR = $Installed; $env:LOG_DIR = $LogDir; $env:UBA_HOST = $UbaHost; $env:MODKIT_ROOT = $Root
  $env:WITH_FULL_DEBUG_INFO = if ($WithDebugInfo) { 'true' } else { 'false' }
  # UBT runs (free memory / this value) actions in parallel, measured once when it starts; the default 1.5 GB lets a
  # running editor serialise the build.
  $env:UnrealBuildTool_ParallelExecutor__MemoryPerActionBytes = '1073741824'
  $log = Join-Path $LogDir 'installed_build.log'
  $rc = Invoke-Watched -Label 'build' -FilePath $env:ComSpec -Arguments "/d /c `"$PSScriptRoot\build-installed.cmd`"" -OutLog (Join-Path $LogDir 'build-installed.out') -WatchLog $log
  if ($rc -ne 0 -or -not (Select-String -Path $log -Pattern 'BUILD SUCCESSFUL' -SimpleMatch -Quiet)) { Fail "the installed build failed (exit $rc), see $log" }
  $limits = @(Select-String -Path $log -Pattern 'limiting max parallel actions to (\d+)' | ForEach-Object { [int]$_.Matches[0].Groups[1].Value })
  if (@($limits | Where-Object { $_ -lt 3 }).Count) { Warn "UBT ran as few as $(($limits | Measure-Object -Minimum).Minimum) local action(s) in parallel for lack of free memory (see 'limiting max parallel actions' in $log)" }
  if ($UbaHost) {
    $remote = (@(Select-String -Path $log -Pattern 'Remote processes finished\s+(\d+)' | ForEach-Object { [int]$_.Matches[0].Groups[1].Value }) | Measure-Object -Sum).Sum
    Info "UBA helpers ran $remote action(s)"
  }
  if (-not (Test-Path (Join-Path $Installed 'Windows\Engine\Binaries\Win64\UnrealEditor.exe'))) { Fail "no UnrealEditor.exe under $Installed\Windows" }
}

$Archive = Join-Path $OutDir "$Tag.7z"
# A new archive needs a fresh release folder (the smoke test writes into the engine folder) and its own smoke test.
if (-not (Test-Path $Archive)) { foreach ($s in @('assemble', 'archive', 'smoke')) { Remove-Item (Join-Path $StateDir "$s.done") -Force -ErrorAction SilentlyContinue } }

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
  # Only the template's committed files: anything generated in the template folder (ModkitData, tag lists, caches) stays out.
  if (-not $Template.StartsWith($SuzieRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { Fail "the template $Template is not inside $SuzieRoot" }
  $tplRel = $Template.Substring($SuzieRoot.Length + 1).Replace('\', '/')
  $tplFiles = @(GitOut $SuzieRoot ls-files -- $tplRel)
  if (-not $tplFiles.Count) { Fail "no committed files in the template $Template" }
  Info "Template ($($tplFiles.Count) committed files) -> $TemplateOut"
  if (Test-Path $TemplateOut) { Remove-Item $TemplateOut -Recurse -Force }
  foreach ($f in $tplFiles) {
    $dst = Join-Path $TemplateOut $f.Substring($tplRel.Length + 1)
    New-Item -ItemType Directory -Force (Split-Path -Parent $dst) | Out-Null
    Copy-Item -LiteralPath (Join-Path $SuzieRoot $f) $dst
  }
  $suzieLog = (GitOut $SuzieRoot log -1 --format='%h %s') | Select-Object -First 1
  $engineLog = (GitOut $EngineSource log -1 --format='%h %s') | Select-Object -First 1
  @(
    "$($Pkg.release_name) ($Tag)",
    "Built:            $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    "Engine:           $($Pkg.engine_branch) $engineLog",
    "Suzie:            $suzieLog",
    "Profile:          $ProfileName",
    "Game version:     $BuildChangeList",
    "Symbols:          $(if ($WithDebugInfo) { 'removed from the release; full PDBs stay in the raw installed build' } else { 'none (built without debug info)' })"
  ) | Set-Content (Join-Path $Release 'VERSION.txt') -Encoding ASCII
}

Stage 'safety' -Always {
  $removed = 0
  foreach ($d in @(Get-ChildItem $Release -Recurse -Force -Directory | Where-Object { $n = $_.Name; @($Pkg.forbidden_folders | Where-Object { $n -like $_ }).Count })) {
    if (Test-Path $d.FullName) { Warn "removing folder $($d.FullName) (forbidden in a release)"; Remove-Item $d.FullName -Recurse -Force; $removed++ }
  }
  $allowed = @($Pkg.allowed_paths)
  foreach ($f in Get-ChildItem $Release -Recurse -Force -File) {
    $n = $f.Name; $why = $null
    $rel = $f.FullName.Substring($Release.Length).TrimStart('\').Replace('\', '/')
    $hit = if (@($allowed | Where-Object { $rel -like $_ }).Count) { $null } else { @($Pkg.forbidden_files | Where-Object { $n -like $_ }) | Select-Object -First 1 }
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
    "$Release\VERSION.txt")
  $missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_) })
  if (-not @(Get-ChildItem $TemplateOut -Filter *.uproject).Count) { $missing += "$TemplateOut\*.uproject" }
  if ($missing.Count) { Fail "missing in the release:`n$($missing -join "`n")" }
  Info 'required files present'
}

Stage 'archive' {
  if (Test-Path $Archive) { Remove-Item $Archive -Force }
  Info "Compressing $Release -> $Archive (AES-256, encrypted file names)"
  $rc = Invoke-Watched -Label '7z' -FilePath $SevenZip -Arguments (Join-Args @('a', '-t7z', '-mx=1', '-mmt=on', '-mhe=on', '-bsp1', "-p$Password", $Archive, $Release)) -OutLog (Join-Path $LogDir '7z.log')
  if ($rc) { Fail "7-Zip failed (exit $rc), see $LogDir\7z.log" }
  Info 'Testing the archive'
  $rc = Invoke-Watched -Label '7z test' -FilePath $SevenZip -Arguments (Join-Args @('t', '-bsp1', "-p$Password", $Archive)) -OutLog (Join-Path $LogDir '7z-test.log')
  if ($rc) { Fail "the archive test failed, see $LogDir\7z-test.log" }
  Info 'SHA-256 of the archive'
  $hash = (Get-FileHash $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
  [IO.File]::WriteAllText("$Archive.sha256", "$hash *$(Split-Path -Leaf $Archive)`n")
  Set-Content "$Archive.password.txt" $Password -Encoding ASCII -NoNewline
}

function Fail-Smoke($msg) {
  foreach ($f in @($Archive, "$Archive.sha256", "$Archive.password.txt")) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
  Fail "$msg (the archive was deleted)"
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
    if ($rc) { Fail-Smoke 'project setup failed' }
    $uproject = (Get-ChildItem $proj -Filter *.uproject | Select-Object -First 1).FullName
    $out = Join-Path $LogDir 'smoke'
    New-Item -ItemType Directory -Force $out | Out-Null
    $dump = Join-Path $out 'golden.txt'
    $golden = Join-Path $EngOut 'Engine\Plugins\Modkit\Suzie\Tools\sweep\golden.ps1'
    Info "Editor start from the release (timeout $($Pkg.smoke_test.timeout_minutes) minutes)"
    $editorLog = Join-Path $proj ("Saved\Logs\" + [IO.Path]::GetFileNameWithoutExtension($uproject) + '.log')
    $gargs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $golden, '-Tag', 'smoke', '-Out', $dump, '-Project', $uproject, '-LogDir', $out, '-TimeoutSec', ([int]$Pkg.smoke_test.timeout_minutes * 60))
    [void](Invoke-Watched -Label 'editor' -FilePath powershell.exe -Arguments (Join-Args $gargs) -OutLog (Join-Path $out 'golden-run.log') -WatchLog $editorLog -FromEnd)
    if (Test-Path (Join-Path $out 'smoke.timeout')) { Fail-Smoke "the editor did not exit within the timeout, see $out\smoke.log" }
    $exit = (Get-Content (Join-Path $out 'smoke.done') -Raw).Trim()
    if ($exit -ne 'exit=0') { Fail-Smoke "editor $exit, see $out\smoke.log" }
    $log = Join-Path $out 'smoke.log'
    $bad = 0
    foreach ($c in $Pkg.smoke_test.log_checks) {
      $n = @(Select-String -Path $log -Pattern $c.pattern).Count
      $ok = if ($null -ne $c.count) { $n -eq [int]$c.count } else { $n -ge [int]$c.min }
      $want = if ($null -ne $c.count) { "$($c.count)" } else { ">= $($c.min)" }
      if ($ok) { Info "ok   $($c.name): $n" } else { Write-Host "FAIL $($c.name): $n lines match '$($c.pattern)', expected $want" -ForegroundColor Red; $bad++ }
    }
    # The golden dump carries the type and tag counts (its SUMMARY line); log_checks cover what the dump does not.
    $goldenRef = Join-Path $Prof 'data\golden\golden.txt.gz'
    if (-not (Test-Path $goldenRef)) { Fail-Smoke "no golden dump $goldenRef" }
    & python (Join-Path $SuzieRoot 'Tools\sweep\golden_diff.py') $goldenRef $dump > (Join-Path $out 'golden_diff.txt') 2>&1
    $summary = (Get-Content $dump -TotalCount 1)
    if ($LASTEXITCODE) { Write-Host "FAIL golden dump differs from $goldenRef, see $out\golden_diff.txt" -ForegroundColor Red; $bad++ } else { Info "ok   golden dump identical ($summary)" }
    if ($bad) { Fail-Smoke "$bad smoke test check(s) failed, see $log" }
  }
}

if ($NewTag) {
  GitOut $EngineSource tag $Tag | Out-Null
  GitOut $SuzieRoot tag $Tag | Out-Null
  Info "Tagged the engine and Suzie commits $Tag"
}

if ($DeleteInstalled -or $DeleteSource) {
  Head 'Removing build files'
  $dirs = @(); if ($DeleteInstalled) { $dirs += $Installed }; if ($DeleteSource) { $dirs += $Src }
  foreach ($d in $dirs) { if (Test-Path $d) { Info "Removing $d"; cmd /c rmdir /s /q "`"$d`"" } }
  $stale = @('build'); if ($DeleteSource) { $stale += 'source' }
  foreach ($s in $stale) { Remove-Item (Join-Path $StateDir "$s.done") -Force -ErrorAction SilentlyContinue }
}

Head 'Summary'
$Timings | Format-Table -AutoSize | Out-String | Write-Host
if (Test-Path $Archive) {
  Info ("Archive:   {0} ({1:N1} GB)" -f $Archive, ((Get-Item $Archive).Length / 1GB))
  Info "SHA-256:   $Archive.sha256"
  Info "Password:  $Archive.password.txt"
}
Info "Logs:      $LogDir"
Close-Log
Write-Host ''
Write-Host "Archive password: $Password" -ForegroundColor Green
exit 0
