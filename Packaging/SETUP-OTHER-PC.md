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
4. [ ] Have **your own** Dead by Daylight install, **version 10.2.2** (section 3).
5. [ ] Have the game's AES key in a text file you create yourself (one line, `0x` + 64 hex digits), outside the package (section 4).
6. [ ] Copy `<PKG>\DBDMount-Template` to your work folder (for example `D:\DBDModkit\Work\DBDMount`).
7. [ ] Extract `AssetRegistry.bin` from the game's containers into the project root (section 5).
8. [ ] Optional: generate the gameplay tags (section 6).
9. [ ] Copy `ModkitLocal.ini.example` to `ModkitLocal.ini` and fill in the paths (section 7).
10. [ ] Register the engine with `Register Engine.cmd` (section 2) or start with `Start Editor.bat`.
11. [ ] First start: wait 15 to 30 minutes (SM5 global shader compile). Do not close the editor.
12. [ ] Check the expected log lines (section 9).

## 1. System requirements

| | |
|---|---|
| OS | Windows 10 (64 bit) or Windows 11 |
| Compiler | Not needed for the template project (no C++ module; plugins are precompiled in the engine). Visual Studio 2022 (Desktop development with C++, Windows 11 SDK) is needed only to add a C++ module to a project or to rebuild the plugins (their `Source` is included). |
| .NET / Python | Only for helper tools: .NET 10 SDK (`ExtractAssetRegistry`), Python 3 (tags, sweep scripts). The editor needs neither. |
| GPU | D3D12 capable with Shader Model 5 (GTX 900 / RX 400 or newer, recent driver). The editor runs with `-d3d12 -sm5`; the cooked shaders exist only as `PCD3D_SM5`. Vulkan and SM6 cannot use them. |
| RAM | 16 GB works; 32 GB is more comfortable for shader compile workers. |
| Disk | The installed engine is about 207 GB (Development and DebugGame editor, client/server/game targets, symbols, docs, templates, no prebuilt DDC), plus the project DDC (a few GB after first start). The game is about 60 to 70 GB. |
| Game | Dead by Daylight **10.2.2**, the version the profile was baked from. Another version needs a new jmap and a re-bake and can show layout differences. |

## 2. Install / register the engine

The folder is the engine; there is no installer.

1. Copy `<PKG>` somewhere short so that `D:\DBDModkit\Windows\Engine\Binaries\Win64\UnrealEditor.exe` exists.
2. Run `vc_redist.x64.exe` once.
3. Registration (only for double-clicking `DBDMount.uproject` or "Switch Unreal Engine version"): run `"Register Engine.cmd"` in the template folder (it uses `..\Windows`, which fits inside the package) or `"Register Engine.cmd" D:\DBDModkit\Windows`. It writes `HKCU\Software\Epic Games\Unreal Engine\Builds\DBDModkit-5.7.4 = <engine folder>` for the current user (no admin rights). The template's `.uproject` has `"EngineAssociation": "DBDModkit-5.7.4"`.
4. Without registration use `Start Editor.bat` in the project: it starts `UnrealEditor.exe` from `..\Windows` or from the environment variable `MODKIT_ENGINE` (the folder that contains `Engine`), e.g. `set MODKIT_ENGINE=D:\DBDModkit\Windows`.

## 3. The game files (you provide them)

* Install Dead by Daylight yourself (Steam). The shipped profile's baked types and shader layouts are from **version 10.2.2**; a newer game needs a re-bake ([section 11](#11-another-game-profile-or-game-version)).
* `GameRoot` in `ModkitLocal.ini` is the folder that contains `DeadByDaylight\Content\Paks` (for example `C:/Program Files (x86)/Steam/steamapps/common/Dead by Daylight`). `Paks` holds 614 containers (307 `.utoc/.ucas` + 307 `.pak`), `global.utoc`, `pakchunk0-Windows.utoc`, ...
* The editor only **reads** the game. Never start the game while the editor runs against the same files.

## 4. The AES key (you provide it)

* The package contains **no key and no game content**. The engine reads the key from the file you name and never logs the value.
* Create a text file (for example `D:\DBDModkit\secrets\dbd-aes.txt`) with one line: the game's 32 byte AES-256 key as `0x` + 64 hex digits. Obtain it from the community modding resources of the game.
* Point to it with `KeyFile=` in `ModkitLocal.ini` (or `-ModkitKeyFile=<file>`, or env `MODKIT_AES_KEY_FILE`).
* Keep the file out of the package, out of version control, chats and logs.

## 5. AssetRegistry.bin (premade registry of the game)

The profile uses the game's own premade asset registry (96,267 assets); it must be in the **project root** as `AssetRegistry.bin`. It is read from the game's first container (`DeadByDaylight/AssetRegistry.bin` in `pakchunk0`), so extract it from **your** install.

