# Profile format, switches and configuration

A profile is a directory `Profiles\<Game>\` of the modkit repository (in an installed build: `Engine\Plugins\Modkit\Suzie\Profiles\<Game>\`). `ModkitData\ModkitLocal.ini [Local] Profile=` names this directory (the folder, not a file inside it).

| File | Read by | Purpose |
|---|---|---|
| `engine.ini` | engine (`Misc/ModkitCore.cpp`) before any plugin loads | containers, cipher pipeline, shader library, layout tolerance, content roots |
| `vanilla_containers.txt` | engine (`Misc/ModkitCore.cpp`), named by `[Containers] VanillaList` | the containers of the unmodified game; others in the Paks folder mount only when the project enables them ([asset-loader.md](asset-loader.md#containers)) |
| `uniform_layouts.txt` | engine (`RenderCore/Private/UniformBufferTranslationLoader.cpp`) before the RHI resources are created | game uniform buffer layouts that differ from the editor's; optional; format in [cooked-materials-shaders.md](cooked-materials-shaders.md) |
| `profile.json` | Suzie | entry point: names the data files below (relative paths resolve against the profile directory) |
| `project.json` | the editor's setup window (`Suzie\Source\Suzie\Private\Setup\SzProjectSetup.cpp`) | the data files a project folder holds (`data_files`: `key`, `extension`, `required`, `description`) and the game install probe (`game`: `name`, `probe`) |
| `packaging.json` | `publish-engine.ps1` | release names, engine branch, template, forbidden files, smoke test log checks |
| `schema/aliases.json` | Suzie | `types`: game type path to editor type path; `by_leaf_fallback` (opt-in leaf name match) |
| `schema/overrides.json` | Suzie | generation policy: abstract rules, class/struct/enum flags, `structs.row_struct` (`keep_super_guarded` or `drop_super`) |
| `load/skip.json` | Suzie | `skip_export_classes` (exports skipped on load, `include_derived`) and `post_serialize` (handler name per class, provided by the extension) |
| `load/native_ops.json` | Suzie | structs whose C++ struct ops come from the extension |
| `tags/tags.json` | Suzie, `Suzie.TagInfo` | `tags_ini` (project relative path of the written tag list), `probe_tag` ([tags.md](tags.md)) |
| `sweeps/` | sweep harness | asset lists; local, not tracked by git ([sweeps-and-verification.md](sweeps-and-verification.md)) |
| `data/golden/golden.txt.gz` | `golden_diff.py` | golden dump, output of `Suzie.DumpAll`; local file, not tracked by git ([sweeps-and-verification.md](sweeps-and-verification.md)) |
| `README.md` | n/a | profile overview |
| `Plugin/<GameModule>` | UE | extension plugin; the module named by `extension_module` |

Types, schema recipes and gameplay tags are not stored in the profile: Suzie derives them from the game's jmap at every start ([native-type-generation.md](native-type-generation.md)).


## profile.json keys

`format` (integer, `1`; not read by Suzie or the engine), `id`, `description`, `aliases`, `overrides`, `skip`, `tags`, `native_ops`, `extension_module` (game plugin module loaded by Suzie before generation), `conflicting_plugins` (list of `{plugin, disable_switch}`: when such a plugin is enabled and its switch is absent, Suzie idles).


## engine.ini

Arrays are repeated plain keys (no `+`).

```ini
[Profile]
Id=dbd
RequiresHookApi=1
[Containers]
ProbeFile=global.utoc            ; files that identify the Paks directory
PaksSubdir=Content/Paks          ; candidate Paks directories under GameRoot (repeat)
GlobalToc=global.utoc
LookLooseFirst=true
ImplyUsePaks=true
VanillaList=vanilla_containers.txt   ; optional; profile-relative file of vanilla container names
IoStoreDirectoryIndex=Xor:TocHeader:104:36;Aes
PakIndex=Aes;Xor:FooterCustom
PakFooterVariant=Guid16;Encrypted1;Magic4;Version4;IndexOffset8;IndexSize8;IndexHash20;Custom28;U32;CompressionNames5x32
[ShaderLibrary]
Name=DeadByDaylight
SkipCookedGlobalShaderCache=true
[ShaderLayout]
AliasUniformBuffers=true
TolerateMismatch=FMaterialShaderMapContent   ; repeat per type
[AssetEditors]
GenericEditorClass=/Script/Niagara.NiagaraSystem   ; repeat per class
[ContentMounts]
PluginScanRoot=../../../DeadByDaylight/Plugins
GameContentDir=../../../DeadByDaylight/Content   ; engine-relative folder of the game's /Game content in its containers
[AssetRegistry]
UsePremade=true
PakPath=../../../DeadByDaylight/AssetRegistry.bin   ; repeatable
```

The DBD profile's `[ShaderLayout] TolerateMismatch` entries are `FMaterialShaderMapContent`, `FMeshMaterialShaderMap`, `FGlobalShaderMapContent`, `FShaderMapContent` and `FNiagaraShaderMapContent`. The Niagara entry lets cooked Niagara GPU script shader maps load; whether GPU emitters render correctly is not verified.

`[AssetEditors] GenericEditorClass=<class path>` (repeatable) lists classes whose cooked assets open in the generic property editor (read-only Details) instead of their own asset editor, including subclasses. Uncooked assets of those classes open their normal editor. Each opened cooked asset logs `Opening cooked asset '<path>' with the generic property editor (profile [AssetEditors]).` The DBD profile lists `/Script/Niagara.NiagaraSystem` and `/Script/Niagara.NiagaraEmitter`: cooked Niagara assets have no script graphs, so the Niagara editor cannot open them.

Cipher step vocabulary: `Aes`, `Xor:TocHeader:<offset>:<len>` (IoStore only, applied before `Aes`), `Xor:FooterCustom` (pak only). An unknown step makes the profile inactive with an error.


## ModkitData\ModkitLocal.ini (machine local, gitignored)

The engine (`Misc/ModkitCore.cpp`), Suzie and the sweep harness read `<Project>\ModkitData\ModkitLocal.ini`. The setup window writes it (UTF-8, forward slashes); other keys and comments already in the file are kept (for example `SuzieProfile=` or comment lines).

```ini
[Local]
Profile=<absolute path of the profile FOLDER, e.g. .../Suzie/Profiles/DBD; the folder that contains profile.json and engine.ini>
SuzieProfile=<optional, Suzie only: profile name or folder, used when -SuzieProfile= is absent>
EngineDir=<optional: engine root, read by the sweep harness>
GameRoot=<game install root>
KeyFile=<path of the AES key file>
Jmap=<required: the game's jmap file>
```

`Jmap=` is read by Suzie at every editor start (`-SuzieJmap=<file>` overrides it). Without a readable jmap Suzie logs `Suzie idle: profile '<id>' needs the game's jmap, ...` and generates nothing.

