# Installed build and publishing

For the person who builds and hands over the distributable engine. End users follow [setup-other-machine.md](setup-other-machine.md), which is not in the archive.

## One command

```
Packaging\publish-engine.cmd
```

Double-clicked or run without options, it asks three questions before the long part starts (run the smoke test, archive password, continue) and then runs unattended. The result is `<WorkDir>\Releases\<tag>.7z` with `<tag>.7z.sha256` and `<tag>.7z.password.txt` next to it; the password is also printed at the end. For automation:

```
publish-engine.cmd -NonInteractive -NoSmokeTest -Password <password>
```

| Option | Meaning |
|---|---|
| `-ProfileName <name>` | profile folder under the modkit repository's `Profiles` (default: the only one with a `packaging.json`) |
| `-SuzieRoot <dir>` | the Suzie repository (default: the only folder in the layout root with a `Suzie.uplugin`) |
| `-WorkDir <dir>` | build copy, raw installed build, release folder, stage markers (default `<layout root>-Publish` next to the layout root) |
| `-OutDir <dir>` | where the archive goes (default `<WorkDir>\Releases`) |
| `-EngineSource <dir>` | engine tree (default: the only `UnrealEngine-*-fork` folder in the layout root) |
| `-Password <pw>` | archive password; without it: asked, or with `-NonInteractive` a random 16 character `A-Za-z0-9` password |
| `-SmokeTest` / `-NoSmokeTest` | run or skip the smoke test without asking |
| `-SmokeData <dir>` | a `ModkitData` folder whose `ModkitLocal.ini` supplies `GameRoot`, `KeyFile`, `Jmap` for the smoke test (default: the only project folder in the layout root that has one: `DBDMount\ModkitData`) |
| `-UbaHost <ip>` | UBA helpers for the build ([engine-fork.md](engine-fork.md)) |
| `-DevProject <uproject>` | project for the compile check (default: the only project in the layout root with `Plugins\Suzie`: `DBDMount`) |
| `-WithDebugInfo` | build with full debug info (`WithFullDebugInfo=true`): full PDBs stay in `<WorkDir>\Installed` and symbolize crash dumps of that release; slower, about 207 GB raw output. For a test build handed to a user with a crash that needs symbols. Default: no debug info (targets get `-nodebuginfo`) |
| `-Clean` | forget all stage markers and the BuildGraph cache |
| `-RemoveBuildFiles` | after a successful run delete the build copy and the raw installed build (about 250 GB) |
| `-NonInteractive` | no questions; the `.cmd` does not pause at the end |

In an interactive run, after the configuration is shown, the script asks whether to delete the older archives in the archive folder and the raw installed build. Answers default to no. The older archives and, when the build stage is due, the raw installed build are deleted before the disk check, so they count toward the free space the build needs; a run that fails after that does not restore them. A raw build left by an earlier run is deleted after the last stage. `-RemoveBuildFiles` deletes the raw installed build and the build copy without asking.

