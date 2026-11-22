# Container cipher and mounting

The game ships 307 IoStore containers (`.utoc/.ucas`), 307 `.pak` files and `global.utoc` under `<GameRoot>\DeadByDaylight\Content\Paks`. The editor reads them in place; nothing is copied or modified. Stock tools (retoc, UnrealPak) cannot read them because the directory index uses a custom cipher.

## Cipher (data driven, `engine.ini`)

| Container part | Pipeline | Detail |
|---|---|---|
| IoStore directory index | `IoStoreDirectoryIndex=Xor:TocHeader:104:36;Aes` | XOR with the 36 bytes at `.utoc` header offset 104 (`Toc.Header.Reserved8`, cyclic), then the stock AES-256 decryption; applied to a copy of the buffer |
| IoStore chunk data | stock | plain AES-256 |
| `global.utoc` | none | not encrypted |
| Pak index | `PakIndex=Aes;Xor:FooterCustom` | stock AES decryption, then XOR with the 28 byte footer custom field; the SHA1 of the result equals `IndexHash` |
| Pak footer | `PakFooterVariant=...` | field order in the file: `Guid16;Encrypted1;Magic4;Version4;IndexOffset8;IndexSize8;IndexHash20;Custom28;U32;CompressionNames5x32`; the stock parser runs when the variant parse fails |

`ModkitCore.cpp` builds a `FPipelineCipher` from these keys and registers it as the container cipher. The registry is sealed at the first container mount.

## Reference for the cipher

The pipeline values are a transcription of CUE4Parse's DBD support, `CUE4Parse\CUE4Parse\GameTypes\DBD\Encryption\Aes\DBDAes.cs` in the clone at the workspace root (upstream `FabianFG/CUE4Parse`). That file is the reference when a game update makes containers fail to mount: pull the clone and compare.

| `DBDAes.cs` | `engine.ini` |
|---|---|
| IoStore index key: first 36 bytes of `TocResource.Header.CustomGameData`; XOR, then AES | `IoStoreDirectoryIndex=Xor:TocHeader:104:36;Aes` (`CustomGameData` is the stock `Reserved8` field at header offset 104) |
| Pak index key: `Info.CustomEncryptionData`, 28 bytes; AES, then XOR | `PakIndex=Aes;Xor:FooterCustom` |
| Pak footer read (`CUE4Parse\CUE4Parse\UE4\Pak\Objects\FPakInfo.cs`, the `GAME_DeadByDaylight` branch reading 28 bytes) | `PakFooterVariant=...` |
| non-index data: AES only | stock |

A pipeline is correct when, for a real container, the decrypted IoStore directory index starts with the mount point string `../../../` and the SHA1 of the decrypted pak index equals the footer's `IndexHash`. Both checks need only the key file and one `.utoc` or `.pak`; the editor log shows the same failures as index errors at mount.

## Key

The AES-256 key is a text file the user supplies: one line, `0x` plus 64 hex digits (the repository never contains it; `DeadByDaylight-Data\DBD-AES.txt` is the user's own copy and is gitignored). Lookup order: `-ModkitKeyFile=<file>`, env `MODKIT_AES_KEY_FILE`, `[Local] KeyFile=`, `<Project>/ModkitAesKey.txt`. Only the file path appears in configuration and logs; the value is never logged. The pak encryption key delegate is bound only when the modkit is active and a key was read. Without a valid key, container mounting is disabled (`LogModkit: Warning: Modkit: no valid AES key; container mounting disabled.`) and the editor starts without the game content; the pak reader would otherwise assert on the first encrypted container.

## Mount sequence

1. `IPlatformFilePak`: reads the config, adds `PaksDir` (the first `PaksSubdir` under `GameRoot` containing a `ProbeFile`), implies `-UsePaks`, binds the key delegate, mounts `GlobalToc`.
2. Footer parse and index decryption through the cipher; stock path as fallback.
3. The first mount happens in `LaunchCheckForFileOverride`; plugin modules of phase `EarliestPossible` load later.
4. Plugin content roots: `PluginScanRoot` is scanned for `.uplugin` files and each plugin is mounted as `/<Plugin>/` (238 for DBD 10.2.2) with its local folder in the project: `<Project>/Plugins/<plugin folder relative to PluginScanRoot>/Content/`. The `.uplugin` files are read from the mounted paks. Each such local folder, and the project `Content/` folder paired with `[ContentMounts] GameContentDir`, is recorded as a container directory: a cooked file that is read by path (a `UFontFace`'s `.ufont`) and is missing in the project folder resolves to the same relative path inside the container (`Modkit::ResolveContainerFilename`).
5. The premade registry (96,267 assets) is loaded when `[AssetRegistry] UsePremade=true`. The candidates are `<Project>/EditorClientAssetRegistry.bin`, `<Project>/AssetRegistry.bin` and then each `[AssetRegistry] PakPath` (`../../../DeadByDaylight/AssetRegistry.bin`, an entry of `pakchunk0`); the first that exists wins, so a loose file in the project overrides the pak entry. Packages hidden by the package filter are removed from it ([asset-loader.md](asset-loader.md)).
6. The shader library is opened after `GEngine->Init`, before `OnPostEngineInit`.

Expected log: 307 `Mounted IoStore container` and 307 `Mounted Pak file` lines plus the global container, `Premade AssetRegistry loaded`, `opened shader library 'DeadByDaylight': yes`.

## Limitations

A game plugin cannot register a container cipher before the first mount; DBD uses the pipeline cipher from `engine.ini`.
