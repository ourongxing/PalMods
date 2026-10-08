using UnrealBuildTool;
public class PalEditorTarget : TargetRules { public PalEditorTarget(TargetInfo Target) : base(Target) { Type=TargetType.Editor; DefaultBuildSettings=BuildSettingsVersion.V2; ExtraModuleNames.AddRange(new string[]{"Pal","WindEditor"}); } }
