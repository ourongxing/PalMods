#pragma once
#include <array>
namespace extra_implant_drops {
struct ImplantRule { const wchar_t* passive; const wchar_t* item; };
inline constexpr std::array<ImplantRule, 28> implant_rules = {{
    {L"CraftSpeed_up3", L"PalPassiveSkillChange_Consumable_CraftSpeed_up3"},
    {L"Deffence_up3", L"PalPassiveSkillChange_Consumable_Deffence_up3"},
    {L"EternalFlame", L"PalPassiveSkillChange_Consumable_EternalFlame"},
    {L"Invader", L"PalPassiveSkillChange_Consumable_Invader"},
    {L"Legend", L"PalPassiveSkillChange_Consumable_Legend"},
    {L"MoveSpeed_up_3", L"PalPassiveSkillChange_Consumable_MoveSpeed_up_3"},
    {L"MutationPal_Babysitter", L"PalPassiveSkillChange_Consumable_MutationPal_Babysitter"},
    {L"MutationPal_ExplosionResist", L"PalPassiveSkillChange_Consumable_MutationPal_ExplosionResist"},
    {L"MutationPal_Immortal", L"PalPassiveSkillChange_Consumable_MutationPal_Immortal"},
    {L"MutationPal_Mutant", L"PalPassiveSkillChange_Consumable_MutationPal_Mutant"},
    {L"Nushi", L"PalPassiveSkillChange_Consumable_Nushi"},
    {L"PAL_ALLAttack_up3", L"PalPassiveSkillChange_Consumable_PAL_ALLAttack_up3"},
    {L"PAL_FullStomach_Down_3", L"PalPassiveSkillChange_Consumable_PAL_FullStomach_Down_3"},
    {L"PAL_Sanity_Down_3", L"PalPassiveSkillChange_Consumable_PAL_Sanity_Down_3"},
    {L"Rare", L"PalPassiveSkillChange_Consumable_Rare"},
    {L"RideJumpCount_Increase2", L"PalPassiveSkillChange_Consumable_RideJumpCount_Increase2"},
    {L"Salvation", L"PalPassiveSkillChange_Consumable_Salvation"},
    {L"Stamina_Up_3", L"PalPassiveSkillChange_Consumable_Stamina_Up_3"},
    {L"SwimSpeed_up_3", L"PalPassiveSkillChange_Consumable_SwimSpeed_up_3"},
    {L"Vampire", L"PalPassiveSkillChange_Consumable_Vampire"},
    {L"Witch", L"PalPassiveSkillChange_Consumable_Witch"},
    {L"WorldTree_ATK", L"PalPassiveSkillChange_Consumable_WorldTree_ATK"},
    {L"WorldTree_ATK_DEF", L"PalPassiveSkillChange_Consumable_WorldTree_ATK_DEF"},
    {L"WorldTree_CraftSpeed", L"PalPassiveSkillChange_Consumable_WorldTree_CraftSpeed"},
    {L"WorldTree_DEF", L"PalPassiveSkillChange_Consumable_WorldTree_DEF"},
    {L"WorldTree_FullStomach", L"PalPassiveSkillChange_Consumable_WorldTree_FullStomach"},
    {L"WorldTree_MoveSpeed", L"PalPassiveSkillChange_Consumable_WorldTree_MoveSpeed"},
    {L"WorldTree_Sanity", L"PalPassiveSkillChange_Consumable_WorldTree_Sanity"},
}};
}
