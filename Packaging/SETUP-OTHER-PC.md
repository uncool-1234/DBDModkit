# DBD modkit editor (UE 5.7.4 installed build): setup on another PC

Package layout (the folder you were given, called `<PKG>` below):

```
<PKG>\Windows\                 the installed engine (UnrealEditor.exe is in Windows\Engine\Binaries\Win64)
<PKG>\DBDMount-Template\       ready-to-use content-only project (copy it, do not edit it in place)
<PKG>\SETUP-OTHER-PC.md        this file
```

This is a modified Unreal Engine 5.7.4 editor that mounts Dead by Daylight's cooked IoStore/pak containers, loads the game's shared shader library and opens the game's cooked materials, meshes, Blueprints, AnimBPs and widgets (the game's native classes are generated in memory at editor start).
The two plugins that do this, `Suzie` and `DBDModkitGame`, are **engine plugins of this build** (`Windows\Engine\Plugins\Modkit`), already compiled. You need no Visual Studio, C++ toolchain or engine source.

## 0. Checklist

1. [ ] Windows 10/11 64 bit, 16 GB RAM or more, a GPU with D3D12 Shader Model 5, about 220 GB free for the engine copy plus 30+ GB for the shader cache.
2. [ ] Copy `<PKG>` to a local SSD with a **short path** (for example `D:\DBDModkit`), not into a OneDrive/Dropbox folder.
3. [ ] Install the Visual C++ runtime once: `<PKG>\Windows\Engine\Extras\Redist\en-us\vc_redist.x64.exe`.
4. [ ] Have **your own** Dead by Daylight install, **version 10.2.2** (section 3), and the game's `.jmap` for that version (section 12).
5. [ ] Have the game's AES key in a text file you create yourself (one line, `0x` + 64 hex digits), outside the package (section 4).
6. [ ] Copy `<PKG>\DBDMount-Template` to your work folder (for example `D:\DBDModkit\Work\DBDMount`).
7. [ ] Asset registry: no step; the editor reads it from the game's containers (section 5).
8. [ ] Gameplay tags need no step: the editor writes them from the jmap (section 6).
9. [ ] Copy `ModkitLocal.ini.example` to `ModkitLocal.ini` and fill in the paths (section 7).
10. [ ] Register the engine with `Register Engine.cmd` (section 2) or start with `Start Editor.bat`.
11. [ ] First start: wait 15 to 30 minutes (SM5 global shader compile). Do not close the editor.
12. [ ] Check the expected log lines (section 9).

## 1. System requirements

| | |
|---|---|
| OS | Windows 10 (64 bit) or Windows 11 |
| Compiler | Not needed for the template project (no C++ module; plugins are precompiled in the engine). Visual Studio 2022 (Desktop development with C++, Windows 11 SDK) is needed only to add a C++ module to a project or to rebuild the plugins (their `Source` is included). |
| .NET / Python | Only for helper tools: Python 3 (sweep scripts). The editor needs neither. |
| GPU | D3D12 capable with Shader Model 5 (GTX 900 / RX 400 or newer, recent driver). The editor runs with `-d3d12 -sm5`; the cooked shaders exist only as `PCD3D_SM5`. Vulkan and SM6 cannot use them. |
| RAM | 16 GB works; 32 GB is more comfortable for shader compile workers. |
| Disk | The installed engine is about 207 GB (Development and DebugGame editor, client/server/game targets, symbols, docs, templates, no prebuilt DDC), plus the project DDC (a few GB after first start). The game is about 60 to 70 GB. |
| Game | Dead by Daylight **10.2.2**, the version the shader layouts of this build match. Another version needs the jmap of that version and can show layout differences. |

## 2. Install / register the engine

The folder is the engine; there is no installer.

1. Copy `<PKG>` somewhere short so that `D:\DBDModkit\Windows\Engine\Binaries\Win64\UnrealEditor.exe` exists.
2. Run `vc_redist.x64.exe` once.
3. Registration (only for double-clicking `DBDMount.uproject` or "Switch Unreal Engine version"): run `"Register Engine.cmd"` in the template folder (it uses `..\Windows`, which fits inside the package) or `"Register Engine.cmd" D:\DBDModkit\Windows`. It writes `HKCU\Software\Epic Games\Unreal Engine\Builds\DBDModkit-5.7.4 = <engine folder>` for the current user (no admin rights). The template's `.uproject` has `"EngineAssociation": "DBDModkit-5.7.4"`.
4. Without registration use `Start Editor.bat` in the project: it starts `UnrealEditor.exe` from `..\Windows` or from the environment variable `MODKIT_ENGINE` (the folder that contains `Engine`), e.g. `set MODKIT_ENGINE=D:\DBDModkit\Windows`.

