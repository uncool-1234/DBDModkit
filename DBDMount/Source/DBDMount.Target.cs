using UnrealBuildTool;

public class DBDMountTarget : TargetRules
{
	public DBDMountTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Game;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("DBDMount");
	}
}