Tool in the package: `Windows\Engine\Plugins\Modkit\Suzie\Tools\ExtractAssetRegistry` (C#, uses CUE4Parse).

```
git clone https://github.com/FabianFG/CUE4Parse.git D:\DBDModkit\CUE4Parse          (a recent net10.0 checkout)
cd D:\DBDModkit\Windows\Engine\Plugins\Modkit\Suzie\Tools\ExtractAssetRegistry
dotnet build -c Release -o D:\DBDModkit\tools\ear -p:CUE4ParseDir=D:\DBDModkit\CUE4Parse
dotnet D:\DBDModkit\tools\ear\ExtractAssetRegistry.dll "<GameRoot>\DeadByDaylight\Content\Paks" "<KeyFile>" "<project>\AssetRegistry.bin"
```

It prints `mounted 614 groups ...` and `wrote ...`. The file holds no code and no key; someone with the **same game version** can give you theirs instead.

## 6. Gameplay tags (optional, removes "Invalid GameplayTag" warnings)

Needs the game's `.jmap` ([section 12](#12-jmap-and-usmap-user-only)) and Python 3:

```
python D:\DBDModkit\Windows\Engine\Plugins\Modkit\Suzie\Tools\suzie_tags.py --jmap D:\DBDModkit\game-data\DBD-10.2.2.jmap --project D:\DBDModkit\Work\DBDMount --tags-ini Config/Tags/DBDGameTags.ini
```

It writes `Config\Tags\DBDGameTags.ini` and `Config\DefaultGameplayTags.ini` (the game's tag list plus its redirects). `Suzie.TagInfo` reports the manager's tag count. Skipping this step only produces gameplay tag warnings.

## 7. ModkitLocal.ini (the only machine specific file)

Copy `ModkitLocal.ini.example` to `ModkitLocal.ini` in the project root (next to `DBDMount.uproject`) and edit. Forward slashes:

```ini
[Local]
Profile=D:/DBDModkit/Windows/Engine/Plugins/Modkit/Suzie/Profiles/DBD
GameRoot=C:/Program Files (x86)/Steam/steamapps/common/Dead by Daylight
KeyFile=D:/DBDModkit/secrets/dbd-aes.txt
EngineDir=D:/DBDModkit/Windows
Jmap=D:/DBDModkit/game-data/DBD-10.2.2.jmap
Usmap=D:/DBDModkit/game-data/DBD-10.2.2.usmap
```

| Field | Required | Meaning |
|---|---|---|
| `Profile` | yes | the profile **FOLDER** `...\Profiles\DBD` (the folder that contains `profile.json` and `engine.ini`), not the file `profile.json`. `engine.ini` is read by the engine, `profile.json` by Suzie. Selecting a profile switches the modkit on; without it the editor is stock UE 5.7.4 and Suzie logs `Suzie idle: no profile selected`. |
| `GameRoot` | yes | install root of the game; the profile probes `Paks`, `Content/Paks`, `DeadByDaylight/Content/Paks` |
| `KeyFile` | yes | path of the AES key file (path only, never the key) |
| `EngineDir` | no | engine root for the sweep scripts; otherwise derived from `EngineAssociation` / `MODKIT_ENGINE` |
| `Jmap` | no | only for `suzie_tags.py` and re-baking |
| `Usmap` | no | only for external tools; `Suzie.VerifyNativeTypes` uses the schema dump in the profile (`data/cache/game_schemas.tsv`, override with `UsmapTsv=`) |

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
LogAssetRegistry: Premade AssetRegistry loaded from '.../AssetRegistry.bin'
LogInit: Display: Modkit: opened shader library 'DeadByDaylight': yes (total shaders in library: 164124, library enabled: 1)
LogInit: Display: Modkit: registered 238 game plugin content roots (238 .uplugin files found).
LogSuzie: GENERATE OK ... enums=1099(+21 existing) structs=2571 ... classes=7592 ... functions=14459 properties=59194 ... overrides=50/160/0
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
| 0 containers mounted, `failed to fill whole buffer` or index errors | Wrong `GameRoot`, wrong or missing key, or a game version other than the one the profile was baked for. Stock tools cannot read the containers; only this engine's cipher from `engine.ini` can. |
| `LogModkit ... key file` error | `KeyFile=` path is wrong or the file does not hold `0x` + 64 hex digits. The value is never logged. |
| Materials render as the default/grey material, `Incomplete material` | `r.AllowStaticLighting=False` is missing in `Config/DefaultEngine.ini`, or the editor runs with SM6/Vulkan: start with `-d3d12 -sm5`. A few `missing TShadowDepthPS...` lines are normal (permutations the game did not cook). |
| `tolerating layout hash mismatch for FMaterialShaderMapContent / FMeshMaterialShaderMap` | Expected; the types are listed under `[ShaderLayout] TolerateMismatch`. |
| Many `Invalid GameplayTag` warnings | Tags not generated: run `suzie_tags.py` (tags.md). |
| Crashes after a failed experiment, corrupt shader cache | Use an isolated DDC (`UE-LocalDataCachePath`), delete that folder and restart. Never share one DDC between the stock editor and this one. |
| `Plugin 'Suzie' ... duplicate` | The plugins are also copied into `<project>\Plugins` of an installed-engine project; remove them (they are engine plugins there). |
| `Missing or incompatible game module` | The project has a `Source` folder or `Modules` entry; the template is content only. Remove them or build the module with Visual Studio. |
| `Project was made with a different version` dialog, double click opens the wrong engine | The engine is not registered or registered under another id; run `Register Engine.cmd` or use `Start Editor.bat`. |
| 15 to 30 minutes of nothing on first start | Normal: SM5 global shader compile with an empty DDC. Watch the `ShaderCompileWorker` processes. |
| Out of memory during shader compile | Close other programs; 16 GB RAM works. |
| Crash or `bIsOptional && ElementSize` assertion after a game update | The game version differs from the version the profile was baked for: unversioned data desynchronizes. Re-bake with the new jmap (native-type-generation.md). |
| `SchemaIt != SchemaEnd` assertion | A game class or struct has reflected members that the schema recipes do not account for (schema-shadow-properties.md). |
| DataTable assertion in the unversioned loader for a row struct with a natively serialized struct (`BarkRuleDB`) | The `DBDModkitGame` plugin did not load: check it is enabled in the `.uproject` and `LogSuzie` names the extension module. |
| `Suzie: profile ... has no baked types file` | `Profiles/<Game>/data/bake/types.json` is missing (generated, gitignored): run the baker. |
| `Suzie.VerifyNativeTypes` finds no schema dump | `data/cache/game_schemas.tsv` (or `UsmapTsv=`) is missing. |
| Editor does not find the engine in `Start Editor.bat` | Set `MODKIT_ENGINE` to the folder that contains `Engine` (installed template) or check `MODKIT_ROOT` (dev tree, `tools\env\modkit-env.cmd`). |
| After moving the tree: plugins missing, worktree errors | Recreate the junctions `DBDMount\Plugins\Suzie` and `DBDMount\Plugins\DBDModkitGame` (`mklink /J`), run `git worktree repair` in the engine fork, delete `Intermediate` folders and rebuild, edit `ModkitLocal.ini`. |

## 11. Another game profile or game version

* Everything game specific is **data in a profile folder** (`Suzie\Profiles\<Game>`: `engine.ini` for the engine, `profile.json` + `schema/`, `load/`, `tags/`, baked `data/bake/types.json` for Suzie, optional `Plugin/<GamePlugin>` with the only game code). Switch with `Profile=` in `ModkitLocal.ini` (or `-ModkitProfile=`).
* This installed build is the `game/dbd` branch: besides the generic hooks it contains the DBD 10.2.2 uniform buffer layouts and a `FShaderMapContent` +8 byte field. A second game generally needs its own engine branch and installed build; only games whose shader layouts equal the engine's can reuse it with another profile.
* New game: create `Profiles/<G2>` from the DBD profile (copy `engine.ini`, an empty `schema/engine_diff.json`, `load/skip.json`, `tags/tags.json`), produce the game's jmap, bake (`tools/dbd_native_baker.py`; `Profiles/DBD/tools/bake_all.cmd`), set `ModkitLocal.ini`, run `Suzie.VerifyNativeTypes`, turn the reported engine class differences into recipes (data), run the sweep harness.
* New DBD version: new jmap, run `Profiles\DBD\tools\bake_all.cmd` with `SUZIE_JMAP` set, and re-check layouts if the shader parameter structs changed.

## 12. jmap and usmap (user only)

* The `.jmap` is a JSON reflection dump of the **running** game process (trumank/jmap `jmap_dumper` format); the `.usmap` is the unversioned property mapping used by CUE4Parse style tools.
* The editor does not need either with the shipped profile (it contains the baked types for 10.2.2 and the usmap schema dump). The jmap is needed for tags and re-baking, the usmap for external tools.
* **Producing a jmap/usmap requires running the game** (or a memory dump of it), with whatever anti-cheat and terms-of-service consequences that has. This package never does it; it is entirely your decision and responsibility.

## 13. Licensing

This folder contains a **modified Unreal Engine 5.7.4** built from Epic's source. Unreal Engine is subject to the Unreal Engine End User License Agreement; redistributing built engine binaries or source is permitted only under that EULA (source access is granted to registered licensees and sharing is limited to other licensees). Do not share this package publicly.
`Suzie` is a fork of trumank/Suzie (MIT, see its `LICENSE`); `CUE4Parse` has its own license.
**No game content, assets or encryption keys are included.** The profile contains reflection data derived from the game's executable metadata (class, struct and property names in `data/bake/types.json`); treat it as game derived material for your own use. Dead by Daylight and its assets belong to Behaviour Interactive.

Known limitations of this build: `docs/limitations.md` of the DBD-UEEditor project.