## 3. The game files (you provide them)

* Install Dead by Daylight yourself (Steam). The shipped profile and the shader layouts of this build are for **version 10.2.2**; a newer game needs its own jmap ([section 11](#11-another-game-profile-or-game-version)).
* `GameRoot` in `ModkitLocal.ini` is the folder that contains `DeadByDaylight\Content\Paks` (for example `C:/Program Files (x86)/Steam/steamapps/common/Dead by Daylight`). `Paks` holds 614 containers (307 `.utoc/.ucas` + 307 `.pak`), `global.utoc`, `pakchunk0-Windows.utoc`, ...
* The editor only **reads** the game. Never start the game while the editor runs against the same files.

## 4. The AES key (you provide it)

* The package contains **no key and no game content**. The engine reads the key from the file you name and never logs the value.
* Create a text file (for example `D:\DBDModkit\secrets\dbd-aes.txt`) with one line: the game's 32 byte AES-256 key as `0x` + 64 hex digits. Obtain it from the community modding resources of the game.
* Point to it with `KeyFile=` in `ModkitLocal.ini` (or `-ModkitKeyFile=<file>`, or env `MODKIT_AES_KEY_FILE`).
* Keep the file out of the package, out of version control, chats and logs.

## 5. Asset registry (premade registry of the game)

The profile uses the game's own premade asset registry (96,267 assets). The engine reads it straight from the mounted container: `DeadByDaylight/AssetRegistry.bin` in `pakchunk0`, named by `[AssetRegistry] PakPath` in the profile's `engine.ini`. No extraction and no file in the project is needed.

A file `<project>\EditorClientAssetRegistry.bin` or `<project>\AssetRegistry.bin`, when present, is loaded instead of the one in the container.
## 6. Gameplay tags (automatic)

No step is needed. After generating the types the editor writes the game's tag list and redirects from the jmap to `<project>\Config\Tags\DBDGameTags.ini` and `<project>\Config\DefaultGameplayTags.ini` (only when their content differs) and logs `Gameplay tags written from the jmap: N tags, M redirects`. Changed redirects apply from the next editor start. `Suzie.TagInfo` reports the manager's tag count.

## 7. ModkitLocal.ini (the only machine specific file)

Copy `ModkitLocal.ini.example` to `ModkitLocal.ini` in the project root (next to `DBDMount.uproject`) and edit. Forward slashes:

```ini
[Local]
Profile=D:/DBDModkit/Windows/Engine/Plugins/Modkit/Suzie/Profiles/DBD
GameRoot=C:/Program Files (x86)/Steam/steamapps/common/Dead by Daylight
KeyFile=D:/DBDModkit/secrets/dbd-aes.txt
EngineDir=D:/DBDModkit/Windows
Jmap=D:/DBDModkit/game-data/DBD-10.2.2.jmap
```

| Field | Required | Meaning |
|---|---|---|
| `Profile` | yes | the profile **FOLDER** `...\Profiles\DBD` (the folder that contains `profile.json` and `engine.ini`), not the file `profile.json`. `engine.ini` is read by the engine, `profile.json` by Suzie. Selecting a profile switches the modkit on; without it the editor is stock UE 5.7.4 and Suzie logs `Suzie idle: no profile selected`. |
| `GameRoot` | yes | install root of the game; the profile probes `Paks`, `Content/Paks`, `DeadByDaylight/Content/Paks` |
| `KeyFile` | yes | path of the AES key file (path only, never the key) |
| `EngineDir` | no | engine root for the sweep scripts; otherwise derived from `EngineAssociation` / `MODKIT_ENGINE` |
| `Jmap` | yes | the game's jmap of your game version ([section 12](#12-the-jmap-you-provide-it)); Suzie reads it at every editor start. Without it the editor generates no types and logs `Suzie idle: profile 'dbd' needs the game's jmap, ...` |

Project settings (already in the template `Config\DefaultEngine.ini`; keep them in your own projects):

```ini
[/Script/UnrealEd.CookerSettings]
cook.AllowCookedDataInEditorBuilds=True
s.AllowUnversionedContentInEditor=1
[/Script/WindowsTargetPlatform.WindowsTargetSettings]
DefaultGraphicsRHI=DefaultGraphicsRHI_DX12
-D3D12TargetedShaderFormats=PCD3D_SM6
+D3D12TargetedShaderFormats=PCD3D_SM5
+D3D11TargetedShaderFormats=PCD3D_SM5
[/Script/Engine.RendererSettings]
r.AllowStaticLighting=False
```

`r.AllowStaticLighting=False` is **required**: the game cooked no static lighting permutations. The `.uproject` enables both plugins (`Suzie`, `DBDModkitGame`; already in the template). Do not also copy them into the project's `Plugins` folder.

## 8. Launch

```
set UE-LocalDataCachePath=D:\DBDModkit\Work\DBDMount\DDC
D:\DBDModkit\Windows\Engine\Binaries\Win64\UnrealEditor.exe D:\DBDModkit\Work\DBDMount\DBDMount.uproject -log -d3d12 -sm5
```

or run `Start Editor.bat` in the project (it sets the isolated DDC and the switches).

No DDC is shipped: the first launch compiles the SM5 global shaders and engine content shaders (**15 to 30 minutes**; the window may stay empty). Later starts take 1 to 2 minutes. `UE-LocalDataCachePath` is a per-project cache; delete it to reset.
Other switches: `-DisableModkit` (stock behaviour), `-DisableSuzie`, `-ModkitProfile=<dir>`, `-ModkitKeyFile=<file>`, `-ModkitGameDir=<dir>`, `-NoPaks`.

## 9. Verify that it works

In `<project>\Saved\Logs\DBDMount.log`:

```
LogModkit: Display: Modkit profile 'dbd' (...Profiles/DBD) active, game Paks directory: ...
LogModkit: Display: Loaded AES key from '...' (value not logged).
LogPakFile: Display: Mounted IoStore container ... (307 times) and Mounted Pak file ... (307 times) + the global container
LogAssetRegistry: Premade AssetRegistry loaded from '../../../DeadByDaylight/AssetRegistry.bin'
LogInit: Display: Modkit: opened shader library 'DeadByDaylight': yes (total shaders in library: 164124, library enabled: 1)
LogInit: Display: Modkit: registered 238 game plugin content roots (238 .uplugin files found).
LogSuzie: jmap <file>: 63026 objects, parse 8.1s, derive 1.1s
LogSuzie: GENERATE OK ... enums=1099(+20 existing) structs=2571 ... classes=7592 ... functions=14459 properties=59194 ... overrides=50/160/0
LogSuzie: Gameplay tags written from the jmap: N tags, M redirects
```

`findstr /c:"Mounted IoStore container" DBDMount.log | find /c /v ""` gives 307. In the editor console `Suzie.VerifyNativeTypes` reports `VERIFY RESULT: types=10163 ok=10004 mismatch=159`.

Regression gates (optional, 10 to 20 minutes with a warm DDC; Python 3 required):

```
powershell -File D:\DBDModkit\Windows\Engine\Plugins\Modkit\Suzie\Tools\sweep\run_gates.ps1 -Tag mycheck -Project D:\DBDModkit\Work\DBDMount\DBDMount.uproject
```

Expected: Blueprint sweep CLEAN >= 529, DIRTY <= 2, CRASH 0; material sweep PASS 200 of 200; results in `<project>\Saved\SuzieSweeps`.

## 10. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Editor starts as plain UE, no `LogModkit` lines; `LogSuzie: Suzie idle: no profile selected` | No profile selected. `ModkitLocal.ini` is missing, is not in the project root next to the `.uproject`, or `Profile=` is not a profile folder: it must be the folder that contains `profile.json` and `engine.ini` (for example `.../Profiles/DBD`), not the file `profile.json`. `-DisableModkit` also causes it. |
| 0 containers mounted, `failed to fill whole buffer` or index errors | Wrong `GameRoot`, wrong or missing key, or a game version other than the one of your jmap and of this build. Stock tools cannot read the containers; only this engine's cipher from `engine.ini` can. |
| `LogModkit ... key file` error | `KeyFile=` path is wrong or the file does not hold `0x` + 64 hex digits. The value is never logged. |
| Materials render as the default/grey material, `Incomplete material` | `r.AllowStaticLighting=False` is missing in `Config/DefaultEngine.ini`, or the editor runs with SM6/Vulkan: start with `-d3d12 -sm5`. A few `missing TShadowDepthPS...` lines are normal (permutations the game did not cook). |
| `tolerating layout hash mismatch for FMaterialShaderMapContent / FMeshMaterialShaderMap` | Expected; the types are listed under `[ShaderLayout] TolerateMismatch`. |
| Many `Invalid GameplayTag` warnings | The jmap is missing or has no tag settings object, or the tags were written during this start and the redirects apply from the next start (tags.md). |
| Crashes after a failed experiment, corrupt shader cache | Use an isolated DDC (`UE-LocalDataCachePath`), delete that folder and restart. Never share one DDC between the stock editor and this one. |
| `Plugin 'Suzie' ... duplicate` | The plugins are also copied into `<project>\Plugins` of an installed-engine project; remove them (they are engine plugins there). |
| `Missing or incompatible game module` | The project has a `Source` folder or `Modules` entry; the template is content only. Remove them or build the module with Visual Studio. |
| `Project was made with a different version` dialog, double click opens the wrong engine | The engine is not registered or registered under another id; run `Register Engine.cmd` or use `Start Editor.bat`. |
| 15 to 30 minutes of nothing on first start | Normal: SM5 global shader compile with an empty DDC. Watch the `ShaderCompileWorker` processes. |
| Out of memory during shader compile | Close other programs; 16 GB RAM works. |
| Crash or `bIsOptional && ElementSize` assertion after a game update | The game version differs from the version of the jmap (or of this build): unversioned data desynchronizes. Use the jmap of the game version you run and restart (native-type-generation.md). |
| `SchemaIt != SchemaEnd` assertion | A game class or struct has reflected members that the schema recipes do not account for (schema-shadow-properties.md). |
| DataTable assertion in the unversioned loader for a row struct with a natively serialized struct (`BarkRuleDB`) | The `DBDModkitGame` plugin did not load: check it is enabled in the `.uproject` and `LogSuzie` names the extension module. |
| `Suzie idle: profile 'dbd' needs the game's jmap, ...` | `Jmap=` in `ModkitLocal.ini` is missing or names a file that does not exist; set it or pass `-SuzieJmap=<file>`. |
| Editor start takes about 9 seconds longer than a stock start | Normal: Suzie parses the jmap (180 MB for 10.2.2) at every start. |
| Editor does not find the engine in `Start Editor.bat` | Set `MODKIT_ENGINE` to the folder that contains `Engine` (installed template) or check `MODKIT_ROOT` (dev tree, `tools\env\modkit-env.cmd`). |
| After moving the tree: plugins missing, worktree errors | Recreate the junctions `DBDMount\Plugins\Suzie` and `DBDMount\Plugins\DBDModkitGame` (`mklink /J`), run `git worktree repair` in the engine fork, delete `Intermediate` folders and rebuild, edit `ModkitLocal.ini`. |

## 11. Another game profile or game version

* Everything game specific is **data in a profile folder** (`Suzie\Profiles\<Game>`: `engine.ini` for the engine, `profile.json` + `schema/`, `load/`, `tags/` for Suzie, optional `Plugin/<GamePlugin>` with the only game code). Switch with `Profile=` in `ModkitLocal.ini` (or `-ModkitProfile=`).
* This installed build is the `game/dbd` branch: besides the generic hooks it contains a `FShaderMapContent` +8 byte field. The DBD 10.2.2 uniform buffer layouts are data in the profile (`uniform_layouts.txt`). A second game needs its own `uniform_layouts.txt` when its uniform buffer layouts differ, and its own engine branch and installed build when engine struct sizes differ.
* New game: create `Profiles/<G2>` from the DBD profile (copy `engine.ini`, `profile.json`, `load/skip.json`, `tags/tags.json`), obtain the game's jmap, set `ModkitLocal.ini` (`Jmap=`), run `Suzie.VerifyNativeTypes`, run the sweep harness.
* New DBD version: set `Jmap=` to the jmap of the new version and restart; types, schema recipes and gameplay tags follow from it. The asset registry follows from the game install. If the game changed its uniform buffer layouts, the profile needs a new `uniform_layouts.txt` (a developer step from a minidump of the game).

## 12. The jmap (you provide it)

* The `.jmap` is a JSON reflection dump of the **running** game process (trumank/jmap `jmap_dumper` format). It must be the jmap of **your game version**; jmaps of a game version circulate in the modding community like the AES key. This package contains none.
* Set `Jmap=` in `ModkitLocal.ini` (or pass `-SuzieJmap=<file>`). The editor needs it at every start: it generates the game's native types, the schema recipes and the gameplay tags from it. Without it nothing is generated.
* The AES key goes in its own file (section 4); the jmap is a separate file and holds no key.
* **Producing a jmap requires running the game** (or a memory dump of it), with whatever anti-cheat and terms-of-service consequences that has. This package never does it; it is entirely your decision and responsibility.

## 13. Licensing

This folder contains a **modified Unreal Engine 5.7.4** built from Epic's source. Unreal Engine is subject to the Unreal Engine End User License Agreement; redistributing built engine binaries or source is permitted only under that EULA (source access is granted to registered licensees and sharing is limited to other licensees). Do not share this package publicly.
`Suzie` is a fork of trumank/Suzie (MIT, see its `LICENSE`).
**No game content, assets or encryption keys are included.** The profile's test references (`data/golden`, `sweeps/`) list names of the game's types and assets. The jmap and the key file are yours. Dead by Daylight and its assets belong to Behaviour Interactive.

Known limitations of this build: `docs/limitations.md` of the DBD-UEEditor project.
