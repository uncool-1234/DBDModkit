using UnrealBuildTool;

public class DBDMountEditorTarget : TargetRules
{
	public DBDMountEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("DBDMount");
	}
}
