# Packaging: installed build of the modkit engine

- `build-installed.cmd`: the BuildGraph command that produces the installed engine, run by `publish-engine.ps1` (environment variables `BUILD_SRC`, `OUT_DIR`, `LOG_DIR`, `UBA_HOST`). The source is a copy of the `game/dbd` tree without `.git`/`Intermediate`/`Saved`, with this repository's `Suzie` and `Profiles/DBD/Plugin/DBDModkitGame` copied to `Engine\Plugins\Modkit\Suzie` and `Engine\Plugins\Modkit\DBDModkitGame`. When `pdbcopy.exe` is unavailable, the `<Strip ...>` step of the build copy's `Engine/Build/InstalledEngineBuild.xml` is replaced by a `<Copy ...>` step (symbols ship unstripped).
- The engine filter drops non-code plugin folders: `publish-engine.ps1` copies the profile (without its `Plugin` folder) and `Tools` of this repository into `Engine\Plugins\Modkit\Suzie\` of the release.
- `DBDMount-Template/`: content-only project for the installed engine (no Source, no machine paths): `DBDMount.uproject`, `Config`, `ModkitProject.ps1`, `Setup Project.bat`, `Start Editor.bat`, `.gitignore`. `Setup Project.bat` writes `ModkitData\ModkitLocal.ini` from the files in `ModkitData` (profile `project.json`).
- `EngineRoot/Register Engine.bat`: placed in the root of the released engine folder; registers it as the profile's `engine_id`.
- `publish-engine.ps1` (entry point `publish-engine.cmd`): builds, assembles and archives a release; game specific values come from the profile's `packaging.json` and `project.json`.
- `SETUP-OTHER-PC.md`: guide for another PC (identical to `N:\DBD-UEEditor\docs\setup-other-machine.md`; not part of the release package).

Procedure: `N:\DBD-UEEditor\docs\installed-build-and-publishing.md`.
