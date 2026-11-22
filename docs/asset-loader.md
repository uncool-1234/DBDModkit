# Asset Loader (game asset filter)

The editor can hide game packages, so that a project asset can take a game asset's path. The common case: a material instance parented to a game material, saved at the path of a game material instance, replaces that instance for every mesh that uses it.

The engine reads a package filter once at startup; the Suzie Asset Loader window writes it. A change takes effect at the next editor start.

## Window

Toolbar button **Asset Loader** (level editor toolbar, User section; the tooltip shows the current mode and package count), or `Suzie.AssetLoader.Open`. Modal window "Choose assets to load":

| Mode | Loads | Left list ("Game assets") | Right list |
|---|---|---|---|
| All | every game asset | disabled | "Will load": every game asset |
| Only selected | the checked assets, plus their dependencies when **Load dependencies** is on | checkboxes | "Will load": the checked assets (dependencies are added at Apply and not listed) |
| All except selected | every game asset except the checked ones | checkboxes | "Will not load" |
| None | no game assets | disabled | "No game assets will load" |

- The left list holds every package of the game's premade asset registry (Name, Path, Type columns, search on name or path). Space or the context menu toggles the checks of the selected rows. The right list has a remove button per row and its own search. Counts read "M of N items" while a search is active.
- **Load dependencies** applies to Only selected; it is disabled in the other modes.
- Apply is disabled in Only selected with nothing checked (tooltip: "Select at least one asset, or choose None.").
- Apply writes both files below. When the result differs from the filter the editor started with, a prompt offers to restart; the restart goes through the editor's own restart (unsaved packages are offered for saving, the command line is kept).
- The window reads its own copy of the premade registry, so hidden packages stay listed and can be selected again.

## Dependencies

The cooked premade registry carries no dependency data. A package's dependencies are the imported packages of its package store entry (every package the loader must load first: parent materials, textures, material functions, parameter collections), followed recursively. The window reads them past the filter (`Modkit::FPackageFilterBypassScope`), so the closure is the same whatever filter is active. Example (DBD 10.2.2): `SK_SlushMachineIndoor01_REF` resolves to 30 packages, its material instance `MI_SlushMachine01` to 21. `Suzie.AssetLoader.Closure <long package name>` prints a closure (size and the first 20 members).

## Files (`<Project>\ModkitData`)

`AssetFilter.txt` is what the engine reads. Absent file = all packages visible.

```
; comments start with ; or #
Mode=AllowList          ; first non-comment line: Off, AllowList or DenyList
/Game/Materials/Masters/Deprecated_Basic/M_Basic_Emmisive
/Game/Textures/Props/Misc/T_SlushMachine01_BC
```

- AllowList: only the listed packages are visible. DenyList: the listed packages are hidden. Off: no filtering.
- One long package name per line; other lines are skipped with a warning. A missing or unknown `Mode` line means Off.
- Written by the window as: All → `Mode=Off`; None → `Mode=AllowList` with no lines; Only selected → `Mode=AllowList` with the checked packages (and their dependency closure when Load dependencies is on); All except selected → `Mode=DenyList` with the checked packages.

`AssetLoader.json` keeps the window's state (the engine does not read it):

```json
{ "mode": "OnlySelected", "load_dependencies": true, "selected": ["/Game/..."] }
```

`mode` is `All`, `OnlySelected`, `AllExceptSelected` or `None`. Without this file the window takes its initial state from `AssetFilter.txt`.

## Engine behaviour

The filter is read in `Misc/ModkitCore.cpp` while the modkit state is built, before the first container is mounted; afterwards it is read only and lock free. Log line: `Modkit: package filter '<file>': mode <Mode>, <n> packages listed.` A hidden package:

- is reported absent by the IoStore dispatcher (`DoesChunkExist` for its export bundle chunk), so `FPackageName::DoesPackageExist` is false and a loose project package at that path is used instead;
- has no package store entry (`FFilePackageStoreBackend::GetPackageStoreEntry` returns Missing);
- is removed from the premade asset registry after it is loaded (log: `Modkit: package filter removed <n> of <m> packages from the premade asset registry.`), so the Content Browser does not show it.

A visible package that imports a hidden one loads with that import null, unless a project asset exists at the hidden path.

Switches: `-ModkitAssetFilter=<file>` reads another filter file; `-ModkitAllAssets` ignores the filter (escape hatch when a filter hides too much). `Suzie.AssetFilter [<package>...]` prints the active filter and, per package, whether it is hidden, in the live registry, found by `DoesPackageExist`, and loaded from IoStore or as an uncooked file.

## Replacing a game material instance

1. Asset Loader: All except selected, check the game material instance, Apply, restart.
2. Create a Material Instance at the same path (folder and name), parent it to the game material, change parameters, save.
3. Meshes that use the game instance now load yours. Cook the replacement with the filter still active ([cooking.md](cooking.md)) and package it with the mod.
