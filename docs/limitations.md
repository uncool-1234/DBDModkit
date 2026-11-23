# Current limitations

Present state of gaps; nothing here is a plan.

## Generated types

- Game functions of generated classes are script stubs (empty bodies) unless the `DBDModkitGame` plugin registers a native implementation for them. Calls to the 25 stub functions do nothing.
- Jmap property values that name an object which does not exist at generation time keep the constructor's value (startup log: `unresolvedObjects`; a reference into a class default object is counted as `cdoInternal`). Stock engine classes' default objects are not changed.
- Jmap values of members the editor does not have (for example stock members deprecated in 5.7.4) are not applied.
- Values of instanced properties are applied only when every object reference in them lies inside the object being set (for example a class default object's own subobjects). A value with a reference to another object is not applied, and the property keeps the constructor's value.
- Jmap property values of a kind the editor's property cannot take (for example an enum constant the editor's enum lacks, such as `EDetailMode::DM_Lowest`) keep the constructor's value (startup log: `typeMismatch`, 1779 for DBD 10.2.2).
- Jmap property values that the editor's type cannot take keep the constructor's value (startup log: `typeMismatch`; for example `DM_Lowest` of `EDetailMode`, a constant the editor's enum lacks).
- Generated instances have no destructor-call property, and no `InitializationArchetype__<Class>` archetype is created.
- Disabled nested default subobjects of a native parent are not detected.
- Generated `UTexture` subclasses are constructible only through the engine `Texture.h` default bodies; they have no resource.
- Two Chaos cloth structs (`ChaosClothAssetLodTransitionDataCache`, `ChaosClothSimulationLodModel`) and four other stock structs that append data natively are generated as plain structs (reported at startup as natively serialized without struct ops): `ChooserPlayerSettings`, `CommonInputActionDataBase`, `SoftDataRegistryOrTable`, `OpenColorIODisplayConfiguration`.
- `FTableRowBase` casts in `CSVImportFactory.cpp` and `CompositeDataTable.cpp` are not guarded.
- Every editor start parses the jmap (about 9 s for DBD 10.2.2); every user needs the jmap of their game version.

## Functions

- Static functions of Blueprint function libraries that have no native implementation are not generated. A call to one aborts the script with a logged Blueprint exception ([troubleshooting.md](troubleshooting.md)).
- Five game functions have a different signature than the editor's and no native implementation: `MeshComponent::SetOverlayMaterial`, `PlayerController::ClientWasKicked`, `PlayerInput::SetBind`, and the delegate signatures `PlayMontageCallbackProxy::OnMontageEnded` and `OnMontageBlendingOut`. They keep the editor's signature.

## Blueprints

- 16-bit integers (and enums with a 16-bit underlying type) can only be read. A read copies 2 bytes into an int pin: int16 values are not sign-extended (-1 reads as 65535), and a read straight into an int variable keeps that variable's upper 2 bytes, so the variable must be 0 beforehand. There is no Set node, Make or Set Members pin for them, and function inputs and containers of 16-bit integers have no pin.
- Enums with a 2, 4 or 8 byte underlying type are plain integer pins without an enum dropdown. Unsigned 32 and 64 bit values show as signed.
- The Set Property By Name nodes do not handle unsigned integers or enums wider than a byte; on such a property they do nothing.
- Assets that use members exposed by the Blueprint exposure settings report compile errors in an editor where the settings are off.

## Schema

- Values of the roughly 160 game members that stock engine classes lack are read and discarded; the editor cannot show them.
- One schema override provider exists; it applies to game schemas only and shadows are never saved.
- Saving cooked assets back is not supported.

## Materials and shaders

- Cooked materials have no expression graph; the Material Editor shows the root node and cooked statistics only.
- `TCustomVS`, `FCustomNoDepthPS`, two BHVR shader pipelines and `FGPUCullingInstancedStaticMeshVertexFactory` load as null slots and are not rendered. Diagnostic code that dereferences shader pipeline lists outside the guarded functions (`GetShaderPipelineList`, `GetShaderList`, `GetOutdatedTypes`, `Validate` are null safe) is unaudited.
- Some materials on the APEX cloth vertex factory (`M_CAMPER`, `M_CAMPER_CUST`, `M_Slasher`, `M_Slasher_Burn`) log `Incomplete material X, missing (TShadowDepthPS...)`; they fall back to the default material.
- Lights whose cooked `FTranslucentLightingInjectPS` has another parameter layout do not light translucent surfaces through the translucency lighting volume.
- Whether cooked Niagara GPU emitters render correctly is not verified.
- The uniform buffer alias and the uniform buffer translation exist for D3D12 only. The translation supports a single GPU (no `-MaxGPUCount` above 1).
- Defaults for game uniform buffer members the editor lacks (black or white textures, a point sampler, zero constants) are verified on the sweeps (300 materials on a sphere), not on full game scenes.
- `BP_ST_Basement01` (default material shader map) and `BP_TL_St_2x2_Shrine_Hti` (native DestructibleMesh payload) load with logged errors.
- Static switches and base property overrides of a MIC with a cooked parent are not available.
- The MIC editor shows cooked parameters under "Global ..." groups (cooked data has no group names).

## Assets and editors

- Cooked Blueprints, AnimBPs and Widgets open as class-defaults Details tabs only: no Widget Designer, no graph editors (no Blueprint asset exists in cooked data).
- Cooked animations (AnimSequence, AnimMontage) have no animation data model. Persona plays them, but its timeline shows no curve, attribute or additive tracks. The curve and bone track edit actions (Remove Curves, Delete All Curves, add curve or metadata, Remove Bone Tracks, Re-zero) do nothing on them. Other Persona tools that read the data model (find and replace curves, the curve editor tab) are not guarded.
- Cooked skeletal meshes report no mesh description; the Persona LOD menu shows them as generated.
- Cooked Niagara systems and emitters open as read-only Details only ([profile-format.md](profile-format.md)).
- Cooked `/HairStrands` Dataflow templates (engine plugin content) hang their editor; this is stock editor behaviour with these engine assets.
- The package filter takes effect at the next editor start. A visible game package that imports a hidden one gets a null import unless a project asset exists at the hidden path. The Asset Loader resolves dependencies from package imports only (hard references); soft references are not followed.
- Cooking ([cooking.md](cooking.md)): project materials cook with shaders compiled by the editor; their use in the game is untested. A command line cook with an explicit `-PACKAGE`/`-COOKDIR` but without `-CookSkipRequests` includes engine packages the game does not contain. A copy of a cooked game StaticMesh does not cook ("Bad MeshDescription"): cooked meshes have no source mesh data.
- Reference Viewer dependency population from IoStore is not implemented. `FShaderMapResource::IsValidShaderIndex` call sites and the D3D12 root CBV skip are not added.
- A game update needs a new jmap and the layout steps of [game-update.md](game-update.md); the profile is validated for DBD 10.2.2 only.

## Packaging and tooling

- The installed build has no Debug/DebugGame/Test game configurations and no prebuilt DDC; symbols ship unstripped. It cannot rebuild engine modules from source; plugin sources are included for reference and plugin rebuilds with Visual Studio.
- No second game profile exists; the `game/dbd` `FShaderMapContent` field makes the installed build specific to DBD.
- `check-layers.ps1` is a text grep, not a parser.
- No tool detects or derives a changed container cipher or pak footer; a game update that changes them shows only as containers that fail to mount. The reference is CUE4Parse ([container-cipher-mounting.md](container-cipher-mounting.md)).
- The `FShaderMapContent` field is compiled into the engine (`game/dbd`). Uniform buffer layouts are profile data, but a new game version needs a minidump and `oatmealf-5.7` to regenerate them, so a jmap alone does not give a working editor for a game version whose layouts differ. Only additive layout changes can be translated.
- No tool lists the cooked uniform buffer layout hashes or memory image type layouts offline; a layout difference is found through the `oatmealf-5.7` report and the editor log ([game-update.md](game-update.md)).
- Editor sweeps cannot run in parallel.
