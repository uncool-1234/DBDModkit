# Native type generation

Cooked DBD Blueprints, widgets and data reference classes, structs and enums of the game's native modules that the stock editor does not have. Suzie creates them in memory at every editor start from the game's jmap; no UHT module, no compile step and no intermediate file are involved. Generated types live under their game paths (`/Script/<Module>.<Name>`) with package flag `PKG_CompiledIn`.

## Inputs

| Input | Origin | Content |
|---|---|---|
| the game's `.jmap` | user supplied ([jmap-usmap.md](jmap-usmap.md)); `-SuzieJmap=<file>`, else `[Local] Jmap=` in `<Project>\ModkitData\ModkitLocal.ini` | JSON reflection dump (trumank/jmap format): enums, structs, classes, delegates, functions, properties with exact flag masks, struct sizes, interfaces, default subobjects, the tag settings object |
| live editor reflection | the running editor | the types, packages and property lists the jmap is compared with |
| `schema/overrides.json`, `schema/aliases.json` | profile, hand written | generation policy |

`Jmap=` is required. Without a readable jmap Suzie logs `Suzie idle: profile '<id>' needs the game's jmap, ...` and generates nothing. Only the property order, count and type matter; the engine computes offsets in `UStruct::Link`.

## Derivation from the jmap (`Private/Gen/SzJmapSource.cpp`)

At plugin phase `PostEngineInit` Suzie parses the jmap once per session, compares it with the live reflection of the running editor and derives the generator's records in memory (the record key vocabulary is documented at the top of `SzJmapSource.cpp`; `FSzBakedGenerator` consumes the records). Measured for DBD 10.2.2: jmap 180 MB, 63,026 objects, parse 8.1 s, derive 1.1 s, generate 0.8 s. Log lines:

```
jmap <file>: 63026 objects, parse 8.1s, derive 1.1s
Schema overrides: 50 types, 160 shadow properties, 0 skipped
GENERATE OK jmap=<file>: enums=1099(+20 existing) structs=2571(...) classes=7592(...) delegates=604 functions=14459 ... overrides=50/160/0 ...
```

Rules:

- A class or struct is generated when the editor has no `UStruct` of that path.
- An enum is generated when its `/Script` package has no type in the editor, or when the editor lacks it and a recipe refers to it.
- Order: structs members first, classes super first, otherwise by path.
- A schema recipe is built for an editor type when the game's property list (name compared case-insensitively without a `_DEPRECATED` suffix, property type, array dimension; editor-only properties ignored) differs from the editor's. Editor types whose short name is shared by several editor types are left alone ([schema-shadow-properties.md](schema-shadow-properties.md)).
- The game's tag list and redirects are read from the jmap and written after generation ([tags.md](tags.md)).
- Generated structs that the game serializes natively (`STRUCT_SerializeNative`) and that have no struct ops are reported: `N generated structs are serialized natively by the game and have no struct ops (load/native_ops.json): <paths>` (DBD 10.2.2: 6, listed in [limitations.md](limitations.md)).
- `-SuzieDumpDerived=<dir>` writes the derived records as `types.json` and `engine_diff.json` into `<dir>`.

## Generation order

1. Profile load (`profile.json`, schema, load lists); jmap parse and derivation.
2. Extension module load; struct ops from `load/native_ops.json` are registered (`UScriptStruct::DeferCppStructOps`).
3. Enums (`SetEnums`), structs (parents first), delegate signature shells, classes (shells first), properties and functions (super first), `Link`, registration events.
4. Schema override provider, skip classes, post-serialize handlers, `FlushAllUnversionedSchemas`.
5. CDO subobjects: default subobjects from the `so` lists of the derived class records, top-most generated class first (`Gen/SzBakedGenerator.cpp`), then the CDO of each generated class (`GetDefaultObject`, in class order). The jmap property values of each CDO (`cdo` of its record) and of its default subobjects (`pv`) are then set by `Gen/SzPropertyValues.cpp`, in class order. An instanced property (one that holds instanced object references) is set only when every object reference in its value lies inside the object being set, for example the CDO's own subobjects; otherwise it is left untouched and counted as `instancedForeign`. A new instance takes the value properties of its class from the class's CDO in the shared constructor (`SzGenericConstruct`), and a CDO takes those of its generated parent's CDO. In that copy, each object reference that points into the source CDO is set to the same-named object of the new object, or to null when there is none (log: `remapped`, `nulled`). Switch `-SuzieNoCdoValues` skips this step ([profile-format.md](profile-format.md)). Only children with `RF_DefaultSubObject` are listed in `so`; other children of a class default object (for example a shape's body setup, created on demand by the engine) are not. Log lines: `Suzie: CDO values: classes=... applied=... skipped=... typeMismatch=... unresolvedObjects=... subobjects=... cdoInternal=... instancedApplied=... instancedForeign=...` and `Suzie: CDO references: remapped=... nulled=...`, where `cdoInternal` counts references into a class default object that does not exist. Listed values with no editor property of that name are ignored and not counted.
6. Gameplay tags are written and the tag tree refreshed ([tags.md](tags.md)).

