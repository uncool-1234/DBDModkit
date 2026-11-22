# Engine fork, branches and building

## Repositories

| Path | Branch | Role |
|---|---|---|
| `N:\DBD-UEEditor\UnrealEngine-5.7.4-fork` | `game/dbd` (checked out) | build tree of the dev engine: `modkit-core` merged with the game commits |
| `N:\DBD-UEEditor\ue-split` | `modkit-core` | sparse git worktree of the fork for authoring generic engine changes |
| `C:\Workspace\UnrealEngine-5.7.4-release` | n/a | stock 5.7.4 source, read-only reference |
| `N:\DBD-UEEditor\Suzie-fork` | `main` | Suzie plugin, profiles, tools, packaging; local only |

`modkit-core` contains only generic hooks (no `DBD`, `BHVR` or `DeadByDaylight` text in added lines). `game/dbd` adds the 8 byte `FShaderMapContent` field. The game's uniform buffer layouts are not engine code: the profile file `uniform_layouts.txt` holds them ([cooked-materials-shaders.md](cooked-materials-shaders.md)). The branches `dbd-modkit`, `backup/dbd-modkit` and `wip/split` are archives and scratch.

Commit subject tags: `[engine]` and `[engine-hdr]` (edits an existing public header) on `modkit-core`, `[game:dbd]` on `game/dbd`, `[suzie]`, `[profile:dbd]`, `[plugin:dbd]`, `[tools]`, `[docs]`, `[packaging]` in Suzie-fork. One concern per commit.

## Base and diffs

The git tag `5.7.4-release` in the fork is the stock 5.7.4 base. `git diff --stat 5.7.4-release modkit-core` lists the generic engine changes (78 files). `git diff --stat modkit-core game/dbd` lists the game changes (1 file, `RenderCore/Public/Shader.h`).

## Workflow

- Generic change: commit on `modkit-core` in `ue-split`, then `git merge --no-ff modkit-core` into `game/dbd` in the fork and build there.
- Game specific engine change: `[game:dbd]` commit on `game/dbd` only.
- A second game gets `game/<g2>` created from `modkit-core`; binaries are per game branch.
- `git worktree repair` in the fork fixes `ue-split` after the tree is moved.

## Building (one UBT at a time)

```
cd /d %MODKIT_ROOT%\UnrealEngine-5.7.4-fork
Engine\Build\BatchFiles\Build.bat DBDMountEditor Win64 Development -Project=%MODKIT_ROOT%\DBDMount\DBDMount.uproject -WaitMutex
Engine\Build\BatchFiles\Build.bat ShaderCompileWorker Win64 Development -WaitMutex
```

- Always pass `-WaitMutex`; only one UBT or RunUAT runs at a time. `Setup.bat` is not run (dependencies are in the tree).
- `ShaderCompileWorker` is rebuilt after engine header edits; `DBDMountEditor` is rebuilt after every `UnrealEditor` target build.
- Optional UBA helpers: add `-UBA -UBAHost=<LAN IP of the build PC> -UBAPort=1345 -UBAPrintSummary`; a helper PC runs `UbaAgent.exe -host=<ip>:1345 -dir=<scratch>`. The addresses of this machine's build PC and helper are comments in `DBDMount\ModkitData\ModkitLocal.ini`.
- UBA host side: UBT listens on `<UBAHost>:<UBAPort>` for the duration of the build (log `UbaServer - Listening on <ip>:1345`) and the helper connects in; the build PC's firewall must allow inbound TCP on that port. A `.NET Host` Block rule for the engine tree's bundled `dotnet.exe` (Windows creates one when its first-listen prompt is dismissed) overrides a port allow rule; `netsh advfirewall firewall show rule name=all dir=in verbose` lists it. `Remote processes finished` in the `-UBAPrintSummary` output counts the actions the helper ran; 0 means it never connected. Without a helper UBT limits parallel actions by free memory (1.5 GB per action).
- From PowerShell, quote switches that carry a dotted value (`"-UBAHost=<ip>"`); unquoted, PowerShell splits the argument at the first dot.
- `-Module=<Name>` limits a build to one module (`-Module=Suzie` for the plugin).
- A plugin-only rebuild (Suzie, DBDModkitGame) takes about 15 s.
- Debug info is off in the dev engine (`Engine\Saved\UnrealBuildTool\BuildConfiguration.xml`).
- New files under `Engine` keep their owning header as first include (UBT IWYU check).
- `Suzie-fork\Tools\check-layers.ps1` fails when a game or studio name appears in the generic plugin `Source`.
