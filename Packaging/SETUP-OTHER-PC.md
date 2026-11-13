# DBD modkit editor (UE 5.7.4 installed build): setup on another PC

Package layout (the folder you were given, called `<PKG>` below):

```
<PKG>\Windows\                 the installed engine (UnrealEditor.exe is in Windows\Engine\Binaries\Win64)
<PKG>\DBDMount-Template\       ready-to-use content-only project (copy it, do not edit it in place)
<PKG>\SETUP-OTHER-PC.md        this file
```

What this is: a modified Unreal Engine 5.7.4 editor that can mount Dead by Daylight's cooked IoStore/pak containers, load the game's shared shader library
and load the game's cooked materials, meshes, Blueprints, AnimBPs and widgets (the game's native classes are generated in memory at editor start).
The two plugins that do this, `Suzie` and `DBDModkitGame`, are **engine plugins of this build** (`Windows\Engine\Plugins\Modkit`), already compiled.
You do not need Visual Studio, a C++ toolchain or the engine source.

## 0. Checklist

1. [ ] Windows 10/11 64 bit, 16 GB RAM or more, a GPU with working D3D12 Shader Model 5, about 220 GB free for the engine copy plus 30+ GB for the shader cache.
2. [ ] Copy `<PKG>` to a local SSD with a **short path** (for example `D:\DBDModkit`). Not into OneDrive/Dropbox folders.
3. [ ] Install the Visual C++ runtime once: run `<PKG>\Windows\Engine\Extras\Redist\en-us\vc_redist.x64.exe` (skip if already installed).
4. [ ] Have **your own** Dead by Daylight install, **version 10.2.2** (see 3). Never copy the game to somebody else.
5. [ ] Have the game's AES key in a text file you create yourself (one line, `0x` + 64 hex digits). Keep it outside the package. See 4.
6. [ ] Copy `<PKG>\DBDMount-Template` to your work folder (for example `D:\DBDModkit\Work\DBDMount`).
7. [ ] Extract `AssetRegistry.bin` from the game's containers into the project root (section 5, needs the .NET 10 SDK and a CUE4Parse checkout; or copy one from a colleague who has the same game version, it holds no code).
8. [ ] Optional but recommended: generate the gameplay tags (section 6, needs Python 3 and the game's `.jmap`).
9. [ ] Copy `ModkitLocal.ini.example` to `ModkitLocal.ini` and fill the paths (section 7).
10. [ ] Register the engine (`Register Engine.cmd`, section 2) or just start with `Start Editor.bat`.
11. [ ] First start: wait 15-30 minutes (SM5 global shader compile, no prebuilt cache is shipped). Do not close the editor.
12. [ ] Check the expected log lines (section 9).

## 1. System requirements

| | |
|---|---|
| OS | Windows 10 (64 bit) or Windows 11 |
| Compiler / Visual Studio | **Not needed** for the template project: it has no C++ module, and the plugins are precompiled inside the engine. You only need Visual Studio 2022 (Build Tools, "Desktop development with C++" + a Windows 11 SDK) if you later add your own C++ module to a project or rebuild the plugins (`Source` of both plugins is in the package). |
| .NET / Python | Only for the optional helper tools: .NET 10 SDK (`ExtractAssetRegistry`), Python 3 (tags, sweep scripts). The editor itself needs neither. |
| GPU | D3D12 capable GPU with Shader Model 5 (any GTX 900 / RX 400 or newer; recent driver). The editor must run with `-d3d12 -sm5`; the game's cooked shaders exist only as `PCD3D_SM5`. Vulkan and SM6 are not usable for the cooked shaders. |
| RAM | 16 GB works (this is what the development PC has); 32 GB is more comfortable (shader compile workers). |
| Disk | The installed engine as built here is about **207 GB** (it includes both editor configurations Development and DebugGame, client/server/game targets in Development and Shipping, all debug symbols (about 57 GB of .pdb), engine docs and templates, and **no** prebuilt DDC). Plus the shader cache of the project (`DBDMount\DDC`, grows to a few GB after the first start). The game itself is about 60-70 GB. |
| Game | Dead by Daylight **10.2.2** (same build the profile was baked from). Another version needs a new jmap and a re-bake (section 11) and may show layout differences. |

## 2. Install / register the engine

There is no installer: the folder **is** the engine.

1. Copy `<PKG>` somewhere short, for example `D:\DBDModkit\` so that `D:\DBDModkit\Windows\Engine\Binaries\Win64\UnrealEditor.exe` exists.
2. Run `vc_redist.x64.exe` (see the checklist) once.
3. Registration (optional, needed only for double-clicking `DBDMount.uproject` or "Switch Unreal Engine version"):
   open a command prompt in your project folder and run
   `"Register Engine.cmd"` (uses `..\Windows` relative to the template, which only fits inside the package) or, explicitly:
   `"Register Engine.cmd" D:\DBDModkit\Windows`.
   It writes `HKCU\Software\Epic Games\Unreal Engine\Builds\DBDModkit-5.7.4 = <engine folder>` for the current user only; no admin rights.
   The template's `.uproject` has `"EngineAssociation": "DBDModkit-5.7.4"`.
4. Without registration use `Start Editor.bat` in the project: it starts `UnrealEditor.exe` directly. It looks for the engine in `..\Windows` (relative to the project) or in the environment variable `MODKIT_ENGINE` (the folder that contains `Engine`).
   Example: `set MODKIT_ENGINE=D:\DBDModkit\Windows` then `Start Editor.bat`.

## 3. The game files (you provide them)

* Install Dead by Daylight yourself (Steam). **Version 10.2.2** is required for the shipped profile (the profile's baked types and the shader layouts are from 10.2.2).
  Steam normally auto-updates; if the game is newer, you need that exact build (e.g. a Steam depot/manifest of 10.2.2 that you own) or a re-bake for the new version (section 11).
* `GameRoot` in `ModkitLocal.ini` is the folder that contains `DeadByDaylight\Content\Paks` (for example `C:/Program Files (x86)/Steam/steamapps/common/Dead by Daylight`).
  Expected content of `Paks`: 614 containers (307 `.utoc/.ucas` IoStore + 307 `.pak`), `global.utoc`, `pakchunk0-Windows.utoc`, ...
* The editor only **reads** the game; nothing is copied or modified. **Never start the game while the editor runs against the same files, and do not run the game just for this tool.**
  (We never ran the game during development and never touched EasyAntiCheat.)

## 4. The AES key (you provide it, never shipped)

* The package contains **no key and no game content** (a scan of the template, the profile and the plugin text files for 0x+64-hex strings found none; the engine reads the key from the file you name and never logs the value).
* Create a text file, for example `D:\DBDModkit\secrets\dbd-aes.txt`, containing one line: the game's 32-byte AES-256 key as `0x` + 64 hex digits. Obtain it yourself from the community modding resources for the game (we do not distribute it).
* Point to it with `KeyFile=` in `ModkitLocal.ini` (or `-ModkitKeyFile=<file>` on the command line, or the environment variable `MODKIT_AES_KEY_FILE`).
* Protect the file (do not put it in the package, do not commit it, do not paste it into chats or logs).
* A wrong or missing key shows up as containers that do not mount (section 10).

## 5. AssetRegistry.bin (premade registry of the game)

The profile uses the game's own premade asset registry (96,267 assets); it must be in the **project root** as `AssetRegistry.bin`.
It is read from the game's first container (`DeadByDaylight/AssetRegistry.bin` in `pakchunk0`), so it is game data: extract it from **your** install.

Tool shipped in the package: `Windows\Engine\Plugins\Modkit\Suzie\Tools\ExtractAssetRegistry` (C#, uses CUE4Parse).

```
git clone https://github.com/FabianFG/CUE4Parse.git D:\DBDModkit\CUE4Parse          (a recent checkout; it was verified with commit 613a673, net10.0)
cd D:\DBDModkit\Windows\Engine\Plugins\Modkit\Suzie\Tools\ExtractAssetRegistry
dotnet build -c Release -o D:\DBDModkit\tools\ear -p:CUE4ParseDir=D:\DBDModkit\CUE4Parse
dotnet D:\DBDModkit\tools\ear\ExtractAssetRegistry.dll "<GameRoot>\DeadByDaylight\Content\Paks" "<KeyFile>" "<project>\AssetRegistry.bin"
```

(It prints `mounted 614 groups ...` and `wrote ...`; the output on the development PC is byte identical to the one used in all tests.)
If you do not want to build anything: the file contains no code and no key; a colleague with the **same game version** can give you theirs.

## 6. Gameplay tags (optional, removes "Invalid GameplayTag" warnings)

Needs the game's `.jmap` (reflection dump, see section 12) and Python 3:

```
python D:\DBDModkit\Windows\Engine\Plugins\Modkit\Suzie\Tools\suzie_tags.py --jmap D:\DBDModkit\game-data\DBD-10.2.2.jmap --project D:\DBDModkit\Work\DBDMount --tags-ini Config/Tags/DBDGameTags.ini
```

It writes `Config\Tags\DBDGameTags.ini` and `Config\DefaultGameplayTags.ini` (5,083 tags, 117 redirects from the game's settings). Expect `Suzie.TagInfo` to report about 6,330 tags with the jmap alone
(the development tree had about 50 more harvested ones; only a few warnings may remain). Skipping this step only produces gameplay tag warnings.

## 7. ModkitLocal.ini (the only machine specific file)

Copy `ModkitLocal.ini.example` to `ModkitLocal.ini` in the project root (next to `DBDMount.uproject`) and edit. Forward slashes. Complete example with placeholder paths:

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
| `Profile` | yes | folder with `engine.ini` (read by the engine: containers, cipher pipeline, shader library, layout rules) and `profile.json` (read by Suzie). It is `Profiles\DBD` inside the Suzie plugin of the installed engine. Selecting a profile switches the modkit on; without it the editor is stock UE 5.7.4. |
| `GameRoot` | yes | install root of the game; the profile probes `Paks`, `Content/Paks`, `DeadByDaylight/Content/Paks`. |
| `KeyFile` | yes | path of the AES key file (path only, never the key). |
| `EngineDir` | no | engine root for the helper/sweep scripts; otherwise derived from `EngineAssociation`/`MODKIT_ENGINE`. |
| `Jmap` | no | only for `suzie_tags.py` and re-baking. |
| `Usmap` | no | only for external tools (CUE4Parse); `Suzie.VerifyNativeTypes` uses the schema dump shipped in the profile (`data/cache/game_schemas.tsv`, override with `UsmapTsv=`). |

Project settings (already set in the template `Config\DefaultEngine.ini`, keep them if you create your own project):

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

`r.AllowStaticLighting=False` is **required**: the game cooked no static lighting permutations; otherwise materials count as incomplete and render with the default material.
The `.uproject` must enable both plugins: `"Plugins": [{"Name":"Suzie","Enabled":true},{"Name":"DBDModkitGame","Enabled":true}]` (already in the template).
Do **not** also copy Suzie or DBDModkitGame into the project's `Plugins` folder (duplicate plugin).

## 8. Launch

```
set UE-LocalDataCachePath=D:\DBDModkit\Work\DBDMount\DDC
D:\DBDModkit\Windows\Engine\Binaries\Win64\UnrealEditor.exe D:\DBDModkit\Work\DBDMount\DBDMount.uproject -log -d3d12 -sm5
```

or double-click/run `Start Editor.bat` in the project (it sets the isolated DDC and the switches).

**No DDC is shipped with this engine.** The first launch compiles the SM5 global shaders and the engine content shaders: **about 15-30 minutes** (this PC: about 15 minutes with an i5-10400F, longer on fewer cores), the editor window may show nothing until it is done.
Set `UE-LocalDataCachePath` (as above) to a folder on a fast disk; it is a per-project cache (use a separate one for experiments so a failed run cannot pollute it; the default shared cache works too but is not isolated). Later starts take about 1-2 minutes.
Other switches: `-DisableModkit` (stock behaviour), `-DisableSuzie`, `-ModkitProfile=<dir>` (instead of `Profile=`), `-ModkitKeyFile=<file>`, `-ModkitGameDir=<dir>`, `-NoPaks`.

## 9. Verify that it works

In `<project>\Saved\Logs\DBDMount.log` (or the `-log` window):

```
LogModkit: Display: Modkit profile 'dbd' (...Profiles/DBD) active, game Paks directory: ...
LogModkit: Display: Loaded AES key from '...' (value not logged).
LogPakFile: Display: Mounted IoStore container ... (307 times) and Mounted Pak file ... (307 times) + the global container
LogAssetRegistry: Premade AssetRegistry loaded from '.../AssetRegistry.bin'
LogInit: Display: Modkit: opened shader library 'DeadByDaylight': yes (total shaders in library: 164124, library enabled: 1)
LogInit: Display: Modkit: registered 238 game plugin content roots (238 .uplugin files found).
LogSuzie: GENERATE OK ... enums=1099(+21 existing) structs=2571 ... classes=7592 ... functions=14459 properties=59194 ... overrides=50/160/0
```

Count check: `findstr /c:"Mounted IoStore container" DBDMount.log | find /c /v ""` gives 307.
Inside the editor: open the Content Browser, enable "Show Engine/Plugin content" if needed, and load `/Game/...` assets; or run `Suzie.VerifyNativeTypes` in the console (expect `VERIFY RESULT: types=10163 ok=10004 mismatch=159`).

Regression gates (optional, about 10-20 minutes with warm DDC), the same harness that was used on the development tree:

```
powershell -File D:\DBDModkit\Windows\Engine\Plugins\Modkit\Suzie\Tools\sweep\run_gates.ps1 -Tag mycheck -Project D:\DBDModkit\Work\DBDMount\DBDMount.uproject
```
(golden dump/verify, Blueprint sweep: CLEAN >= 529, DIRTY <= 2, CRASH 0; material sweep: PASS 200 of 200; results in `<project>\Saved\SuzieSweeps`; Python 3 required.)
Results of this package on the build PC are in section 13.

## 10. Troubleshooting (failures we hit during development)

| Symptom | Cause / fix |
|---|---|
| Editor starts as plain UE, no `LogModkit` lines | no profile selected: `Profile=` missing in `ModkitLocal.ini` (must be in the project root next to the `.uproject`), wrong folder, or `-DisableModkit`. Also `LogSuzie: Suzie idle: no profile selected`. |
| 0 containers mounted, "failed to fill whole buffer"/index errors | wrong `GameRoot`, wrong/missing key, or a game version other than 10.2.2. Stock tools (retoc, stock UnrealPak) cannot read these containers: the directory index uses a custom cipher; only this engine's data-driven cipher (profile `engine.ini`) does. |
| `LogModkit ... key file` error | `KeyFile` path wrong or the file does not contain `0x` + 64 hex. The value is never logged. |
| Materials show the default/grey material, "Incomplete material" | `r.AllowStaticLighting=False` missing, or the editor ran with D3D11/SM6/Vulkan: start with `-d3d12 -sm5`. A few "missing TShadowDepthPS" lines are normal (permutations the game did not cook). |
| `tolerating layout hash mismatch for FMaterialShaderMapContent / FMeshMaterialShaderMap` | expected, harmless (profile `TolerateMismatch`). |
| Many `Invalid GameplayTag` warnings | tags not generated (section 6). |
| Corrupt shader cache, crashes right after a failed experiment | use an isolated DDC (`UE-LocalDataCachePath`), delete that folder and restart. Never share one DDC between the stock editor and this one. |
| `Plugin 'Suzie' ... duplicate` / plugin loads twice | you also copied the plugins into `<project>\Plugins`; remove them (they are engine plugins). |
| `Missing or incompatible game module` | the project got a `Source` folder or `Modules` entry; the template is content-only. Remove them or build the module (needs Visual Studio). |
| "Project was made with a different version" dialog / double click opens the wrong engine | engine not registered (section 2) or registered under another id; use `Start Editor.bat`. |
| 15-30 min of nothing on the first start | normal: shader compile of the global shader cache (no DDC shipped). Watch `ShaderCompileWorker` processes. |
| Out of memory during shader compile | close other programs; 16 GB works (the build PC has 16 GB). The editor uses all cores for shader workers by default; fewer cores only makes the first start longer. |
| Editor crash after a game update | game version differs from 10.2.2: unversioned data desyncs ("bIsOptional && ElementSize" assertions). Re-bake (section 11) or use 10.2.2. |
| Windows Defender / EAC dialogs | the editor never touches the running game; keep the game closed while using the editor. |
| `/Game/Data/Dlc/.../BarkRuleDB` style assertions | fixed in this build (native struct ops of the profile plugin); if you see them, the `DBDModkitGame` plugin did not load: check it is enabled in the `.uproject` and `LogSuzie` mentions the extension module. |

## 11. Another game profile / another game version (generic architecture)

* The engine is generic: everything game specific is **data in a profile folder** (`Suzie\Profiles\<Game>`: `engine.ini` for the engine, `profile.json` + `schema/`, `load/`, `tags/`, baked `data/bake/types.json` for Suzie, optional `Plugin/<GamePlugin>` with the only game code). Switch the profile with `Profile=` in `ModkitLocal.ini` (or `-ModkitProfile=`).
* **Caveat, important:** this installed build is the `game/dbd` branch: besides the generic hooks it contains the DBD 10.2.2 **uniform buffer layouts** and a `FShaderMapContent` +8 byte field (11 engine files, 58 lines). A second game generally needs its own engine branch `game/<g2>` with its own layouts (and therefore its own installed build). Only games whose shader layouts equal the engine's can reuse this build with a different profile.
* Steps for a new game: create `Profiles/<G2>` from the DBD profile as a template (copy `engine.ini`, empty `schema/engine_diff.json`, `load/skip.json`, `tags/tags.json`), produce the game's jmap (section 12), bake (`tools/dbd_native_baker.py`, see `Profiles/DBD/README.md` "Re-baking"), set `ModkitLocal.ini`, run `Suzie.VerifyNativeTypes`, turn the reported engine-class differences into recipes (data), run the sweep harness. Design notes: `NOTES\modkit-architecture.md` (sections 2.4, 4).
* New DBD version: new jmap, run `Profiles\DBD\tools\bake_all.cmd` (or `python -I tools/dbd_native_baker.py --editor-schemas data/editor_schemas_stock.tsv --out data/bake/types.json --cdo-out data/bake/cdo.json` with `SUZIE_JMAP` set), and expect to re-check the layouts if the shader parameter structs changed.

## 12. Where the jmap and usmap come from (not run by us)

* **What they are:** the `.jmap` is a JSON reflection dump (classes, structs, enums, properties, CDO values) of the **running** game process; the `.usmap` is the unversioned-property mapping used by CUE4Parse-style tools.
* **For the shipped profile you do not need either** to open the editor: the profile already contains the baked types for 10.2.2 (`data/bake/types.json`) and the usmap schema dump used by the verify command (`data/cache/game_schemas.tsv`). The jmap is only needed for gameplay tags (section 6) and for re-baking; the usmap only for external tools.
* **How they were obtained:** the 10.2.2 `DBD-10.2.2.jmap` and `.usmap` of the development PC were supplied to us; our notes do not record the exact dump command, and we did not produce them. The method the modkit guide describes is the `jmap_dumper` of trumank/jmap (injected into the running game; the Suzie fork consumes that format), with the usmap produced by the usual mapping dumpers from the same process.
* **FLAG: producing a jmap/usmap requires running the game** (or a memory dump of it), with whatever anti-cheat/Terms-of-Service consequences that has. We did not and will not do that step for you. It is entirely your decision and responsibility; do not attempt it with EasyAntiCheat active unless you understand the risk. If you cannot or do not want to, stay on game version 10.2.2 with the shipped baked profile (the editor works without any jmap/usmap).

## 13. Verified on the build PC

(Installed build tested from `N:\DBD-UEEditor-Installed` with a fresh project copy and an isolated DDC, game 10.2.2.)

* Containers mounted: 307 IoStore + 307 pak + the global container, premade registry, shader library `DeadByDaylight` 164,124 shaders, 238 plugin content roots.
* Suzie generated 1,099 (+21 existing) enums, 2,571 structs, **7,592 classes**, 14,459 functions; overrides 50 types / 160 shadow properties / 0 skipped; `VERIFY: types=10163 ok=10004 mismatch=159`.
* 531 Blueprint/AnimBP/Widget sweep: CLEAN 529, DIRTY 2 (`BP_ST_Basement01`, `BP_TL_St_2x2_Shrine_Hti`), CRASH 0. Material/MIC sweep: **PASS 200/200**.
* Material Editor opened on the cooked material `M_CAMPER_CUST` (`open_editor_for_assets` returned True); the editor then quit cleanly (exit code 0).
* First start with an empty DDC took about 15 minutes (to the end of the shader compile and library mount).

## 14. Known limitations

* Values of the roughly 160 game members that stock engine classes lack are read and discarded (not visible in the editor).
* Generated classes have script stubs only (no function bodies) and no CDO values beyond default subobjects; cooked Blueprint classes open in the generic class-defaults tab (no Widget Designer / graph editors).
* `BP_ST_Basement01` (default-material shader map) and `BP_TL_St_2x2_Shrine_Hti` (native DestructibleMesh payload) load with logged errors.
* Some materials log `Incomplete material X, missing (TShadowDepthPS...)`: the editor expects permutations the game did not cook; the base pass still draws.
* `tolerating layout hash mismatch` (FMaterialShaderMapContent, FMeshMaterialShaderMap): the extra 8-byte field of the game's FShaderMapContent is a placeholder `uint64`.
* BHVR-only shader types (custom vertex/pixel shaders) load as null slots and their passes are not rendered. D3D12 only (the D3D11 RHI has no uniform-buffer alias).
* The material instance editor shows cooked parameters under "Global Scalar/Vector/Texture Parameters" (no group names in cooked data).
* Two Chaos cloth structs that append data are generated as plain structs (the game's registry has no Chaos cloth asset). `FTableRowBase` casts in the CSV import factory/composite tables are not guarded.
* The package has no prebuilt DDC, no `Debug` (full debug CRT) game configuration, no `Test` configuration; the Windows debugging tools (`pdbcopy`) were not available on the build PC, so symbols are shipped unstripped (large `.pdb` files; they can be deleted if you do not debug).
* The installed engine can not rebuild engine modules from source; Suzie/DBDModkitGame sources are included only for reference and for plugin rebuilds with Visual Studio.

## 15. Licensing note

This folder contains a **modified Unreal Engine 5.7.4** (source-level hooks and per-game layout data) built from Epic's source. Unreal Engine is subject to the Unreal Engine End User License Agreement; **redistributing built engine binaries or source is only permitted under that EULA** (in particular, access to the source is granted to registered licensees and sharing is limited to other licensees, usually through a GitHub fork of the Epic repository). Check the EULA before you share this package; sharing it publicly is not permitted by us.
`Suzie` is a fork of trumank/Suzie (MIT, see its `LICENSE`); `CUE4Parse` has its own license.
**No game content, no game assets and no encryption keys are included.** The package does contain reflection data derived from the game's executable metadata (class/struct/property names in `data/bake/types.json`), which you should treat as game-derived material for your own use. Dead by Daylight and its assets belong to Behaviour Interactive; use your own game install and respect its terms.
