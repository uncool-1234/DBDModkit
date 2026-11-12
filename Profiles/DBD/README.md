# Profile: DBD

All game specifics of the fork live here; `Source/` contains no game names (checked by `Tools/check-layers.ps1`).

| File | Purpose |
|---|---|
| `profile.json` | entry point: names the data files, plugins that must not generate at the same time, optional usmap tsv for `Suzie.VerifyNativeTypes` (machine-local path) |
| `data/bake/types.json` | GENERATED, gitignored (10.6 MB). Input format = the baked JSON "format 1" written by `tools/dbd_native_baker.py` from the jmap + usmap. |
| `data/bake/cdo.json` | GENERATED CDO deltas (not consumed yet, phase 3) |
| `data/golden/golden.txt.gz` | golden reflection dump (`Suzie.DumpAll`), old generator output == fork output (empty diff) |
| `schema/engine_diff.json` | recipes for engine types whose game layout differs (17 types, 24 shadow properties) |
| `schema/aliases.json` | game type path -> editor type path; `by_leaf_fallback` is opt-in |
| `schema/overrides.json` | policy: classes deriving from these paths are Abstract; struct supers never applied (row struct base) |
| `load/skip.json` | classes whose cooked exports are skipped on load |
| `tags/tags.json` | gameplay tag description (probe tag, ini path); `tools/gen_tags.py` writes the ini files |
| `sweeps/` | lists used by the sweep harness (`Tools/sweep`) |

## Input format decision

The fork consumes the already baked JSON (format 1) instead of the raw jmap: the generator code was ported unchanged from
the standalone generator (its input is that format, 10.6 MB, parsed in about 1 s), whereas the raw jmap is 180 MB and needs a
streaming parser (not written). Upstream Suzie's jmap path (`Content/DynamicClasses`) is kept and is used when a profile has
no types file or with `-SuzieUpstreamJmap`.

## Use

    -SuzieGenerate -SuzieProfile=DBD [-DisableDBDNativeTypes]
    (or ModkitLocal.ini [Local] SuzieProfile=DBD)

`DBDNativeTypes` and the fork must not both generate: `profile.json conflicting_plugins` makes the fork refuse unless the other plugin is disabled.
Commands: `Suzie.GenerateNativeTypes`, `Suzie.VerifyNativeTypes [usmap tsv]`, `Suzie.DumpClass`, `Suzie.DumpAll <file>`, `Suzie.TagInfo`.
