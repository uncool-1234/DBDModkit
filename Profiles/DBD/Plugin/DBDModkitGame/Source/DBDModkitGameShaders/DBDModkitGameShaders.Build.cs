using UnrealBuildTool;

// Loaded at PostConfigInit (DBDModkitGame.uplugin), before the engine initializes shader types.
public class DBDModkitGameShaders : ModuleRules
{
	public DBDModkitGameShaders(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = ModuleRules.PCHUsageMode.UseExplicitOrSharedPCHs;
		PublicDependencyModuleNames.AddRange(new string[] { "Core" });
		PrivateDependencyModuleNames.AddRange(new string[] { "RenderCore", "RHI", "Engine", "Renderer", "Projects" });
	}
}
