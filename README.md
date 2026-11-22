# DBDModkit: Dead by Daylight cooked content in the Unreal Editor

Opens Dead by Daylight's cooked assets in the Unreal Engine 5.7.4 editor. A modified engine mounts the game's encrypted IoStore/pak containers and loads the game's shader library, so cooked materials render with the game's compiled shaders (parameter edits through material instances). The Suzie plugin generates the game's native classes in memory, so Blueprints, AnimBPs and widgets load. The editor only reads the game; the game is never run.

This repository holds the Dead by Daylight specific parts: the profile (game data the engine and Suzie read), the game plugin, the packaging scripts and the documentation.

Dead by Daylight and its assets belong to Behaviour Interactive. This repository contains no game files and no encryption key.

## What you need

- Your own install of the game, version 10.2.2.
- The game's AES key, in a text file (one line, `0x` plus 64 hex digits).
- The game's jmap for that version ([docs/jmap-usmap.md](docs/jmap-usmap.md)).
- For building from source: access to Unreal Engine source on GitHub (an Epic Games account linked to GitHub), Visual Studio for UE 5.7, and about 350 GB of free disk space.

## Repositories

| Repository | Content |
|---|---|
| [uncool-1234/DBDModkit](https://github.com/uncool-1234/DBDModkit) (this one) | profile `Profiles/DBD`, game plugin `Profiles/DBD/Plugin/DBDModkitGame`, packaging `Packaging`, dev project `DBDMount`, docs, tools |
| [uncool-1234/UnrealEngine-dbd](https://github.com/uncool-1234/UnrealEngine-dbd) | the engine: Unreal Engine 5.7.4 with the modkit hooks (branch `modkit-core`) and the game's struct change (branch `game/dbd`, the one to build). Visible only with Unreal Engine source access. Its `MODKIT.md` describes the changes. |
| [uncool-1234/Suzie](https://github.com/uncool-1234/Suzie) | the editor plugin that generates the game's native types from the jmap |
| [uncool-1234/oatmealf](https://github.com/uncool-1234/oatmealf) | the tool that produces `Profiles/DBD/uniform_layouts.txt` for a new game version |

## Folder layout

The scripts and docs expect one folder that is a clone of this repository, with the other repositories cloned into it under fixed names. Git ignores those subfolders here.

| Folder | What |
|---|---|
| `.` | this repository |
| `UnrealEngine-5.7.4-fork` | clone of UnrealEngine-dbd, branch `game/dbd` |
| `Suzie-fork` | clone of Suzie |
| `oatmealf-5.7` | clone of oatmealf (only to regenerate `uniform_layouts.txt`) |
| `DBDMount` | dev project: `DBDMount.uproject` and `Source` are tracked here; `Config`, `ModkitData` and the plugin links are local |

```powershell
git clone https://github.com/uncool-1234/DBDModkit.git DBDModkit
cd DBDModkit
git clone -b game/dbd https://github.com/uncool-1234/UnrealEngine-dbd.git UnrealEngine-5.7.4-fork
git clone https://github.com/uncool-1234/Suzie.git Suzie-fork
.\tools\setup-dev-project.ps1
```

`tools\setup-dev-project.ps1` copies the template's `Config` into `DBDMount` when it has none and links `DBDMount\Plugins\Suzie` to `Suzie-fork` and `DBDMount\Plugins\DBDModkitGame` to `Profiles\DBD\Plugin\DBDModkitGame` (directory junctions).

## Build and run (from source)

1. Run `Setup.bat` once in `UnrealEngine-5.7.4-fork` (downloads the engine's binary dependencies), then build the editor and the shader compiler ([docs/engine-fork.md](docs/engine-fork.md)).
2. Put the key file and the game's jmap in `DBDMount\ModkitData` (one file per extension).
3. Double-click `DBDMount\DBDMount.uproject`. When a path is missing, the **Modkit project setup** window opens: choose the game folder; the key file and the jmap are filled in from `ModkitData`. `Save and restart` writes `DBDMount\ModkitData\ModkitLocal.ini`, the only file with absolute paths ([docs/profile-format.md](docs/profile-format.md)):

```ini
[Local]
Profile=<this repository>/Profiles/DBD     ; the profile FOLDER (contains profile.json and engine.ini)
GameRoot=<game install root>
KeyFile=<path of your AES key file>
Jmap=<path of the game's jmap>
```

The first start compiles SM5 global shaders (15 to 30 minutes). `Jmap=` is required: without it Suzie generates nothing. The gameplay tags come from the jmap ([docs/tags.md](docs/tags.md)); the game's `AssetRegistry.bin` is read from the mounted containers. Without a profile, or with `-DisableModkit`, the editor behaves as stock UE 5.7.4.

An installed engine build (no source build on the user's PC) is made with `Packaging\publish-engine.cmd` ([docs/installed-build-and-publishing.md](docs/installed-build-and-publishing.md)); its users follow [docs/setup-other-machine.md](docs/setup-other-machine.md). Engine binaries may be given only to people who accepted the Unreal Engine EULA.

To place your own asset at a game asset's path (for example a material instance that replaces a game material instance), hide the game asset with the **Asset Loader** toolbar button and restart the editor: [docs/asset-loader.md](docs/asset-loader.md).

## Documentation

- Architecture, hooks, layers: [docs/architecture.md](docs/architecture.md)
- Switches, ini keys, console commands: [docs/profile-format.md](docs/profile-format.md)
- Choosing which game assets load: [docs/asset-loader.md](docs/asset-loader.md)
- Cooking your assets (game content is referenced, not cooked): [docs/cooking.md](docs/cooking.md)
- Engine branches and building: [docs/engine-fork.md](docs/engine-fork.md)
- A new game version: [docs/game-update.md](docs/game-update.md)
- Testing: [docs/sweeps-and-verification.md](docs/sweeps-and-verification.md)
- Problems: [docs/troubleshooting.md](docs/troubleshooting.md); limits: [docs/limitations.md](docs/limitations.md)
- Orientation for AI coding agents working in this layout: [AGENTS.md](AGENTS.md)

## License

MIT ([LICENSE](LICENSE)). The engine fork is under the Unreal Engine EULA; Suzie and oatmealf have their own MIT licenses.
