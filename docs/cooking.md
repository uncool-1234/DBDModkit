# Cooking project content

A project's own assets cook with the stock cook commandlet. Game content is never cooked: with the modkit active, the cooker records every package of the mounted containers as cooked by the base game, so project assets reference game assets by path and the game resolves them to its own packages.

## From the editor

`Platforms > Windows > Cook Content` cooks the project content. Output, key and DDC are the editor's; the result is the same as the command line below.

- Scope: the Project Settings > Packaging > "Additional Asset Directories to Cook" entries inside the project folder (`/Game/...` and game plugin roots such as `/K01`). Without such entries: the whole Content folder plus each game plugin folder under `<Project>/Plugins` that holds a package. Entries outside the project folder (engine plugins add their own) are ignored.
- Every asset in that scope must cook: an asset that references a package that is neither in the mounted game nor in the project fails the cook with "Content is missing from cook".
- The editor passes `-VersionCookedContent` to UAT (versioned packages, tagged properties).

## Command line

```
<Engine>\Engine\Binaries\Win64\UnrealEditor-Cmd.exe "<Project>\<Project>.uproject" -run=cook -targetplatform=Windows -unattended -d3d12 -sm5 -ModkitKeyFile=<key file path> -CookSkipRequests -COOKDIR=<Project>\Content\<folder> [-COOKDIR=...] [-PACKAGE=/Game/...]
```

- Without `-MAP`, `-PACKAGE`, `-COOKDIR` or `-COOKALL`, the cook takes the editor's scope above and applies `-CookSkipRequests` by itself (log line `Modkit: no cook request given; cooking <n> project content folder(s) ...`).
- `-COOKDIR` takes a file system folder (`-COOKDIR=/Game/...` cooks nothing); `-PACKAGE` takes a long package name. Both may repeat. Project assets referenced by the requested ones are cooked too.
- `-CookSkipRequests` drops the packages the cooker adds on its own: the editor's startup packages (editor materials, engine plugin content), the default and always-cook maps of the project settings, and their dependencies. Without it, about 60 `/Engine` and engine plugin packages that the game does not contain land in the output.
- The key file path and the DDC are the ones the editor uses (`ModkitLocal.ini` `KeyFile`; environment `UE-LocalDataCachePath=<Project>\DDC`, which the engine sets for every project it opens, unless the variable is already set).
- Output: `<Project>\Saved\Cooked\Windows\<Project>\Content\...` for `/Game`, `<Project>\Saved\Cooked\Windows\<Project>\Plugins\<category>\...\<Plugin>\Content\...` for assets saved under a game plugin root (`.uasset` + `.uexp`, loose, not IoStore). `AssetRegistry.bin` there lists the cooked project packages only; `Metadata\DevelopmentAssetRegistry.bin` also lists the base game packages.

Log line: `Modkit: <n> packages from mounted containers recorded as base game (<s> skipped: no mount point), <ms> ms.` (DBD 10.2.2: 185028 packages, 0 skipped, about 3 s.)

## Base game packages

`UCookOnTheFlyServer::RecordModkitMountedPackagesAsBaseGame` (`CookOnTheFlyServer.cpp`) runs at the start of a cook by the book when `Modkit::IsActive()`:

- Candidates are the packages of the live asset registry; a package is recorded when its export bundle chunk exists in the IoStore dispatcher. The editor's own loose content is not in IoStore, and the package filter removes the chunks of hidden packages.
- Recorded packages get a cooker package data marked cooked with `EWhereCooked::BaseGame` (`FPackageDatas::AddExistingPackageDatasForPlatform`, the DLC base-release state) and are declared to the EDL import checker, so imports of them are neither cooked nor reported as missing content.
- They are left out of the cooked `AssetRegistry.bin`, as for DLC cooks.

Game plugin content (`/S05`, `/K01`, ...) is included: the game plugin content roots are registered in commandlets as in the editor ([architecture.md](architecture.md)), so project assets reference plugin packages the same way as `/Game` packages.

## Replacing a game asset

A replacement under a game plugin root is saved in `<Project>/Plugins/<category>/.../<Plugin>/Content/`. A project asset at a game asset's path cooks only while the Asset Loader hides the game asset (All except selected, [asset-loader.md](asset-loader.md)); otherwise that path counts as base game and the asset is not cooked. With `-ModkitAllAssets` every game path counts as base game.
