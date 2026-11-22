# Architecture

The modkit opens cooked Dead by Daylight (DBD) assets in the Unreal Engine 5.7.4 editor. Five layers; each game specific item sits in the lowest layer that can hold it.

| Layer | Where | Holds |
|---|---|---|
| Engine, generic | `UnrealEngine-5.7.4-fork`, branch `modkit-core` | hooks with no game name: profile/config loader and data driven container cipher (`Core/Public/Misc/ModkitCore.h`), cooked material guards, loader tolerances, schema override / skip / post-serialize / generated-type registries (`CoreUObject/Public/UObject/UnversionedSchemaOverride.h`), uniform buffer layout hash alias, uniform buffer layout translation (`RHI/Public/RHIUniformBufferTranslation.h`), `UTexture` default bodies, DataTable guard |
| Engine, game | same repo, branch `game/dbd` (= `modkit-core` + game commits) | the extra 8 byte field of `FShaderMapContent` (1 file, 3 lines). No BHVR member sits in an engine header. |
| Suzie plugin | `Suzie-fork` (junction `DBDMount\Plugins\Suzie`) | game agnostic generator of native classes, structs, enums and delegates derived from the game's jmap at editor start, schema recipes, gameplay tags, profile loader, console commands, verification |
| Profile | `Profiles\DBD` (modkit repository) | data: `engine.ini`, `profile.json`, `uniform_layouts.txt` (game uniform buffer layouts), schema policy, load lists, tag settings, sweep lists, golden dump |
| Game plugin | `Profiles\DBD\Plugin\DBDModkitGame` (junction `DBDMount\Plugins\DBDModkitGame`) | the only DBD specific code: struct ops, post-serialize handler, bark node template deserializer |

Placement rules: data beats plugin code beats engine branch. A new engine header beats an edited public header (a public Engine/Core/RenderCore header edit costs about 2 h of rebuild, a cpp edit 1 to 3 min). Game specific engine C++ goes to `game/<game>`; generic engine C++ goes to `modkit-core`.

## Activation

