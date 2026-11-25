using UnrealBuildTool;
public class ASTCharacterFireBounce : ModuleRules
{
    public ASTCharacterFireBounce(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        PublicDependencyModuleNames.AddRange(new[] { "Core", "CoreUObject", "Engine" });
    }
}
