# DBD modkit editor (UE 5.7.4 installed build): setup on another PC

The release is one encrypted `.7z` archive (AES-256, encrypted file names; the password is delivered separately; a `.sha256` file sits next to it). Extracting it needs 7-Zip or another 7z tool. The extracted folder (called `<PKG>` below) contains:

```
<PKG>\UnrealEngine-5.7.4-DBD\   the installed engine (Engine\..., Register Engine.bat)
<PKG>\DBDMount-Template\        project template: DBDMount.uproject, Config, Content, .gitignore
<PKG>\VERSION.txt
```

This is a modified Unreal Engine 5.7.4 editor that mounts Dead by Daylight's cooked IoStore/pak containers, loads the game's shared shader library and opens the game's cooked materials, meshes, Blueprints, AnimBPs and widgets (the game's native classes are generated in memory at editor start).
The two plugins that do this, `Suzie` and `DBDModkitGame`, are **engine plugins of this build** (`UnrealEngine-5.7.4-DBD\Engine\Plugins\Modkit`), already compiled. You need no Visual Studio, C++ toolchain or engine source.

## 0. Checklist

1. [ ] Windows 10/11 64 bit, 16 GB RAM or more, a GPU with D3D12 Shader Model 5, about 30 GB free for the extracted engine plus room for the archive while extracting, and 30+ GB for the shader cache.
2. [ ] Extract the archive to a local SSD with a **short path** (for example `D:\DBDModkit`), not into a OneDrive/Dropbox folder.
3. [ ] Install the Visual C++ runtime once: `<PKG>\UnrealEngine-5.7.4-DBD\Engine\Extras\Redist\en-us\vc_redist.x64.exe`.
4. [ ] Have **your own** Dead by Daylight install, **version 10.2.2** (section 3), the game's AES key in a text file (section 4) and the game's `.jmap` for that version (section 11).
5. [ ] Run `Register Engine.bat` in the engine folder (section 2).
6. [ ] Copy `<PKG>\DBDMount-Template` to your work folder (for example `D:\DBDModkit\Work\DBDMount`) or use it in place.
7. [ ] Create a folder `ModkitData` next to `DBDMount.uproject` and put the key file and the jmap in it (section 5).
8. [ ] Double-click `DBDMount.uproject`: the `Modkit project setup` window opens; choose the game folder and save (section 5).
9. [ ] Double-click `DBDMount.uproject`. First start: wait 15 to 30 minutes (SM5 global shader compile). Do not close the editor.
10. [ ] Check the expected log lines (section 8).

The asset registry and the gameplay tags need no step (section 6).

## 1. System requirements

| | |
|---|---|
| OS | Windows 10 (64 bit) or Windows 11 |
| Compiler | Not needed for the template project (no C++ module; plugins are precompiled in the engine). Visual Studio 2022 (Desktop development with C++, Windows 11 SDK) is needed only to add a C++ module to a project or to rebuild the plugins (their `Source` is included). |
| .NET / Python | Only for helper tools: Python 3 (sweep scripts). The editor needs neither. |
| GPU | D3D12 capable with Shader Model 5 (GTX 900 / RX 400 or newer, recent driver). The editor runs with `-d3d12 -sm5`; the cooked shaders exist only as `PCD3D_SM5`. Vulkan and SM6 cannot use them. |
| RAM | 16 GB works; 32 GB is more comfortable for shader compile workers. |
| Disk | The extracted engine is about 28 GB (Development editor, game target for Development and Shipping; no debug symbols, engine documentation, templates or prebuilt DDC), plus the project DDC (a few GB after first start). The game is about 60 to 70 GB. |
| Game | Dead by Daylight **10.2.2**, the version the shader layouts of this build match. Another version needs the jmap of that version and can show layout differences. |

## 2. Engine registration

The folder is the engine; there is no installer.

