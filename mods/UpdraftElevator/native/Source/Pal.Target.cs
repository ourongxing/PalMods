using UnrealBuildTool;
public class PalTarget : TargetRules { public PalTarget(TargetInfo Target) : base(Target) { Type=TargetType.Game; DefaultBuildSettings=BuildSettingsVersion.V2; ExtraModuleNames.Add("Pal"); } }
