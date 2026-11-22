# Sweeps and verification

All scripts live in `Suzie-fork\Tools\sweep` (installed builds: `<engine>\Engine\Plugins\Modkit\Suzie\Tools\sweep`). They start the editor, so only one runs at a time (GPU, DDC and project lock are shared). They carry no machine paths.

Common arguments: `-Project <path of the .uproject>` (or env `MODKIT_PROJECT`), `-Extra "<more editor args>"`, `-OutDir <dir>` (default `<ProjectDir>\Saved\SuzieSweeps`). The engine comes from `[Local] EngineDir=` of `<ProjectDir>\ModkitData\ModkitLocal.ini` when it is set, else from the `.uproject` `EngineAssociation` (a path, or an engine id registered under `HKCU\Software\Epic Games\Unreal Engine\Builds`); the key file path from `[Local] KeyFile=` is passed as `-ModkitKeyFile=`. The DDC is `<ProjectDir>\DDC`.

Every script compares the project's `Config` folder with the profile's project template (`packaging.json` `template`, found through `[Local] Profile=`) and prints a warning listing files that exist only in the project, are missing in it, or differ from the template. The generated tag list (`tags.json` `tags_ini`) and `Config/DefaultGameplayTags.ini` are not compared, nor is the `AndroidFileServer` section the editor adds on its first start. Gate values and golden dumps are taken from a project without such differences, so that they match a project made from the template.

| Script | Purpose |
|---|---|
| `run_gates.ps1 -Tag t [-OldGolden file] [-Skip golden,bp,mat]` | golden dump + Blueprint sweep + material sweep; writes `<Tag>.summary.json` |
| `golden.ps1 -Tag t -Out file [-TimeoutSec s]` | one editor start (killed after `-TimeoutSec`, default 900): `golden.py` runs verify, tag probe and `Suzie.DumpAll` |
| `golden_diff.py old new [--structure]` | compares two dumps block by block (`.gz` or plain text); `--structure` ignores sizes, offsets, flags; exit 1 when a difference is found |
| `runlist.ps1 -list <list> -tag t` | Blueprint/AnimBP/Widget load sweep (`m_test.py`) in one editor session; restarts after a crash and records the culprit; list lines may carry `|Type` |
| `make_sweep_csv.py <tag> <out.csv> --dir <OutDir> --list <list>` | classifies each asset CLEAN, DIRTY (loads, error lines in its log slice) or CRASH |
| `sweep.ps1 -list <asset\|class list> -tag t` | material/MIC sweep (`sweep.py`) in one editor session: creates a MIC, assigns it to a sphere, renders a 128x128 capture and reads it back (which waits for the GPU); restarts after a crash and records the asset being rendered. The CSV adds error lines per asset, pixels that differ from a capture without the sphere (0 = nothing visible) and the largest channel difference |
| `dt_run.ps1 -Tag t -Max 300` | loads random DataTable assets from the registry (`dt_test.py`); after a crash the culprit is excluded and the session restarts |

Asset lists: `Profiles/DBD/sweeps/blueprints_531.list`, `materials_200.list`, `plugin_materials_100.list`, `roots_17_failing.txt`.

## Gate values (DBD 10.2.2)

- `Suzie.VerifyNativeTypes`: `types=10163 ok=10004 mismatch=159` (gate: ok >= 10,000 of 10,163; the 159 notes are non-reflected members, vtables, shared pointers, padding).
- Generation summary: 1,099 new + 20 existing enums, 2,571 structs, 7,592 classes, 14,459 functions; overrides 50 types / 160 shadow properties / 0 skipped.
- Golden dump: no difference to `data/golden/golden.txt.gz` (`golden_diff.py`).
- Blueprint sweep (531 assets): CLEAN >= 529, DIRTY <= 2 (`BP_ST_Basement01`, `BP_TL_St_2x2_Shrine_Hti`), CRASH 0.
- Material sweep (200): PASS 200. Plugin materials (100): PASS 100.
- DataTable sweep: all sampled tables load.
- Mount: 307 + 307 containers, 96,267 registry assets, 238 plugin content roots, shader libraries Global 4,741 and DeadByDaylight 164,124 shaders.

## Golden dump

- `Profiles/DBD/data/golden/golden.txt.gz`: output of `Suzie.DumpAll` (11,666 type blocks; 1,119 enums listed, of which 20 exist in the editor already). It lists the game's types, so git does not track it (`.gitignore`); each machine keeps its own copy, a gzip of the dump `Tools/sweep/golden.ps1 -Out <file>` writes on a build that passes the other gates, or a copy from another machine.
- Gate: `golden_diff.py <golden.txt.gz> <new dump>` reports no difference (the tool reads `.gz` and plain text).

## Other checks

- `Suzie-fork\Tools\check-layers.ps1`: no game or studio name in the generic plugin `Source`; exit 1 on a hit.
- Editor Python scripts run with `-ExecutePythonScript=<file>` (the editor exits after the script) or `-ExecCmds="py <file>"` (the editor stays open).
