# Packaging: installed build of the modkit engine

* `build-installed.cmd`: the exact BuildGraph command of the successful run (build 8 on the build PC; source = a copy of the `game/dbd` tree without `.git`/`Intermediate`/`Saved` in `N:\DBD-UEEditor-BuildSrc`, with this repository's `Suzie` and `Profiles/DBD/Plugin/DBDModkitGame` copied to `Engine\Plugins\Modkit\Suzie` and `Engine\Plugins\Modkit\DBDModkitGame`).
  Local edit of the build copy of `Engine/Build/InstalledEngineBuild.xml` (not committed to the fork): line 1150 `<Strip Files="#Strip Tools for Installed Win64" ...>` replaced by `<Copy Files="#Strip Tools for Installed Win64" From="$(RootDir)" To="$(LocalInstalledDir)" Tag="#Installed Build Win64 Files"/>` because `pdbcopy.exe` (Windows Debugging Tools) is not installed; together with `-set:WithFullDebugInfo=true` this ships unstripped symbols.
* After the build the engine filter drops non-code plugin folders: copy `Suzie\Profiles` and `Suzie\Tools` of this repository into `Windows\Engine\Plugins\Modkit\Suzie\` of the installed build.
* `DBDMount-Template/`: content-only project for the installed engine (no Source, no machine paths).
* `SETUP-OTHER-PC.md`: guide for another PC.
