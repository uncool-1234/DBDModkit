# DBD cooked-content modkit (UE 5.7.4 fork + Suzie)

Opens Dead by Daylight's cooked assets in the Unreal Engine 5.7.4 editor: the engine mounts the game's encrypted IoStore/pak containers, loads the game's shader library so cooked materials render with the game's compiled shaders (parameter edits through material instances), and the Suzie plugin generates the game's native classes in memory so Blueprints, AnimBPs and widgets load. The editor only reads the game; the game is never run.

You provide: your own game install (version 10.2.2), the AES key in a text file, and the jmap of that game version ([docs/jmap-usmap.md](docs/jmap-usmap.md)). Suzie reads the jmap at every editor start. The key file and the jmap go in the project's `ModkitData` folder; the editor's setup window writes the machine local paths.

## Parts

| Part | Where |
|---|---|
| Engine, generic hooks | `UnrealEngine-5.7.4-fork`, branch `modkit-core` |
| Engine, DBD struct field | same repo, branch `game/dbd` (the build tree) |
| Suzie plugin | `Suzie-fork\Source` |
| DBD profile and game plugin | `Profiles\DBD`, `Plugin\DBDModkitGame` |
| Dev project | `DBDMount` |
| Installed engine for other PCs | the release package built by `Packaging\publish-engine.cmd` ([docs/setup-other-machine.md](docs/setup-other-machine.md), [docs/installed-build-and-publishing.md](docs/installed-build-and-publishing.md)) |

## Configure a project (dev tree)

1. Put the key file (`*.txt`, one line: `0x` + 64 hex digits) and the game's jmap (`*.jmap`) in `DBDMount\ModkitData`, one file per extension.
2. Double-click `DBDMount.uproject`. When a path is missing, the `Modkit project setup` window opens: choose the game folder; the key file and the jmap are filled in from `DBDMount\ModkitData`. `Save and restart` writes `DBDMount\ModkitData\ModkitLocal.ini` (the only file with absolute paths, gitignored; it keeps its other keys and comments) and restarts the editor. Only the path of the key file is stored ([docs/profile-format.md](docs/profile-format.md)).

```ini
[Local]
Profile=N:/DBD-UEEditor/Profiles/DBD     ; the profile FOLDER (contains profile.json and engine.ini), not profile.json
GameRoot=<game install root>
KeyFile=<path of your AES key file>
Jmap=<path of the game's jmap>
```

3. `Jmap=` is required: without it Suzie generates nothing. The gameplay tags come from the jmap automatically ([docs/tags.md](docs/tags.md)). The game's `AssetRegistry.bin` is read from the mounted pak (profile `[AssetRegistry] PakPath`); no extraction.
4. `DBDMount\Plugins\Suzie` is a junction to `Suzie-fork`, `DBDMount\Plugins\DBDModkitGame` to `Profiles\DBD\Plugin\DBDModkitGame`; both plugins are enabled in `DBDMount.uproject`.
5. `Config\DefaultEngine.ini` project settings and the `-d3d12 -sm5` launch: [docs/profile-format.md](docs/profile-format.md).

To place your own asset at a game asset's path (for example a material instance that replaces a game material instance), hide the game asset with the **Asset Loader** toolbar button and restart the editor: [docs/asset-loader.md](docs/asset-loader.md).

Open the project by double-clicking `DBDMount\DBDMount.uproject` (first start compiles SM5 global shaders, 15 to 30 minutes). Without a selected profile, or with `-DisableModkit`, the editor behaves as stock UE 5.7.4.

## Where to read next

- Architecture, hooks, layers: [docs/architecture.md](docs/architecture.md)
- Switches, ini keys, console commands: [docs/profile-format.md](docs/profile-format.md)
- Choosing which game assets load: [docs/asset-loader.md](docs/asset-loader.md)
- Cooking your assets (game content is referenced, not cooked): [docs/cooking.md](docs/cooking.md)
- Build, branches: [docs/engine-fork.md](docs/engine-fork.md)
- Testing: [docs/sweeps-and-verification.md](docs/sweeps-and-verification.md)
- Problems: [docs/troubleshooting.md](docs/troubleshooting.md); limits: [docs/limitations.md](docs/limitations.md)
- Project orientation for agents: [AGENTS.md](AGENTS.md)
