# Profile: DBD

All game specifics of Suzie live in this directory, plus the engine branch `game/dbd` for layouts that cannot be data. `Source/` of the plugin contains no game names (`Tools/check-layers.ps1`). Nothing in this directory is generated: the game's types, schema recipes and gameplay tags are derived from the game's jmap at every editor start.

| File | Purpose |
|---|---|
| `profile.json` | entry point: names the data files, the extension module, plugins that must not generate at the same time (relative paths resolve against this directory) |
| `engine.ini` | read by the ENGINE (`Misc/ModkitCore.cpp`) before any plugin loads: container probing, index cipher pipeline, shader library, layout tolerance, plugin content roots |
| `ModkitLocal.example.ini` | machine local keys; copy to `<Project>/ModkitLocal.ini` (never put a key VALUE there, only the path of the key file) |
| `schema/aliases.json` | game type path to editor type path (empty); `by_leaf_fallback` is opt-in |
| `schema/overrides.json` | generation policy: abstract rules, flags, row structs (`structs.row_struct`: `keep_super_guarded` or `drop_super`) |
| `load/skip.json` | `skip_export_classes` (exports skipped on load) and `post_serialize` (handler names provided by the extension) |
| `load/native_ops.json` | structs whose C++ struct ops come from the extension |
| `tags/tags.json` | `tags_ini` (project relative path of the written tag list) and `probe_tag` |
| `sweeps/` | asset lists of the sweep harness (`Tools/sweep`) |
| `data/golden/golden.txt.gz` | golden reflection dump (`Suzie.DumpAll`, gzip) |
| `Plugin/DBDModkitGame` | the only DBD specific CODE (module named by `extension_module`, loaded by Suzie on demand) |

`profile.json` keys: `format`, `id`, `description`, `aliases`, `overrides`, `skip`, `tags`, `native_ops`, `extension_module`, `conflicting_plugins`.

## Shadow recipes

The game's engine classes carry members the editor lacks (about 50 types, e.g. `AActor::TickIntervalOnDS`, `UMaterial::bIsGroundTagged`, `FPostProcessSettings::BHVRPostProcessOverlayColor`) and the game has types the engine does not (`FMaterialVariant`, `UBHVRVariantGenerator`, ...). Suzie generates the missing types from the jmap. For every editor type whose game property list differs it builds a recipe, consumed through the engine's unversioned schema override hook: a member the editor type lacks is read into a temporary and discarded; an editor property that matches (name, property class, array dimension, struct path) is used live. Values of the discarded members are not visible in the editor.

## Use

`<Project>/ModkitLocal.ini`:

    [Local]
    Profile=<absolute path of this directory>     ; the profile FOLDER: engine.ini (engine) and profile.json (Suzie) are read from it
    GameRoot=...   KeyFile=...
    Jmap=<the game's jmap>                        ; required; none ships with the modkit

With a profile selected, a jmap configured and no conflicting plugin enabled, Suzie generates the game's types at startup. Switches: `-DisableSuzie`, `-DisableModkit`, `-SuzieProfile=<name|dir>`, `-SuzieJmap=<file>`, `-SuzieDumpDerived=<dir>`. Commands: `Suzie.GenerateNativeTypes`, `Suzie.VerifyNativeTypes`, `Suzie.DumpClass`, `Suzie.DumpAll <file>`, `Suzie.TagInfo`.

The extension plugin must be discoverable by the project: junction or copy `Plugin/DBDModkitGame` into `<Project>/Plugins/` (or list its parent in `AdditionalPluginDirectories`) and enable it in the `.uproject`; Suzie is installed the same way (`<Project>/Plugins/Suzie` is this repository).

## Gates (`Tools/sweep/run_gates.ps1`)

Golden dump without difference to `data/golden/golden.txt.gz` (`golden_diff.py`); Blueprint/AnimBP/Widget sweep (`sweeps/blueprints_531.list`): CLEAN >= 529, DIRTY <= 2 (`BP_ST_Basement01`, `BP_TL_St_2x2_Shrine_Hti`), CRASH 0; material sweep: PASS 200; `Suzie.VerifyNativeTypes` ok >= 10,000 of 10,163 types.
