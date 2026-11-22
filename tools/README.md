# Tools

Scripts shipped with the installed plugin live in `Suzie-fork\Tools`; release scripts live in `Packaging`; this folder holds the workspace level scripts.

## tools\env

| File | Use |
|---|---|
| `env\modkit-env.cmd` | `call "%MODKIT_ROOT%\tools\env\modkit-env.cmd"` sets `MODKIT_ROOT` to the project root (two levels above the file) unless already set. `Packaging\build-installed.cmd` uses it. |
| `env\modkit-env.ps1` | dot-source `. "<root>\tools\env\modkit-env.ps1"`; sets `$env:MODKIT_ROOT` the same way |

## Tools in the repositories

| Path | Use |
|---|---|
| `Suzie-fork\Tools\sweep\` | sweep harness: `run_gates.ps1`, `golden.ps1`, `golden_diff.py`, `runlist.ps1`, `sweep.ps1`, `dt_run.ps1`, `make_sweep_csv.py`, editor-side `golden.py`, `m_test.py`, `sweep.py`, `dt_test.py` ([docs\sweeps-and-verification.md](../docs/sweeps-and-verification.md)) |
| `Suzie-fork\Tools\check-layers.ps1 -Pattern <regex>` | fails when the pattern matches a tracked file of the Suzie repository; `tools\check-suzie-layers.ps1` runs it with this game's names |
| `Packaging\publish-engine.cmd` | one-command release: build copy, BuildGraph, trim, safety scan, optional smoke test, encrypted `.7z` ([docs\installed-build-and-publishing.md](../docs/installed-build-and-publishing.md)) |
| `Packaging\build-installed.cmd` | the BuildGraph command `publish-engine.cmd` runs |
| `Suzie-fork\Source\Suzie\Private\Setup\SzProjectSetup.cpp` | project setup window (writes `ModkitData\ModkitLocal.ini`) and `Suzie.ProjectSetup` ([docs\profile-format.md](../docs/profile-format.md)) |
| `Packaging\EngineRoot\Register Engine.bat` | shipped in the release's engine folder; registers it as the template's `EngineAssociation` |

## External tools at the workspace root

| Path | Use |
|---|---|
| `oatmealf-5.7\` | Rust tool that compares the game's uniform buffer layouts (from a minidump) with the editor's; its `uniform_layouts` binary writes the profile's `uniform_layouts.txt`; `README-5.7.md` ([docs\game-update.md](../docs/game-update.md)) |
| `CUE4Parse\`, `retoc\` | external repositories |
