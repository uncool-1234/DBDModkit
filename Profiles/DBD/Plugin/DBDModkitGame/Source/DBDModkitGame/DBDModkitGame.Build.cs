using UnrealBuildTool;

// Loaded on demand by Suzie (profile.json "extension_module"), hence LoadingPhase None in the .uplugin.
public class DBDModkitGame : ModuleRules
{
	public DBDModkitGame(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = ModuleRules.PCHUsageMode.UseExplicitOrSharedPCHs;
		PublicDependencyModuleNames.AddRange(new string[] { "Core" });
		PrivateDependencyModuleNames.AddRange(new string[] { "CoreUObject", "Engine", "GameplayTags", "Suzie" });
	}
}
