# Profile: DBD

All game specifics of the Suzie fork live in this directory (plus the small engine branch `game/dbd` for layouts that cannot be data).
`Source/` of the fork contains no game names (checked by `Tools/check-layers.ps1`).

| File | Purpose |
|---|---|
| `profile.json` | entry point: names the data files, the extension module, plugins that must not generate at the same time, the optional usmap tsv for `Suzie.VerifyNativeTypes` (relative paths resolve against this directory) |
| `engine.ini` | read by the ENGINE (Core, `Misc/ModkitCore.cpp`) before any plugin loads: container probing, index cipher pipeline, shader library, layout tolerance, plugin content roots |
| `ModkitLocal.example.ini` | machine local keys; copy to `<Project>/ModkitLocal.ini` and edit (never put a key VALUE there, only the path of the key file) |
| `data/bake/types.json` | GENERATED, gitignored (10.6 MB): baked types (format 1) written by `tools/dbd_native_baker.py` from the jmap |
| `data/bake/cdo.json` | GENERATED CDO deltas (not consumed yet) |
| `data/bake/*_stage1.json` | the baked files of stage 1 (game members still carried by engine headers), kept for A/B |
| `data/cache/` | local, gitignored: `game_schemas.tsv` (usmap dump for `Suzie.VerifyNativeTypes`) |
| `data/editor_schemas_stock.tsv`, `data/stock_info.json` | baker inputs describing the STOCK 5.7.4 reflection (gitignored, see "Re-baking") |
| `data/golden/` | golden reflection dumps (`Suzie.DumpAll`, gzip) of stage 1 and stage 2 and the reviewed whitelist between them |
| `schema/engine_diff.json` | recipes for the engine types whose game layout differs: 50 types, 160 shadow properties. Entries marked `fk` are members the legacy fork carried in engine headers (validation aid, see `-SuzieForceShadowMarked`) |
| `schema/_fork_additions.json` | the legacy fork members/types (source of the `fk` marks; no engine header carries them any more) |
| `schema/aliases.json` | game type path -> editor type path (empty); `by_leaf_fallback` is opt-in |
| `schema/overrides.json` | policy: abstract rules, row structs (`structs.row_struct`: `keep_super_guarded` keeps `TableRowBase` as super of generated row structs, `drop_super` removes it) |
| `load/skip.json` | `skip_export_classes` (cooked exports skipped on load) and `post_serialize` (handler names provided by the extension) |
| `load/native_ops.json` | structs whose C++ struct ops come from the extension (`/Script/Engine.BHVRVariantConfigurator`, serialized raw by the game) |
| `Plugin/DBDModkitGame` | the only DBD specific CODE: struct ops and the post-serialize handler (module loaded by Suzie on demand, `extension_module` in `profile.json`) |
| `tags/tags.json` | gameplay tag description (probe tag, ini path); `Tools/suzie_tags.py` writes the ini files |
| `sweeps/` | lists used by the sweep harness (`Tools/sweep`) |
| `tools/` | baker (`dbd_native_baker.py`), `make_stock_editor_schema.py`, flag tables, `bake_all.cmd` |

## Shadow recipes instead of engine members

The game's engine differs from stock UE 5.7.4 by members added to about 50 engine classes/structs (e.g. `AActor::TickIntervalOnDS`, `UMaterial::bIsGroundTagged`,
`FPostProcessSettings::BHVRPostProcessOverlayColor`) and by types that exist only in the game (`FMaterialVariant`, `UBHVRVariantGenerator`, ...).
The engine headers carry none of them. The types are generated from `types.json`; the missing members are listed in `schema/engine_diff.json` with the game's
full property list and are consumed through the engine's unversioned schema override hook (`UObject/UnversionedSchemaOverride.h`): a member the engine type
lacks is read into a temporary and discarded. Where a stock property matches (name, type, array dimension) it is used live.
Values of these members are therefore not visible in the editor; nothing in the editor reads them.

## Re-baking

    set SUZIE_JMAP=<game>.jmap                    (or --jmap, or Jmap= in ModkitLocal.ini with --local-ini)
    python -I tools/dbd_native_baker.py --editor-schemas data/editor_schemas_stock.tsv --out data/bake/types.json --cdo-out data/bake/cdo.json
    (writes schema/engine_diff.json too; tools/bake_all.cmd does this)

`editor_schemas_stock.tsv` is a reflection dump of the STOCK editor (`S`/`P` lines). `tools/make_stock_editor_schema.py` derives it from a dump taken on a modified
fork by removing the members a commit added (`--repo`, `--commit`), and writes the `fk` mark list.

## Use

`<Project>/ModkitLocal.ini`:

    [Local]
    Profile=<absolute path of this directory>     ; engine.ini (engine) and profile.json (Suzie) are both read from it
    GameRoot=...   KeyFile=...

With a profile selected and no conflicting plugin enabled, Suzie generates the game's types at startup (no switch needed).
Switches: `-DisableSuzie`, `-DisableModkit` (engine side), `-SuzieProfile=<name|dir>`, `-SuzieForceShadowMarked[=Type+Type.Member]` (validation).
Commands: `Suzie.GenerateNativeTypes`, `Suzie.VerifyNativeTypes [usmap tsv]`, `Suzie.DumpClass`, `Suzie.DumpAll <file>`, `Suzie.TagInfo`.

The extension plugin must be discoverable by the project: junction/copy `Plugin/DBDModkitGame` into `<Project>/Plugins/` (or list its parent in `AdditionalPluginDirectories`)
and enable it in the .uproject; Suzie itself is installed the same way (`<Project>/Plugins/Suzie` -> this repository).

## Gates (see Tools/sweep/run_gates.ps1)

Golden dump structurally equal to stage 1 except `data/golden/whitelist_stage2.txt`; 531 Blueprint/AnimBP/Widget load sweep (`sweeps/blueprints_531.list`): CLEAN >= 529,
DIRTY <= 2 (`BP_ST_Basement01`, `BP_TL_St_2x2_Shrine_Hti`), CRASH 0; 200 material/MIC sweep: PASS 200; `Suzie.VerifyNativeTypes` ok >= 10,000 of 10,163 types.