- `Modkit::IsEnabled()`: editor build and no `-DisableModkit`.
- `Modkit::IsActive()`: enabled and a profile resolved. Every modkit code path in the engine is guarded by it; without a profile the editor is stock UE 5.7.4 and the modkit logs nothing.
- Profile lookup: `-ModkitProfile=<dir>`, else `<ProjectDir>/ModkitData/ModkitLocal.ini` `[Local] Profile=<dir>`. The directory holds `engine.ini` (engine) and `profile.json` (Suzie).
- `engine.ini [Profile] RequiresHookApi=<n>`: the engine stays inactive (and logs an error) when its hook API level is lower.
- Suzie generates types at editor start when a profile with `profile.json` is selected, no plugin listed in `conflicting_plugins` is enabled and the game's jmap is configured (`-SuzieJmap=<file>`, else `[Local] Jmap=`). Without a profile Suzie logs `Suzie idle: no profile selected`; without a readable jmap it logs `Suzie idle: profile '<id>' needs the game's jmap, ...` and generates nothing.

## Runtime sequence

1. The engine reads the profile and the package filter `ModkitData/AssetFilter.txt` (`ModkitCore.cpp`, [asset-loader.md](asset-loader.md)), adds the Paks directory, implies `-UsePaks`, binds the key delegate and mounts `global.utoc` ([container-cipher-mounting.md](container-cipher-mounting.md)). For every project it opens, unless `UE-LocalDataCachePath` is already set, the engine sets it to `<Project>/DDC` (`UseProjectLocalDataCache()`, `ModkitCore.cpp`), so the project keeps its own DDC.
2. Before the RHI resources are created (`FRenderResource::InitPreRHIResources`), the profile's `uniform_layouts.txt` is read and each game layout is registered as a translation of the editor layout whose hash it names ([cooked-materials-shaders.md](cooked-materials-shaders.md)).
3. The premade `AssetRegistry.bin` is loaded from the mounted pak (profile `[AssetRegistry] PakPath`; a file in the project root takes precedence) and packages hidden by the filter are removed from it; `/<Plugin>/` content roots are mounted for every `.uplugin` found under the profile's `PluginScanRoot` (after engine init in the editor, before the commandlet runs in commandlets). Each maps to `<Project>/Plugins/<plugin folder relative to the scan root>/Content/`, so assets saved under a game plugin root are project files; the folder exists only once an asset is saved there (missing root folders are not created or watched by the asset registry). The Suzie editor module shows these roots under `All/Plugins` in the Content Browser (`SetGenerateVirtualPathPrefixDelegate`; other paths keep the stock virtual path).
4. The shader library named in the profile is opened after `GEngine->Init` ([cooked-materials-shaders.md](cooked-materials-shaders.md)).
5. Suzie (plugin phase `PostEngineInit`) parses the jmap, compares it with the live editor reflection, loads the extension module named by `profile.json`, registers struct ops, generates enums, structs, classes and delegates, installs the schema override provider (recipes derived from the same comparison), the skip list and the post-serialize handlers, flushes the cached unversioned schemas, then writes the gameplay tags ([native-type-generation.md](native-type-generation.md), [schema-shadow-properties.md](schema-shadow-properties.md), [tags.md](tags.md)).
6. Cooked packages load through the stock IoStore loader with the modkit tolerances (serial size mismatch seeks, missing templates warn, invalid imports yield null).

## Engine hooks (modkit-core)

Each hook has a stock default; without a registration the stock behaviour runs.

| Hook | Header / file | Purpose |
|---|---|---|
| Config | `Misc/ModkitCore.h` | `FGameConfig` from `engine.ini` and `ModkitData/ModkitLocal.ini`; `GetAesKey` (key from a file, never logged) |
| Container cipher | `Misc/ModkitCore.h` | `IContainerCipher`; the built-in pipeline cipher is built from `engine.ini` (`IoStoreDirectoryIndex`, `PakIndex`, `PakFooterVariant`). Call points: `IoStore.cpp` (directory index), `PakFile.cpp` (footer and index). `SetPakCustomData` stores the footer custom bytes per pak. |
| Data driven behaviour | `IPlatformFilePak.cpp`, `AssetRegistry.cpp`, `ShaderCodeLibrary.cpp`, `LaunchEngineLoop.cpp`, `ShaderCompiler.cpp`, `MemoryImage.cpp`, `RHICoreShader.cpp` | Paks dir, premade registry, shader library open, layout tolerance, uniform buffer alias, plugin content roots |
| Package filter | `Misc/ModkitCore.h`, `IoDispatcher.cpp`, `FilePackageStore.cpp`, `AssetRegistry.cpp` | packages hidden by `AssetFilter.txt` are absent from the IoStore dispatcher, the package store and the premade registry; `FPackageFilterBypassScope` reads past it on one thread ([asset-loader.md](asset-loader.md)) |
| Cook against the mounted game | `CookOnTheFlyServer.cpp` | a cook by the book records the packages of the mounted containers as base game: referenced, not cooked, not in the cooked asset registry; without an explicit request it cooks the project content folders only; the editor's Cook Content and Package commands cook versioned packages (`CookCommandlet.cpp`, `TurnkeySupportModule.cpp`, [cooking.md](cooking.md)) |
| Schema override | `UObject/UnversionedSchemaOverride.h` | `SetOverrideProvider`, `FlushAllUnversionedSchemas`, `UE_MODKIT_SCHEMA_HOOK_LEVEL` |
| Native serialize registries | same header, `UE::NativeSerialize` | `AddSkipClass` (exports skipped on load, never CDOs), `AddPostSerialize` (handler after `UObject::Serialize` of a non-CDO export), `AddGeneratedClass`/`AddGeneratedStruct`, `IsNativeRowStruct` |
| Uniform buffer translation | `RHI/Public/RHIUniformBufferTranslation.h`, `RenderCore/Private/UniformBufferTranslationLoader.cpp`, `D3D12UniformBuffer.cpp`, `D3D12Commands.cpp` | registry of game layouts keyed by editor layout hash, loaded from the profile; D3D12 keeps a game-layout twin of each translated uniform buffer and binds it to shaders that expect the game hash |
| Struct type hash fallback | `Class.cpp` | `GetStructTypeHash` hashes members with `CPF_HasGetValueTypeHash` when a struct has no `CppStructOps` |
| Loader resilience | `AsyncLoading2.cpp`, `LinkerLoad.cpp`, `UnversionedPropertySerialization.cpp`, `ShaderMap.cpp`, D3D12 RHI | tolerances listed above; null safe shader maps for unknown shader types |
| Cooked editing | `MaterialShared.cpp`, `Material.cpp`, `MaterialInstance.cpp`, `MaterialEditorUtilities.cpp`, asset editor gates | editing of cooked assets, cooked parameter panel, static permutation rules |

## Hook levels

Two separate numbers in the engine tree:

- `Modkit::HookApiLevel` (`Core/Public/Misc/ModkitCore.h`, value 1) is the level of the modkit hook set. `Core/Private/Misc/ModkitCore.cpp` compares it with the profile's `engine.ini [Profile] RequiresHookApi` (default 1, DBD sets 1) and leaves the modkit inactive with an error when the profile requires a higher level. No other reader in `Runtime/Core` or `Runtime/CoreUObject`.
- `UE_MODKIT_SCHEMA_HOOK_LEVEL` (`CoreUObject/Public/UObject/UnversionedSchemaOverride.h`, value 3) is the level of the schema override, post-serialize and generated-type hooks. The engine does not test it. Suzie tests it at compile time in `Source/Suzie/Private/Gen/SzBakedGenerator.cpp`: `SUZIE_HAS_HOOK_LEVEL2` for level 2 or more (row structs keep `TableRowBase` as super), `SUZIE_HAS_HOOK_LEVEL3` for level 3 or more (byte and enum shadows read as integers). Without the header the schema override code is not compiled.

Switches, ini keys and console commands: [profile-format.md](profile-format.md). Branch workflow and builds: [engine-fork.md](engine-fork.md).
