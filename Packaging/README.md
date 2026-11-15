# Packaging: installed build of the modkit engine

- `build-installed.cmd`: the BuildGraph command that produces the installed engine (environment variables `BUILD_SRC`, `OUT_DIR`, `LOG_DIR`, `UBA_HOST`). The source is a copy of the `game/dbd` tree without `.git`/`Intermediate`/`Saved`, with this repository's `Suzie` and `Profiles/DBD/Plugin/DBDModkitGame` copied to `Engine\Plugins\Modkit\Suzie` and `Engine\Plugins\Modkit\DBDModkitGame`. When `pdbcopy.exe` is unavailable, the `<Strip ...>` step of the build copy's `Engine/Build/InstalledEngineBuild.xml` is replaced by a `<Copy ...>` step (symbols ship unstripped).
- The engine filter drops non-code plugin folders: copy `Suzie\Profiles` and `Suzie\Tools` of this repository into `Windows\Engine\Plugins\Modkit\Suzie\` of the installed build.
- `DBDMount-Template/`: content-only project for the installed engine (no Source, no machine paths).
- `SETUP-OTHER-PC.md`: guide for another PC (identical to `N:\DBD-UEEditor\docs\setup-other-machine.md` and `N:\DBD-UEEditor-Installed\SETUP-OTHER-PC.md`).

Procedure: `N:\DBD-UEEditor\docs\installed-build-and-publishing.md`.