Generation takes about 0.8 s for DBD 10.2.2; the jmap parse and derivation come before it.

## Builders

- Properties: flags are the exact CPF bits of the jmap masks; container inner properties use `AddCppProperty`, which pushes to the head of `ChildProperties`, so properties are added in reverse order. A bool is native when `byte_mask==1 && field_mask==255`, else a bitfield (`SetBoolSize`).
- Structs: kept flags `STRUCT_HasInstancedReference`, `STRUCT_NoExport`, `STRUCT_Atomic`, `STRUCT_Immutable`, `STRUCT_RequiredAPI`; size and alignment padded to the game values; an empty struct has size 1. Row structs keep `TableRowBase` as super (`keep_super_guarded`); the engine `DataTable.cpp` guard uses `IsGeneratedStruct`.
- Enums: `NewObject<UEnum>`, `SetEnums` with the cpp form derived from the enumerator names and cpp type.
- Classes: `NewObject<UClass>`, flags from the jmap minus `CLASS_Config`, `CLASS_GlobalUserConfig`, `CLASS_ProjectUserConfig`, `CLASS_DefaultConfig`, `CLASS_Intrinsic`, `CLASS_Constructed`, `CLASS_TokenStreamAssembled`, plus `CLASS_Native`. Subclasses of `Subsystem` and `DeveloperSettings` are abstract. Interface classes are generated; implemented interfaces are listed on the class at offset 0.
- Shared class constructor: calls the first non-generated ancestor's constructor, initializes the properties the class introduces, creates the required default subobjects (the top-most generated class's override class wins; nested `Outer:Name` subobjects are supported). CDO subobjects are rooted.
- Functions of generated classes: script stubs (`EX_Return`, `EX_Nothing`, `EX_EndOfScript`), `FUNC_Native` stripped. A function with a native implementation registered by the game plugin is the exception (see below).
- Generated `UTexture` subclasses are registered through `AddGeneratedClass`; the engine returns early from `UpdateResourceWithParams` for them.
- Functions of classes the editor already has are added or replaced as described in [Engine class functions](#engine-class-functions).

## Game plugin (`DBDModkitGame`)

Registered as `ISuzieGameExtension` (`Source/Suzie/Public/SuzieExtension.h`) and bound by name from `load/native_ops.json` and `load/skip.json`.

| Member | Role |
|---|---|
| `static FName GetModularFeatureName()` | `SuzieGameExtension`; the name the plugin registers its feature under |
| `virtual FName GetProfileId() const` | the profile `id` the extension serves (`dbd`); `Register` is called only for a matching profile |
| `virtual void Register(FSzExtensionRegistry&)` | adds the named struct ops (`AddStructOps<StructT>(Name)`), post-serialize handlers (`AddPostSerialize(Name, Fn)`) and native function implementations (`AddNativeFunction(Path, Fn)`, `SuzieExtension.h`, keyed by function path) |

Registration: the game module's `StartupModule` calls `IModularFeatures::Get().RegisterModularFeature(ISuzieGameExtension::GetModularFeatureName(), &Extension)` and `ShutdownModule` unregisters it. The generator loads the module named by `extension_module` (`FModuleManager::LoadModule`), then calls `Register` on every feature implementation whose profile id matches (`Gen/SzBakedGenerator.cpp`).

| Name | Binds to | Behaviour |
|---|---|---|
| `dbd.variant_configurator` | struct `/Script/Engine.BHVRVariantConfigurator` | raw serialization: object reference, string, tag |
| `dbd.material_instance_trailing_variants` | post-serialize of `/Script/Engine.MaterialInstance` | reads the trailing int32 count and that many raw variant configurators |
| `dbd.bark_node_template` | struct `/Script/BhvrBark.BhvrBarkNodeTemplate` | 16 byte struct: int32 `bHasNode`, then a class package index and that class instance's unversioned properties inline, with no serial size; read into a transient object with `UObject::SerializeScriptProperties`, kept in the first 8 bytes, reported to the GC |

`load/skip.json` also skips exports of `/Script/AkAudio.AkAudioType` and derived classes (Wwise payloads).

The native function implementations registered by the DBD plugin:

- Float operators the stock engine removed, added to `KismetMathLibrary`: `Add_`, `Subtract_`, `Multiply_`, `Divide_`, `Less_`, `Greater_`, `LessEqual_`, `GreaterEqual_`, `EqualEqual_` and `NotEqual_FloatFloat` (float overloads), plus `MultiplyMultiply_DoubleDouble` and `NearlyEqual_DoubleDouble`.
- Replacements of stock functions: `MultiplyMultiply_FloatFloat` (game parameters are float), `KismetSystemLibrary::PrintString` and `PrintText` (game parameter `Key` is int32). A replacement reads the game's parameter layout only when the calling script is cooked; otherwise it runs the stock function.

## Engine class functions

The jmap lists the functions of each class in the output array `engine_class_functions`. For a class the editor already has, Suzie compares each jmap function with the editor's functions:

- A function the editor lacks is added. It is a native function when the game plugin registers an implementation for its path, otherwise a script stub with an empty body. Static functions of Blueprint function libraries without an implementation are not added; a call to them aborts the script ([troubleshooting.md](troubleshooting.md)).
- Generated functions are script stubs. When cooked bytecode calls one with `EX_CallMath` (the opcode for native library functions), the engine runs it as a normal script call with its own frame.
- A function the editor has with other parameters keeps the editor's signature. When the game plugin registers an implementation for its path, the implementation replaces the native thunk. Otherwise Suzie logs a warning naming the function.

Startup log line: `engine class functions: added <n> (native <m>, stub <k>), replaced <r>, skipped <s>, signature differs <d>`. DBD 10.2.2: `added 37 (native 12, stub 25), replaced 3, skipped 0, signature differs 5`. The five functions with a different signature and no implementation are `MeshComponent::SetOverlayMaterial`, `PlayerController::ClientWasKicked`, `PlayerInput::SetBind` and the delegate signatures `PlayMontageCallbackProxy::OnMontageEnded` and `OnMontageBlendingOut`. The 25 stub functions do nothing when called.

## Source map

`Suzie-fork/Source/Suzie`:

| File | Holds |
|---|---|
| `Suzie.Build.cs` | module rules; public `Core`, private `CoreUObject`, `Engine`, `Blutility`, `Json`, `GameplayTags`, `UnrealEd`, `Projects`, `BlueprintGraph`, `zlib` |
| `Public/SuziePlugin.h` | `FSuziePluginModule`, the upstream jmap route's construction and context structs, `LogSuzie` |
| `Public/SuzieExtension.h` | `ISuzieGameExtension`, `FSzExtensionRegistry`, `FSzPostSerializeFn` |
| `Private/SuziePlugin.cpp` | startup, profile selection and switches; upstream jmap route (`ProcessAllJsonClassDefinitions`, class, struct, enum and function builders, property value deserialization, CDO values) |
| `Private/SuzieDecompressionHelper.h/.cpp` | gzip inflate through zlib (used by the upstream jmap route) |
| `Private/Gen/SzProfile.h/.cpp` | `FSzProfile`: `profile.json` and the files it names, `[Local] SuzieProfile=` resolution |
| `Private/Gen/SzJmapSource.h/.cpp` | `SzJmap::ResolveFile`, `SzJmap::Get`: jmap parse, comparison with the live editor reflection, derived type records, recipe records, tag list, natively serialized structs (`FSzJmapTypes`) |
| `Private/Gen/SzFlagNames.inl` | flag name tables (CPF, CLASS, STRUCT, FUNC) used to read the jmap's flag strings |
| `Private/Gen/SzPropertyValues.h/.cpp` | `SzApplyPropertyValues`: sets the listed JSON values (property_values) on an object or struct; the value kinds per property type, `FSzValueStats` |
| `Private/Gen/SzBakedGenerator.h/.cpp` | `FSzBakedGenerator::Generate`: derived records to enums, structs, classes and delegates; schema override provider, skip and post-serialize registration, extension registration, default subobjects; `FSzGenStats`, `FSzGeneratedType` |
| `Private/Gen/SzCommands.cpp` | console commands `Suzie.GenerateNativeTypes`, `Suzie.VerifyNativeTypes`, `Suzie.DumpClass`, `Suzie.DumpObjectRefs`, `Suzie.DumpAll`, `Suzie.TagInfo`; `RunGenerateFromModule`; gameplay tag files |

## Verification

`Suzie.VerifyNativeTypes` (no argument) compares each generated type's live property list, sizes and offsets with the jmap: type count, ok count, layout notes (non-reflected members, vtables, shared pointers). DBD 10.2.2: `types=10163 ok=10004 mismatch=159`. `Suzie.DumpAll <file>` writes the canonical golden dump. `Suzie.DumpObjectRefs <object path>` prints every non-null object reference of an object (of a class: its default object), one line per value: the property path, the referenced object and whether that object lies inside the object itself (`outer is self`). `Suzie.VerifyNativeTypes` also logs the reference remap counters. See [sweeps-and-verification.md](sweeps-and-verification.md).