1. Run `vc_redist.x64.exe` once.
2. Run `Register Engine.bat` in the root of `UnrealEngine-5.7.4-DBD` (next to `Engine\`). It writes `HKCU\Software\Epic Games\Unreal Engine\Builds\DBDModkit-5.7.4 = <engine folder>` for the current user (no admin rights). The template's `.uproject` has `"EngineAssociation": "DBDModkit-5.7.4"`, so after registration double-clicking `DBDMount.uproject` opens it with this engine.
3. Double-clicking the `.uproject` needs the engine registered under the id in its `EngineAssociation`, or that field holds the path of the engine folder. The sweep tools find the engine the same way when `EngineDir` is not in the ini.

## 3. The game files (you provide them)

* Install Dead by Daylight yourself (Steam). The shipped profile and the shader layouts of this build are for **version 10.2.2**; a newer game needs its own jmap ([section 10](#10-another-game-profile-or-game-version)).
* `GameRoot` in `ModkitData\ModkitLocal.ini` (chosen in the setup window, section 5) is the folder that contains `DeadByDaylight\Content\Paks` (for example `C:/Program Files (x86)/Steam/steamapps/common/Dead by Daylight`). `Paks` holds 614 containers (307 `.utoc/.ucas` + 307 `.pak`), `global.utoc`, `pakchunk0-Windows.utoc`, ...
* The editor only **reads** the game. Never start the game while the editor runs against the same files.

## 4. The AES key (you provide it)

* The package contains **no key and no game content**. The engine reads the key from the file you name and never logs the value.
* Create a `.txt` file (for example `dbd-aes.txt`) with one line: the game's 32 byte AES-256 key as `0x` + 64 hex digits. Obtain it from the community modding resources of the game.
* Put it in the project's `ModkitData` folder (section 5). The setup window records its path and never reads its contents. The engine also accepts `-ModkitKeyFile=<file>` and the environment variable `MODKIT_AES_KEY_FILE`.
* Keep the file out of version control, chats and logs.

## 5. Project setup (the setup window)

The machine specific paths live in one file, `<project>\ModkitData\ModkitLocal.ini`. The editor writes it; you never write it by hand.

1. Put the key file (`*.txt`) and the jmap (`*.jmap`) in the folder `ModkitData` next to `DBDMount.uproject`. The usmap (`*.usmap`) is optional and used only by external tools. Keep one file per extension. Other files and folders in `ModkitData` are ignored.
2. Double-click `DBDMount.uproject`. When a path is missing or invalid, the editor shows the `Modkit project setup` window before the profile starts. It has one row per path:
   * the game folder (`Dead by Daylight folder`): the install folder that contains `DeadByDaylight\Content\Paks\global.utoc`;
   * `KeyFile`, `Jmap` and `Usmap (optional)`: the file. A row is filled in when `ModkitData` holds exactly one file of that extension.
   Type a path or use `...` to browse. Each row shows `valid` or `invalid`. `Save and restart` is enabled when every required row is valid; it writes `ModkitLocal.ini` and restarts the editor. `Cancel` closes the window and the editor starts without the game's content. With several profile folders the window asks for one; with one, the editor chooses it.
3. The window opens again on a start where a path is missing or invalid, for example after the game or a data file moved. When every path is valid it does not open.

The profile's `project.json` names the game and the data files that the window shows. The window writes `Profile=`, `GameRoot=` and the data file keys; other keys and comments in the file are kept.

```ini
[Local]
Profile=D:/DBDModkit/UnrealEngine-5.7.4-DBD/Engine/Plugins/Modkit/Suzie/Profiles/DBD
GameRoot=C:/Program Files (x86)/Steam/steamapps/common/Dead by Daylight
KeyFile=D:/DBDModkit/Work/DBDMount/ModkitData/dbd-aes.txt
Jmap=D:/DBDModkit/Work/DBDMount/ModkitData/DBD-10.2.2.jmap
```

| Key | Required | Meaning |
|---|---|---|
| `Profile` | yes | the profile **FOLDER** `...\Profiles\DBD` (the folder that contains `profile.json` and `engine.ini`), not the file `profile.json`. `engine.ini` is read by the engine, `profile.json` by Suzie. Selecting a profile switches the modkit on; without it the editor is stock UE 5.7.4 and Suzie logs `Suzie idle: no profile selected`. |
| `EngineDir` | no | engine root, read by the sweep tools. Without it they take the engine from the `.uproject` `EngineAssociation`. The editor does not read it. |
| `GameRoot` | yes | install root of the game; the profile probes `Paks`, `Content/Paks`, `DeadByDaylight/Content/Paks` |
| `KeyFile` | yes | path of the AES key file (path only, never the key) |
| `Jmap` | yes | the game's jmap of your game version ([section 11](#11-the-jmap-you-provide-it)); Suzie reads it at every editor start. Without it the editor generates no types and logs `Suzie idle: profile 'dbd' needs the game's jmap, ...` |
| `Usmap` | no | the game's usmap, for external tools only |

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
r.SupportStationarySkylight=False
r.SupportLowQualityLightmaps=False
r.DBuffer=False
```

The four `r.` settings are **required**: the game cooked no permutations for static lighting, stationary skylight, low quality lightmaps or DBuffer. The `.uproject` enables both plugins (`Suzie`, `DBDModkitGame`; already in the template). Do not also copy them into the project's `Plugins` folder.

## 6. Asset registry and gameplay tags (automatic)

**Asset registry.** The profile uses the game's own premade asset registry (96,267 assets). The engine reads it straight from the mounted container: `DeadByDaylight/AssetRegistry.bin` in `pakchunk0`, named by `[AssetRegistry] PakPath` in the profile's `engine.ini`. No extraction and no file in the project is needed. A file `<project>\EditorClientAssetRegistry.bin` or `<project>\AssetRegistry.bin`, when present, is loaded instead of the one in the container.

**Gameplay tags.** After generating the types the editor writes the game's tag list and redirects from the jmap to `<project>\Config\Tags\DBDGameTags.ini` and `<project>\Config\DefaultGameplayTags.ini` (only when their content differs) and logs `Gameplay tags written from the jmap: N tags, M redirects`. Changed redirects apply from the next editor start. `Suzie.TagInfo` reports the manager's tag count.

## 7. Launch

Double-click `DBDMount.uproject` (or the `.uproject` of your project). The engine that opens it is the one named by the `.uproject` `EngineAssociation` (the shipped template uses the id registered by `Register Engine.bat`). The project's `Config` selects D3D12 and SM5, so no switches are needed. When the modkit profile is active the engine sets `UE-LocalDataCachePath` to `<project>\DDC` unless the variable is already set. Extra editor arguments go on an `UnrealEditor.exe` command line:

```
UnrealEditor.exe <project>\DBDMount.uproject -log
```

If a path is not set up or is invalid, the editor shows the `Modkit project setup` window (section 5) before the profile starts. The same problems are logged as a Warning (`LogSuzie`, `Modkit project setup: ...`). Unattended runs do not show the window.

No DDC is shipped: the first launch compiles the SM5 global shaders and engine content shaders (**15 to 30 minutes**; the window may stay empty). Later starts take 1 to 2 minutes. Delete `<project>\DDC` to reset the cache.
Other switches: `-DisableModkit` (stock behaviour), `-DisableSuzie`, `-ModkitProfile=<dir>`, `-ModkitKeyFile=<file>`, `-ModkitGameDir=<dir>`, `-NoPaks`.

## 8. Verify that it works

In `<project>\Saved\Logs\DBDMount.log`:

```
LogModkit: Display: Modkit profile 'dbd' (...Profiles/DBD) active, game Paks directory: ...
LogModkit: Display: Loaded AES key from '...' (value not logged).
LogPakFile: Display: Mounted IoStore container ... (307 times) and Mounted Pak file ... (307 times) + the global container
LogAssetRegistry: Premade AssetRegistry loaded from '../../../DeadByDaylight/AssetRegistry.bin'
LogInit: Display: Modkit: opened shader library 'DeadByDaylight': yes (total shaders in library: 164124, library enabled: 1)
LogInit: Display: Modkit: registered 238 game plugin content roots (238 .uplugin files found, 0 outside their scan root and mapped to their own folder), 239 container directories recorded, project plugins folder: <Project>/Plugins/
LogSuzie: jmap <file>: 63026 objects, parse 8.1s, derive 1.1s
LogSuzie: GENERATE OK ... enums=1099(+20 existing) structs=2571 ... classes=7592 ... functions=14459 properties=59194 ... overrides=50/160/0
LogSuzie: Gameplay tags written from the jmap: N tags, M redirects
```

`findstr /c:"Mounted IoStore container" DBDMount.log | find /c /v ""` gives 307. In the editor console `Suzie.VerifyNativeTypes` reports `VERIFY RESULT: types=10163 ok=10004 mismatch=159`.

Regression gates (optional, 10 to 20 minutes with a warm DDC; Python 3 required):

```
powershell -File D:\DBDModkit\UnrealEngine-5.7.4-DBD\Engine\Plugins\Modkit\Suzie\Tools\sweep\run_gates.ps1 -Tag mycheck -Project D:\DBDModkit\Work\DBDMount\DBDMount.uproject
```

Expected: Blueprint sweep CLEAN >= 529, DIRTY <= 2, CRASH 0; material sweep PASS 200 of 200; results in `<project>\Saved\SuzieSweeps`.

## 9. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Editor starts as plain UE, no `LogModkit` lines; `LogSuzie: Suzie idle: no profile selected` | No profile selected. `ModkitData\ModkitLocal.ini` is missing or has no `Profile=` (open the project and fill in the setup window, section 5), or `Profile=` is not a profile folder: it must be the folder that contains `profile.json` and `engine.ini` (for example `.../Profiles/DBD`), not the file `profile.json`. `-DisableModkit` also causes it. |
| 0 containers mounted, `failed to fill whole buffer` or index errors | Wrong `GameRoot`, wrong or missing key, or a game version other than the one of your jmap and of this build. Stock tools cannot read the containers; only this engine's cipher from `engine.ini` can. |
| `LogModkit ... key file` error | `KeyFile=` path is wrong or the file does not hold `0x` + 64 hex digits. The value is never logged. |
| Materials render as the default/grey material, `Incomplete material` | `r.AllowStaticLighting=False` is missing in `Config/DefaultEngine.ini`, or the editor runs with SM6/Vulkan: start with `-d3d12 -sm5`. `missing TShadowDepthPS...` on `M_CAMPER`, `M_CAMPER_CUST`, `M_Slasher` or `M_Slasher_Burn` is expected (permutations the game did not cook). |
| `Incomplete material X, missing (TBasePassPSFNoLightMapPolicySkylight)` or `FDeferredDecalEmissivePS`; lit opaque or decal materials draw as the default material | The renderer settings of the project template are missing in `Config/DefaultEngine.ini`: `r.SupportStationarySkylight=False`, `r.SupportLowQualityLightmaps=False`, `r.DBuffer=False` next to `r.AllowStaticLighting=False`. |
| `tolerating layout hash mismatch for FMaterialShaderMapContent / FMeshMaterialShaderMap` | Expected; the types are listed under `[ShaderLayout] TolerateMismatch`. |
| Many `Invalid GameplayTag` warnings | The jmap is missing or has no tag settings object, or the tags were written during this start and the redirects apply from the next start (tags.md). |
| Crashes after a failed experiment, corrupt shader cache | Use the project DDC `<project>\DDC` (the engine sets it when the modkit profile is active), delete that folder and restart. Never share one DDC between the stock editor and this one. |
| `Plugin 'Suzie' ... duplicate` | The plugins are also copied into `<project>\Plugins` of an installed-engine project; remove them (they are engine plugins there). |
| `Missing or incompatible game module` | The project has a `Source` folder or `Modules` entry; the template is content only. Remove them or build the module with Visual Studio. |
| `Project was made with a different version` dialog, double click opens the wrong engine | The engine is not registered or registered under another id; run `Register Engine.bat`. |
| The `Modkit project setup` window opens | Expected while a path is missing or invalid: fill in its rows (section 5) and choose `Save and restart`. If it opens again after saving, the `Modkit project setup:` Warning in the log names the row that is still invalid. |
| 15 to 30 minutes of nothing on first start | Normal: SM5 global shader compile with an empty DDC. Watch the `ShaderCompileWorker` processes. |
| Out of memory during shader compile | Close other programs; 16 GB RAM works. |
| Crash or `bIsOptional && ElementSize` assertion after a game update | The game version differs from the version of the jmap (or of this build): unversioned data desynchronizes. Use the jmap of the game version you run and restart (native-type-generation.md). |
| `SchemaIt != SchemaEnd` assertion | A game class or struct has reflected members that the schema recipes do not account for (schema-shadow-properties.md). |
| DataTable assertion in the unversioned loader for a row struct with a natively serialized struct (`BarkRuleDB`) | The `DBDModkitGame` plugin did not load: check it is enabled in the `.uproject` and `LogSuzie` names the extension module. |
| `Suzie idle: profile 'dbd' needs the game's jmap, ...` | `Jmap=` under `[Local]` in `<project>/ModkitData/ModkitLocal.ini` is missing or names a file that does not exist; put the jmap in `ModkitData` and open the project to fill the `Jmap` row, or pass `-SuzieJmap=<file>`. |
| Editor start takes about 9 seconds longer than a stock start | Normal: Suzie parses the jmap (180 MB for 10.2.2) at every start. |
| The `GameRoot` row is invalid | The folder does not contain `DeadByDaylight\Content\Paks\global.utoc`. Choose the install folder of the game (type the path or use `...`). |
| A row reports two files | `ModkitData` holds more than one `*.txt`, `*.jmap` or `*.usmap`; keep one of each. |
| The game, the engine or a data file moved | Open the project: the window opens for the invalid rows; choose the new paths. After moving the engine, run `Register Engine.bat` in the new engine folder. |

## 10. Another game profile or game version

* Everything game specific is **data in a profile folder** (`Suzie\Profiles\<Game>`: `engine.ini` for the engine, `profile.json` + `schema/`, `load/`, `tags/` for Suzie, optional `Plugin/<GamePlugin>` with the only game code). The setup window selects the profile when several exist; `Profile=` in `ModkitData\ModkitLocal.ini` (or `-ModkitProfile=`) names it. The profile's `project.json` names the data files and the game install probe.
* This installed build is the `game/dbd` branch: besides the generic hooks it contains a `FShaderMapContent` +8 byte field. The DBD 10.2.2 uniform buffer layouts are data in the profile (`uniform_layouts.txt`). A second game needs its own `uniform_layouts.txt` when its uniform buffer layouts differ, and its own engine branch and installed build when engine struct sizes differ.
* New game: create `Profiles/<G2>` from the DBD profile (copy `engine.ini`, `profile.json`, `project.json`, `load/skip.json`, `tags/tags.json`), obtain the game's jmap, put it in `ModkitData`, open the project and fill in the setup window, run `Suzie.VerifyNativeTypes`, run the sweep harness.
* New DBD version: replace the jmap in `ModkitData` with the one of the new version and restart; types, schema recipes and gameplay tags follow from it. If the file name changes, the ini still names the old file: edit the `Jmap=` line of `ModkitLocal.ini`, or delete the ini and fill in the setup window again. The asset registry follows from the game install. If the game changed its uniform buffer layouts, the profile needs a new `uniform_layouts.txt` (a developer step from a minidump of the game).

## 11. The jmap (you provide it)

* The `.jmap` is a JSON reflection dump of the **running** game process (trumank/jmap `jmap_dumper` format). It must be the jmap of **your game version**; jmaps of a game version circulate in the modding community like the AES key. This package contains none.
* Put it in `ModkitData` and open the project (section 5), or pass `-SuzieJmap=<file>`. The editor needs it at every start: it generates the game's native types, the schema recipes and the gameplay tags from it. Without it nothing is generated.
* The AES key goes in its own file (section 4); the jmap is a separate file and holds no key.
* **Producing a jmap requires running the game** (or a memory dump of it), with whatever anti-cheat and terms-of-service consequences that has. This package never does it; it is entirely your decision and responsibility.

## 12. Licensing

This folder contains a **modified Unreal Engine 5.7.4** built from Epic's source. Unreal Engine is subject to the Unreal Engine End User License Agreement; redistributing built engine binaries or source is permitted only under that EULA (source access is granted to registered licensees and sharing is limited to other licensees). Do not share this package publicly.
`Suzie` is a fork of trumank/Suzie (MIT, see its `LICENSE`).
**No game content, assets or encryption keys are included.** The profile's test references (`data/golden`, `sweeps/`) list names of the game's types and assets. The jmap and the key file are yours. Dead by Daylight and its assets belong to Behaviour Interactive.

Known limitations of this build: `docs/limitations.md` of the DBD-UEEditor project.