Logs: `<layout root>\logs\publish-<timestamp>\` (`publish.log` with the password replaced by `<password>`, `installed_build.log`, robocopy and 7-Zip logs, `smoke\`).

Console: each stage header shows its number, the minutes since the start and the clock time. While a step runs, a grey line every 5 to 30 seconds shows its elapsed time and what its log says it is doing: the BuildGraph node and UBT action (`[2/11] Compile UnrealEditor Win64 | [812/2088] Link ...`), the robocopy file count and current file, the 7-Zip percentage, or the latest editor log line during the smoke test. After the build the script reports how many actions the UBA helpers ran and warns when UBT limited local parallel actions to fewer than 3 for lack of free memory.

## What ships

| Ships | Never ships |
|---|---|
| installed engine, trimmed, as `UnrealEngine-5.7.4-DBD\` with `Register Engine.bat` | the AES key file or any key value |
| `DBDMount-Template` (uproject, `Config`, `Content`) | game files, paks, extracted assets |
| `VERSION.txt` | a `ModkitData` folder or a `ModkitLocal.ini` |
| the DBD Suzie profile (inside the engine plugin; it holds no type data, and its test references `data/golden` and `sweeps/` list names of the game's types and assets) | the jmap (the user supplies it) |

The engine is a modified fork of Epic's source; redistribution is limited by the Unreal Engine EULA. Hand the build only to people who may hold UE source/binaries.

## Stages

Each stage writes `<WorkDir>\state\<stage>.done` holding a fingerprint of its inputs, and a run skips stages whose marker matches. **source** and **build** depend on the engine commit, the Suzie files that are compiled (everything except `Packaging`, `Profiles`, `Tools`), the game plugin and `-WithDebugInfo`; when one of them changes, all markers and the BuildGraph cache are discarded and every stage runs again. The later stages depend on the engine and Suzie commits, the profile and `-WithDebugInfo`; a change to packaging, the profile or the tools reruns only them. A failed run is resumed by running the command again.

1. **Preflight** (every run): the engine tree is on `packaging.json` `engine_branch` (`game/dbd`) with every `engine_merged_branches` entry (`modkit-core`) merged; the engine tree, `Suzie-fork` and the modkit repository have no uncommitted or untracked files; the template's `EngineAssociation` equals `project.json` `engine_id`; 7-Zip exists; no UnrealBuildTool or AutomationTool runs; the work drive has 350 GB free (60 GB once the build is done). The release tag is `<release_name>-<yyyyMMdd>` (suffix `-2`, `-3`, ... when taken); a tag already on the engine, `Suzie-fork` and modkit commits is reused. A new tag is created on all three commits only after every stage passed, so a failed run leaves no tag. When the build stage is due, a compile check runs `Build.bat <DevProject>Editor Win64 Development -Module=<each module of Suzie.uplugin and the game plugin> -DisableUnity -NoPCH -WaitMutex` (about one minute, log `compile_check.log`): unity batches and the precompiled header hide missing `#include`s, and the installed build batches differently and would fail on them late.
2. **source**: `robocopy /MIR` of the engine tree to `<WorkDir>\Source` without `.git`, `Intermediate`, `Saved` and folders named `Binaries`, `bin`, `obj` (nothing tracked lives in `Intermediate` or `Saved`; the dependency files that the engine's `Setup.bat` downloaded are untracked and are copied). Folders named `Binaries`, `bin` and `obj` hold build inputs next to the C++ and C# build outputs: only the inputs are copied, i.e. files tracked by git and files listed in the engine tree's `.uedependencies` (installed by `Setup.bat`), when size or time differ. The copy keeps its own build outputs, so after a small engine change the build relinks only the affected modules; the dev tree's outputs in their place make UBT relink every module and AutomationTool rebuild its C# tools. `Suzie-fork` without `.git`, `Packaging`, `Profiles`, `Tools`, `Binaries`, `Intermediate` goes to `Engine\Plugins\Modkit\Suzie`, the profile's game plugin (`packaging.json` `game_plugin`) to `Engine\Plugins\Modkit\DBDModkitGame`. BuildGraph's `<Strip>` steps run `pdbcopy.exe` (feature "Debugging Tools for Windows" of the Windows SDK, `Windows Kits\10\Debuggers\x64`; `winget install --id Microsoft.WindowsSDK.10.0.26100 --force --override "/features OptionId.WindowsDesktopDebuggers /quiet /norestart"` adds it). When it is missing, every Win64 `<Strip>` step of the copy's `InstalledEngineBuild.xml` becomes a `<Copy>` of the same files; symbols are then unstripped in the raw build (the trim removes them either way). Without debug info (the default) the editor, game and tools steps strip; with `-WithDebugInfo` only the tools step does.
3. **build**: `build-installed.cmd` with `BUILD_SRC=<WorkDir>\Source`, `OUT_DIR=<WorkDir>\Installed`. It runs

   ```
   Engine\Build\BatchFiles\RunUAT.bat BuildGraph -target="Make Installed Build Win64" -script=Engine/Build/InstalledEngineBuild.xml
     -set:HostPlatformOnly=true -set:WithWin64=true -set:WithClient=false -set:WithServer=false
     "-set:GameConfigurations=Development;Shipping" -set:WithDDC=false -set:WithFullDebugInfo=<true|false> -set:IncludeDocs=true
     -set:BuiltDirectory=<OUT_DIR> -WaitMutex -NoP4
   ```

   Targets: Win64 editor and game target, Development and Shipping; no Client or Server targets. The script sets `UnrealBuildTool_ParallelExecutor__MemoryPerActionBytes=1073741824`: UBT runs at most (free memory / 1 GB) actions in parallel, measured once when it starts (UBT's default is 1.5 GB). `WithDDC=false`: the editor builds its own DDC on first start (15 to 30 minutes). The stage passes when the exit code is 0, the log contains `BUILD SUCCESSFUL` and `Windows\Engine\Binaries\Win64\UnrealEditor.exe` exists. BuildGraph caches finished nodes in `<WorkDir>\Source\Engine\Saved`; `-Clean` deletes that cache. By default the build has no debug info (`WITH_FULL_DEBUG_INFO=false` for `build-installed.cmd`), so crash dumps of the release cannot be symbolized. With `-WithDebugInfo` the raw output is about 207 GB (mostly PDBs) and intermediates about 45 GB; the full PDBs stay in `<WorkDir>\Installed` (unless `-RemoveBuildFiles`) and symbolize crash dumps of that release.
4. **assemble** into `<WorkDir>\Release\<release_name>`:
   - `robocopy` of `Installed\Windows` to `UnrealEngine-5.7.4-DBD` (`packaging.json` `engine_folder`) without `*.pdb`, `*.obj` and folders named `Documentation`, `Templates`, `FeaturePacks` (shipped about 28 GB). `Engine\Intermediate` stays: the installed engine needs data in it. Without PDBs crash call stacks show raw addresses.
   - The installed file filter keeps only code plugin folders, so the profile (without its `Plugin` folder) is copied to `Engine\Plugins\Modkit\Suzie\Profiles\DBD` and `Suzie-fork\Tools` to `Engine\Plugins\Modkit\Suzie\Tools`.
   - `Packaging\EngineRoot\Register Engine.bat` with `project.json` `engine_id` filled in goes to the engine folder root.
   - The template (`packaging.json` `template`): only its files committed in this repository (`git ls-files`), so nothing generated in the template folder ships; `VERSION.txt` (tag, build date, engine, Suzie and modkit commits, profile, the build change list from the jmap's metadata, symbols). The jmap comes from `-Jmap`, else the `Jmap=` of the `ModkitLocal.ini` of `-SmokeData` or the only `ModkitData` in the workspace root; the run fails without it.
5. **safety** (every run): every file in the release folder whose name matches `forbidden_files` (`*AES*.txt`, `*.jmap`, `*.usmap`, `*.pak`, `*.utoc`, `*.ucas`, `ModkitLocal.ini`), except files whose path relative to the release folder matches `allowed_paths` (`*/Engine/Binaries/ThirdParty/CEF3/*`: the editor's web browser needs its `.pak` resources and crashes at startup without them), every folder matching `forbidden_folders` (`ModkitData`) and every file of at most 100 bytes whose content is `0x` plus 64 hex digits is printed as a warning and deleted. Then the required files are checked: `UnrealEditor.exe`, `Register Engine.bat`, `Suzie.uplugin`, the profile's `profile.json`, `engine.ini`, `project.json`, the game plugin's `.uplugin`, the template's `.uproject` and three scripts, `VERSION.txt`.
6. **archive**: `7z a -t7z -mx=1 -mmt=on -mhe=on -p<password>` of the release folder (AES-256, file names encrypted: nothing in the archive is readable without the password), `7z t` of the result, SHA-256 file, password file. When the archive is missing, assemble, archive and smoke run again.
7. **smoke** (optional): runs after the archive, so nothing the editor writes into the release folder reaches it; a failure deletes the archive, its checksum and password file. It copies the release's template to `<WorkDir>\SmokeTest`, puts the `-SmokeData` `ModkitLocal.ini` into its `ModkitData` and sets its `EngineDir` and `Profile` to the release's engine folder and its single profile folder (the stage fails unless exactly one profile folder with `project.json` exists), then the release's `Tools\sweep\golden.ps1` (one editor start: `Suzie.VerifyNativeTypes`, `Suzie.TagInfo`, `Suzie.DumpAll`, quit) with `packaging.json` `smoke_test.timeout_minutes`. Passes when the editor exits with 0, every `smoke_test.log_checks` regex matches its expected number of log lines (installed engine, key loaded, container mounts, jmap object count, generation without failures, verify gate) and the dump equals the profile's `data/golden/golden.txt.gz` (`golden_diff.py`), whose `SUMMARY` line carries the enum, struct, class, delegate and gameplay tag counts. Expected values live only in those two files. The first start builds the smoke project's DDC.

## Verify on another machine

The smoke test runs on the build machine. Before handing a release out, follow [setup-other-machine.md](setup-other-machine.md) on a machine that is not the build machine: setup, first start, a material instance and the Material Editor of a cooked material, `Suzie.VerifyNativeTypes`. Harmless log noise: PIX, Wintab, STUN, VisionOS icon, autogen delete.

## Installed layout

`UnrealEngine-5.7.4-DBD\Engine\Plugins\Modkit\Suzie` (plugin, `Profiles`, `Tools`), `UnrealEngine-5.7.4-DBD\Engine\Plugins\Modkit\DBDModkitGame`. `Register Engine.bat` registers the engine folder as `DBDModkit-5.7.4` under `HKCU\Software\Epic Games\Unreal Engine\Builds`, the `EngineAssociation` of the template's `.uproject`.

For network copies of the archive use robocopy; a blank-password local account fails with SMB error 1326.
