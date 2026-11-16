# Profile: DBD

All game specifics of Suzie live in this directory, plus the engine branch `game/dbd` for layouts that cannot be data. `Source/` of the plugin contains no game names (`Tools/check-layers.ps1`).

| File | Purpose |
|---|---|
| `profile.json` | entry point: names the data files, the extension module, plugins that must not generate at the same time, the usmap tsv for `Suzie.VerifyNativeTypes` (relative paths resolve against this directory) |
| `engine.ini` | read by the ENGINE (`Misc/ModkitCore.cpp`) before any plugin loads: container probing, index cipher pipeline, shader library, layout tolerance, plugin content roots |
| `ModkitLocal.example.ini` | machine local keys; copy to `<Project>/ModkitLocal.ini` (never put a key VALUE there, only the path of the key file) |
| `data/bake/types.json`, `data/bake/cdo.json` | GENERATED, gitignored: baked types (format 1, read by Suzie) and CDO deltas written by `tools/dbd_native_baker.py` (not read by Suzie; CDO property values are not applied) |
| `data/bake/*_stage1.json` | baked files for a build whose engine headers still carry game members |
| `data/cache/` | local, gitignored: `game_schemas.tsv` (usmap dump for `Suzie.VerifyNativeTypes`) |
| `data/editor_schemas_stock.tsv`, `data/stock_info.json` | baker inputs describing the STOCK 5.7.4 reflection (gitignored) |
| `data/golden/` | golden reflection dumps (`Suzie.DumpAll`, gzip) and the reviewed whitelist between them |
| `schema/engine_diff.json` | recipes for the engine types whose game layout differs: 50 types, 160 shadow properties; entries marked `fk` are members a modified engine tree carries as real code (`-SuzieForceShadowMarked`) |
| `schema/_fork_additions.json` | members/types a modified engine tree carries in its headers (source of the `fk` marks) |
| `schema/aliases.json` | game type path to editor type path (empty); `by_leaf_fallback` is opt-in |
| `schema/overrides.json` | generation policy: abstract rules, flags, row structs (`structs.row_struct`: `keep_super_guarded` or `drop_super`) |
| `load/skip.json` | `skip_export_classes` (exports skipped on load) and `post_serialize` (handler names provided by the extension) |
| `load/native_ops.json` | structs whose C++ struct ops come from the extension |
| `Plugin/DBDModkitGame` | the only DBD specific CODE (module named by `extension_module`, loaded by Suzie on demand) |
| `tags/tags.json` | gameplay tag source, ini path, probe tag; `Tools/suzie_tags.py` writes the ini files |
| `sweeps/` | asset lists of the sweep harness (`Tools/sweep`) |
| `tools/` | baker `dbd_native_baker.py`, `bake_all.cmd`, `make_stock_editor_schema.py`, `scan_stock.py`, flag tables, `usmap_reader.py`, `usmap_to_tsv.py` (writes `data/cache/game_schemas.tsv` from a usmap) |

## Shadow recipes

The game's engine classes carry members the stock UE 5.7.4 lacks (about 50 types, e.g. `AActor::TickIntervalOnDS`, `UMaterial::bIsGroundTagged`, `FPostProcessSettings::BHVRPostProcessOverlayColor`) and the game has types the engine does not (`FMaterialVariant`, `UBHVRVariantGenerator`, ...). The types are generated from `types.json`; the missing members are listed in `schema/engine_diff.json` with the game's full property list and are consumed through the engine's unversioned schema override hook: a member the stock type lacks is read into a temporary and discarded; a stock property that matches (name, type, array dimension) is used live. Values of the discarded members are not visible in the editor.

## Re-baking

    set SUZIE_JMAP=<game>.jmap                    (or --jmap, or Jmap= in ModkitLocal.ini with --local-ini)
    python -I tools/dbd_native_baker.py --editor-schemas data/editor_schemas_stock.tsv --out data/bake/types.json --cdo-out data/bake/cdo.json

`tools/bake_all.cmd` does this and also writes `schema/engine_diff.json`. `editor_schemas_stock.tsv` is a reflection dump of the STOCK editor (`S`/`P` lines); `tools/make_stock_editor_schema.py` derives it from a dump taken on a modified engine tree by removing the members a commit added (`--repo`, `--commit`) and writes the `fk` mark list.

## Use

`<Project>/ModkitLocal.ini`:

    [Local]
    Profile=<absolute path of this directory>     ; the profile FOLDER: engine.ini (engine) and profile.json (Suzie) are read from it
    GameRoot=...   KeyFile=...

With a profile selected and no conflicting plugin enabled, Suzie generates the game's types at startup. Switches: `-DisableSuzie`, `-DisableModkit`, `-SuzieProfile=<name|dir>`, `-SuzieForceShadowMarked[=Type+Type.Member]`. Commands: `Suzie.GenerateNativeTypes`, `Suzie.VerifyNativeTypes [usmap tsv]`, `Suzie.DumpClass`, `Suzie.DumpAll <file>`, `Suzie.TagInfo`.

The extension plugin must be discoverable by the project: junction or copy `Plugin/DBDModkitGame` into `<Project>/Plugins/` (or list its parent in `AdditionalPluginDirectories`) and enable it in the `.uproject`; Suzie is installed the same way (`<Project>/Plugins/Suzie` is this repository).

## Gates (`Tools/sweep/run_gates.ps1`)

Golden dump structurally equal to `data/golden/golden_stage1.txt.gz` except `data/golden/whitelist_stage2.txt`; Blueprint/AnimBP/Widget sweep (`sweeps/blueprints_531.list`): CLEAN >= 529, DIRTY <= 2 (`BP_ST_Basement01`, `BP_TL_St_2x2_Shrine_Hti`), CRASH 0; material sweep: PASS 200; `Suzie.VerifyNativeTypes` ok >= 10,000 of 10,163 types.
