# Game update

The golden dump, the gate values, the profile's `uniform_layouts.txt` and the `game/dbd` field are valid for one game version (DBD 10.2.2). Unversioned cooked data desynchronizes on any other version. This page lists what changes for a new game version, in order, and the tool for each step.

## Inputs (user supplied)

| Input | Used by | Notes |
|---|---|---|
| game install of the new version | editor | `[Local] GameRoot=` |
| AES key file | editor | `[Local] KeyFile=`; only the path is handled |
| `.jmap` of the new version | Suzie at every editor start | `[Local] Jmap=` or `-SuzieJmap=`; [jmap-usmap.md](jmap-usmap.md) |
| full-memory minidump (`.DMP`) of the running game | `oatmealf` | uniform buffer layouts (developer input); [jmap-usmap.md](jmap-usmap.md) |

## Steps

| # | Step | Tool | Result / check |
|---|---|---|---|
| 1 | Mount | start the editor | the mount counts of 10.2.2 are 307 + 307. `0 containers` or index errors: [container-cipher-mounting.md](container-cipher-mounting.md) |
| 2 | Asset registry | none; read from the mounted pak ([setup-other-machine.md](setup-other-machine.md) section 5) | `Premade AssetRegistry loaded from ...` in the log |
| 3 | New jmap | put the jmap in `<Project>\ModkitData` and restart the editor (a new file name also needs the `Jmap=` line of `ModkitLocal.ini` changed) | types, schema recipes and gameplay tags follow from the jmap ([native-type-generation.md](native-type-generation.md)); the log shows the `GENERATE OK` summary |
| 4 | Uniform buffer layouts | `oatmealf-5.7` (below) | new `Profiles\DBD\uniform_layouts.txt` (`[profile:dbd]` commit); no engine build |
| 5 | Memory image layouts | editor log (below) | `[ShaderLayout] TolerateMismatch` entries, `game/dbd` fields |
| 6 | Gates | `Suzie-fork\Tools\sweep\run_gates.ps1` ([sweeps-and-verification.md](sweeps-and-verification.md)) | new gate values, new golden dump (`Suzie.DumpAll`) |
| 7 | Version text | `profile.json` `description`, the comment in `engine.ini`, the numbers in the docs | |

Step 3 needs no tool: the schema recipes change when the game adds or removes members of engine classes, and the startup counters (`types/shadows/skipped`) follow. A struct that the game serializes natively needs struct ops in the game plugin; the editor reports such structs at startup ([native-type-generation.md](native-type-generation.md)), the symptoms of a missing one are in [troubleshooting.md](troubleshooting.md).

## Uniform buffer layouts (step 4)

A cooked shader stores the layout hash of every uniform buffer it binds; the hash covers the member list of the buffer's parameter struct. [oatmealf](https://github.com/uncool-1234/oatmealf) (Rust, folder `oatmealf-5.7` of the layout, `README-5.7.md`) reads the registered layouts from a game minidump and from a running stock editor and compares them; its second binary `uniform_layouts` writes the differing layouts as the profile file `uniform_layouts.txt`, which the engine translates to at run time ([cooked-materials-shaders.md](cooked-materials-shaders.md)).

```
oatmealf --capture-only --save-editor-layouts <editor-layouts.json>
oatmealf --capture-only --game-minidump <game>.DMP --save-game-layouts <game-layouts.json> -v
oatmealf --game-layouts <game-layouts.json> --editor-layouts <editor-layouts.json> --engine-root <engine source root> -o Generated -v
uniform_layouts <game-layouts.json> <editor-layouts.json> <profile dir>\uniform_layouts.txt
```

- Build: `cargo build --release` in `oatmealf-5.7` (exes `target\release\oatmealf.exe` and `uniform_layouts.exe`).
- The editor capture reads the process `UnrealEditor.exe` and must come from a STOCK 5.7.4 editor: the `editor` hashes in the data file are the stock layout hashes.
- The third command is a report: `Generated\<timestamp>\report.md` (per layout: game hash, editor hash, member changes), `manifest.json`, `exports\`, and copies of the stock sources with the changes applied (reference only). oatmealf recomputes each layout hash from the captured members; `N/N changed layouts verified` means the captures are consistent. A layout the report lists as not loaded in the editor exists only in the game (`GPUCulling`) and needs no translation.
- `uniform_layouts` prints `exported N layouts`. At editor start the log shows `Uniform buffer translations: N of N layouts registered`; any layout the loader refuses logs an error with its name. Only additive changes translate: a game layout that drops or retypes an editor member needs an engine change on `game/dbd`.
- A layout that differs and has no translation is covered at run time by `AliasUniformBuffers=true` (the cooked hash is registered as an alias of the editor buffer of the same name, log `aliased cooked uniform buffer layout hash`); the alias maps the hash only and does not change the editor's member layout ([cooked-materials-shaders.md](cooked-materials-shaders.md)).

## Memory image layouts (step 5)

Frozen shader map content is checked against the editor's type layouts (name, size, field offsets, SHA1).

- A mismatch on a type listed under `[ShaderLayout] TolerateMismatch` logs `Modkit: tolerating layout hash mismatch for type <T>`. `-ModkitTolerateAllLayoutMismatch` extends this to every type; `-ModkitStrictLayoutHash` disables it.
- For 10.2.2 the mismatches of `FMaterialShaderMapContent`, `FMeshMaterialShaderMap` and `FGlobalShaderMapContent` derive from their base `FShaderMapContent`, which is 8 bytes larger in the game; `game/dbd` adds a `uint64` after `ShaderPlatformName` (`git show e0f4eb2be`), which makes the sizes equal.
- The tolerance skips the hash comparison only; it does not adapt sizes or offsets. A size difference is matched by a field on `game/dbd`.