This file is the only place that holds absolute paths. Only the path of the key file is stored, never the key.

`ModkitData` also holds `AssetFilter.txt` (package filter read by the engine) and `AssetLoader.json` (state of the Asset Loader window) when the Asset Loader was used: [asset-loader.md](asset-loader.md).


## Project setup (the setup window)

The editor opens the `Modkit project setup` window before the profile starts when a path is missing or invalid (an interactive editor only). The profile's `project.json` names the game and the data files that the window shows. Setup procedure for users: [setup-other-machine.md](setup-other-machine.md) section 5.

`project.json` keys: `engine_id` (the engine id of the template's `.uproject`, informational), `data_files` (list of `key` = ini key, `extension`, `required`, `description` = row tooltip), `game` (`description` = tooltip of the game folder row, `probe` = path below the game root that must exist).

The window resolves its rows (`SzProjectSetup::Resolve`):

- Profile: the `[Local] Profile=` folder when it holds `profile.json`, `engine.ini` and `project.json`; otherwise the only such folder under the Suzie plugin's `Profiles` folder. With several and none set, the window shows a profile row.
- Game folder (`GameRoot`): valid when `<GameRoot>\<probe>` exists.
- Data files: the ini value when that file exists; otherwise the one file in `ModkitData` with the extension. Two such files leave the row empty and invalid. A required row is valid when its file exists; an optional row may be empty.
- KeyFile: invalid when the engine read this file at startup and did not accept its key.

`Save and restart` writes the ini (`Profile=`, `GameRoot=` and the data keys; an empty optional key is removed; other lines are kept) and restarts the editor. The console command `Suzie.ProjectSetup` logs the same rows. With `GameRoot=<dir>` and data keys (`KeyFile=<file>`, `Jmap=<file>`) it writes the ini when every row is valid and writes nothing otherwise.

For every project it opens, the engine sets `UE-LocalDataCachePath` to `<Project>\DDC`, unless the variable is already set. Extra editor arguments go on an `UnrealEditor.exe <uproject> ...` command line.

`Register Engine.bat` sits in the root of the released engine folder and registers that folder under `engine_id` for the current user.


## Command line switches

| Switch | Effect |
|---|---|
| `-DisableModkit` | stock engine behaviour |
| `-ModkitProfile=<dir>` | profile folder (overrides `Profile=`) |
| `-ModkitGameDir=<dir>` | game root (overrides `GameRoot=`) |
| `-ModkitKeyFile=<file>` | key file path; also env `MODKIT_AES_KEY_FILE`, `[Local] KeyFile=`, `<Project>/ModkitAesKey.txt` |
| `-ModkitShaderLibraryName=<name>` | overrides `[ShaderLibrary] Name` |
| `-ModkitNoGlobalToc`, `-ModkitNoLookLooseFirst`, `-ModkitNoPluginContent` | disable that mount behaviour |
| `-ModkitStrictLayoutHash`, `-ModkitTolerateAllLayoutMismatch` | disable / widen the layout hash tolerance |
| `-ModkitNoUniformBufferAlias` | disable the uniform buffer alias |
| `-ModkitUseCookedGlobalShaders` | use the game's `GlobalShaderCache` |
| `-ModkitAssetFilter=<file>` | package filter file (default `<Project>/ModkitData/AssetFilter.txt`; [asset-loader.md](asset-loader.md)) |
| `-ModkitAllAssets` | ignore the package filter |
| `-ModkitAllContainers` | mount every container in the game's Paks folder, also those not in `[Containers] VanillaList` |
| `-DisableCookedShaderLibrary`, `-DisablePremadeAssetRegistry`, `-NoPaks` | disable shader library, premade registry, pak mounting |
| `-DisableSuzie` | Suzie does nothing |
| `-SuzieProfile=<name\|dir>` | Suzie profile (bare name = `<plugin>/Profiles/<name>`) |
| `-SuzieJmap=<file>` | the game's jmap (overrides `[Local] Jmap=`) |
| `-SuzieGenerate` | generate even when a conflicting plugin is enabled (error); without a profile, or with a profile but no jmap, runs the upstream jmap route reading `Content/DynamicClasses/*.jmap` |
| `-SuzieUpstreamJmap` | with `-SuzieGenerate`, use the upstream jmap route even when a jmap is configured; without `-SuzieGenerate` Suzie idles |
| `-SuzieNoCdoValues` | generated classes keep the constructor's default values: the jmap property values of class default objects and their default subobjects are not applied ([native-type-generation.md](native-type-generation.md)) |
| `-SuzieDumpDerived=<dir>` | writes the derived records as `types.json` and `engine_diff.json` into that directory (inspection) |

CVar `r.CookedShaders.GuardCookedMaterials`: -1 automatic (on when a shader library is configured), 0 off, 1 on.


## Console commands (Suzie)

`Suzie.GenerateNativeTypes` (no argument), `Suzie.VerifyNativeTypes` (no argument; compares each generated type's live property list, sizes and offsets with the jmap), `Suzie.DumpClass <class path>`, `Suzie.DumpAll <file>` (canonical golden dump), `Suzie.TagInfo [tag...|refresh]`. `Suzie.TagInfo refresh` runs `EditorRefreshGameplayTagTree` and prints the tag count; it probes no tags.

Asset Loader: `Suzie.AssetLoader.Open` (the window), `Suzie.AssetLoader.Closure <long package name>` (dependency closure), `Suzie.AssetFilter [<package>...]` (filter state per package); [asset-loader.md](asset-loader.md).


## Project requirements

`Config/DefaultEngine.ini` must contain:

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
r.Shaders.RemoveUnusedInterpolators=1
r.SupportStationarySkylight=False
r.SupportLowQualityLightmaps=False
r.DBuffer=False
```

The four `r.` settings are required: the game cooked no permutations for static lighting, stationary skylight, low quality lightmaps or DBuffer. Without them, materials count as incomplete ([cooked-materials-shaders.md](cooked-materials-shaders.md)). `r.Shaders.RemoveUnusedInterpolators=1` matches how the game's shaders are compiled: pipeline shaders drop the vertex outputs the next stage does not read, so cooked pipeline shaders have the game's bytecode ([cooked-materials-shaders.md](cooked-materials-shaders.md#custom-pass-shader-types)). The project template `Config\DefaultEngine.ini` holds them.

`Config/DefaultGame.ini` must contain:

```ini
[/Script/UnrealEd.ProjectPackagingSettings]
bShareMaterialShaderCode=False
```

The packaging settings are read from the Game ini; the engine default (`BaseGame.ini`) is `True`. With `False` a cook writes no project shader library and every cooked material carries its shader code inline ([cooking.md](cooking.md)). `tools\setup-dev-project.ps1` copies the template `Config` only into a project without one, so an existing project needs the file copied by hand. The editor runs with `-d3d12 -sm5` (or `-d3d11`); the cooked shaders exist only as `PCD3D_SM5`. The `.uproject` enables the plugins `Suzie` and `DBDModkitGame`.

The template's `Config\DefaultEditorPerProjectUserSettings.ini` turns on the four Blueprint exposure settings (`bExposeAllProperties`, `bExposeAllFunctions`, `bExposeAllStructs`, `bExposeAllClasses` in `[/Script/BlueprintGraph.BlueprintEditorSettings]`); each user can change them in Editor Preferences > Blueprint Editor > Exposure.
