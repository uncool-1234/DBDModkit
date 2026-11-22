# Schema recipes and shadow properties

Cooked data uses unversioned property serialization: the loader derives the property order of each struct from the type's reflection schema. Where the game's engine classes carry members the editor lacks (about 50 types, 160 members such as `AActor::TickIntervalOnDS`, `UMaterial::bIsGroundTagged`), the editor schema would desynchronize. Recipes describe the game's full property list of those types; members the editor type lacks become **shadow properties** that are read and discarded.

## Engine side (`UObject/UnversionedSchemaOverride.h`)

- `SetOverrideProvider(FOverrideProvider)`: one provider; called when the GAME schema of a struct is built (`bSkipEditorOnly` true), possibly on loader threads, so it is thread safe and side effect free. It receives the entries in property link order and may rewrite them (`FOverrideEntry {Property, ArrayIndex, bDiscard}`).
- A discard entry points to a standalone shadow property: the value is read into a temporary and dropped. `ShouldSaveAsZero` is true; saving is not supported (shadows are written as skips).
- Byte and enum shadows are read as raw integers (`UE_MODKIT_SCHEMA_HOOK_LEVEL 3`).
- The schema hash includes a marker plus the names and discard flags.
- `FlushAllUnversionedSchemas()` (game thread, no async load in flight) drops the cached schemas; Suzie calls it once after installing the provider.

## Recipes (derived at every editor start)

No recipe file exists. Suzie compares the game's property list of each editor type with the live reflection of the running editor ([native-type-generation.md](native-type-generation.md)) and builds one recipe per type whose lists differ:

- The recipe is the game's property list in game order. Name (case-insensitive, `_DEPRECATED` suffix ignored), property type and array dimension are the comparison key; editor-only properties are ignored.
- Per entry, the live editor property is used when its name, property class, array dimension and (for struct properties) struct path match the game's; otherwise a standalone shadow property is built and read and discarded.
- Live properties that the game's list does not contain disappear from the game schema.
- A type is skipped (counted in `skipped`) when the editor type cannot be resolved or a shadow cannot be built; the warning names the type.
- Editor types whose short name is shared by several editor types are left alone.
- Startup counters (`Schema overrides: <types> types, <shadows> shadow properties, <skipped> skipped`; DBD 10.2.2: 50/160/0) match the gate values of the sweep harness.
- `-SuzieDumpDerived=<dir>` writes the derived recipe records as `engine_diff.json` for inspection (record keys: top of `Private/Gen/SzJmapSource.cpp`).

## Aliases and overrides

`schema/aliases.json` maps a game type path to the editor path (looked up before `FindObject`; leaf name matching is opt-in and logs a warning). `schema/overrides.json` holds generation policy: `classes` (`abstract_if_derived_from`, `strip_flags`, `force_flags`, interface and subobject rules), `structs` (`keep_flags`, `pad_to_game_size`, `empty_struct_size`, `row_struct`), `enums` (`mode`), `stub_modules_enable_instead` (stock modules enabled instead of generated).

## Symptoms

An assertion `SchemaIt != SchemaEnd` in the unversioned loader means a game class or struct has reflected members the schema does not account for: the jmap does not describe the type, or the type was left alone because its short name is shared by several editor types.
