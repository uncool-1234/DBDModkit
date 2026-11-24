// Stand-in shader types for the game's custom pass. Every cooked game mesh shader map holds the pipelines CustomNoDepthPipeline
// (TCustomVS + FCustomNoDepthPS) and CustomNoPixelPipeline (TCustomVS); the cooker compiles them through these types.
// The C++ class names are part of the type names and the layout hashes, so they must equal the game's names.
// Only cooks compile the stages (ShouldCompilePermutation), so editor shader maps are unchanged.

#include "CoreMinimal.h"
#include "CoreGlobals.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/Paths.h"
#include "Modules/ModuleManager.h"
#include "MaterialShaderType.h"
#include "MeshMaterialShader.h"
#include "MeshMaterialShaderType.h"
#include "Serialization/MemoryLayout.h"
#include "ShaderCore.h"
#include "VertexFactory.h"

DEFINE_LOG_CATEGORY_STATIC(LogDbdModkitGameShaders, Log, All);

class TCustomVS : public FMeshMaterialShader
{
	DECLARE_SHADER_TYPE(TCustomVS, MeshMaterial);
protected:
	TCustomVS() {}

	TCustomVS(const FMeshMaterialShaderType::CompiledShaderInitializerType& Initializer) :
		FMeshMaterialShader(Initializer)
	{}

public:
	static bool ShouldCompilePermutation(const FMeshMaterialShaderPermutationParameters& Parameters)
	{
		return IsRunningCookCommandlet() && !Parameters.VertexFactoryType->SupportsNaniteRendering();
	}

	static void ModifyCompilationEnvironment(const FMaterialShaderPermutationParameters& Parameters, FShaderCompilerEnvironment& OutEnvironment)
	{
		FMeshMaterialShader::ModifyCompilationEnvironment(Parameters, OutEnvironment);
	}
};

class FCustomNoDepthPS : public FMeshMaterialShader
{
	DECLARE_SHADER_TYPE(FCustomNoDepthPS, MeshMaterial);
public:
	static bool ShouldCompilePermutation(const FMeshMaterialShaderPermutationParameters& Parameters)
	{
		return IsRunningCookCommandlet() && !Parameters.VertexFactoryType->SupportsNaniteRendering();
	}

	FCustomNoDepthPS(const FMeshMaterialShaderType::CompiledShaderInitializerType& Initializer) :
		FMeshMaterialShader(Initializer)
	{}

	static void ModifyCompilationEnvironment(const FMaterialShaderPermutationParameters& Parameters, FShaderCompilerEnvironment& OutEnvironment)
	{
		FMeshMaterialShader::ModifyCompilationEnvironment(Parameters, OutEnvironment);

		OutEnvironment.SetDefine(TEXT("ALLOW_DEBUG_VIEW_MODES"), AllowDebugViewmodes(Parameters.Platform));

		const bool bIsSingleLayerWater = Parameters.MaterialParameters.ShadingModels.HasShadingModel(MSM_SingleLayerWater);
		OutEnvironment.SetDefine(TEXT("SCENE_TEXTURES_DISABLED"), bIsSingleLayerWater ? 0u : 1u);
	}

	FCustomNoDepthPS() {}
};

IMPLEMENT_MATERIAL_SHADER_TYPE(, TCustomVS, TEXT("/Plugin/DBDModkitGame/Private/CustomPassVertexShader.usf"), TEXT("Main"), SF_Vertex);
IMPLEMENT_MATERIAL_SHADER_TYPE(, FCustomNoDepthPS, TEXT("/Plugin/DBDModkitGame/Private/CustomPassPixelShader.usf"), TEXT("Main"), SF_Pixel);

IMPLEMENT_SHADERPIPELINE_TYPE_VSPS(CustomNoDepthPipeline, TCustomVS, FCustomNoDepthPS, true);
IMPLEMENT_SHADERPIPELINE_TYPE_VS(CustomNoPixelPipeline, TCustomVS, true);

class FDbdModkitGameShadersModule : public IModuleInterface
{
public:
	virtual void StartupModule() override
	{
		TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("DBDModkitGame"));
		if (Plugin.IsValid())
		{
			AddShaderSourceDirectoryMapping(TEXT("/Plugin/DBDModkitGame"), FPaths::Combine(Plugin->GetBaseDir(), TEXT("Shaders")));
		}

		FPlatformTypeLayoutParameters EditorParams;
		EditorParams.InitializeForCurrent();
		FPlatformTypeLayoutParameters CookedParams;
		CookedParams.InitializeForPlatform(TEXT("Windows"), false);

		auto LogLayout = [&](const TCHAR* Name, const FTypeLayoutDesc& Desc)
		{
			UE_LOG(LogDbdModkitGameShaders, Log, TEXT("DBDModkitGame: custom pass shader type %s editor=%s cooked=%s"),
				Name, *Freeze::HashLayout(Desc, EditorParams).ToString(), *Freeze::HashLayout(Desc, CookedParams).ToString());
		};
		LogLayout(TEXT("TCustomVS"), StaticGetTypeLayoutDesc<TCustomVS>());
		LogLayout(TEXT("FCustomNoDepthPS"), StaticGetTypeLayoutDesc<FCustomNoDepthPS>());
	}
};

IMPLEMENT_MODULE(FDbdModkitGameShadersModule, DBDModkitGameShaders)
