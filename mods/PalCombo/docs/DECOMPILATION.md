# Palworld combat selection: decompilation record

Analysis date: 2026-09-29. Game executable SHA-256: `E590B5E7BFAA3FEA40FAB1A02CC72C8FC5FD6F8631EF2308E95AC56C25195837`.

## Assets and tools

Extracted `BP_AIAction_CombatPal` and `BP_MonsterAIController_Otomo` from `Pal-Windows.pak` with `repak`. Decoded Blueprint bytecode with UAssetAPI v1.1.0 and the Palworld mapping file. `tools/print_blueprint.ps1` renders a decoded function from the resulting JSON. Native addresses below come from disassembling this exact `Palworld-Win64-Shipping.exe` with Rizin. Addresses are image relative RVAs so they remain valid with ASLR for this binary.

## Blueprint path versus Otomo path

The ordinary `BP_AIAction_CombatPal` Blueprint's `Get Next Action Slot ID` calls `UPalActiveSkillSlot::FindSlotIDForWildPal(TargetActor, empty ignore list)`. Its `ChangeNextAction` looks up the chosen Waza class, and `PlayWazaAction` plays it. That is a real path, but it is not the player Otomo path.

The `BP_MonsterAIController_Otomo` class default object sets `CombatModuleClass` to `PalAICombatModule_Otomo`. Its `AttackForEnemy` invokes native `Set Combat Action And Target`. The native action used for this controller is `UPalAIActionCombat_Standard`, deriving from `UPalAIActionCombatBase`.

## Native call chain

1. `UPalAIActionCombat_Standard::StartNextAction_Event` UFunction thunk at RVA `0x281FF20` calls native implementation at RVA `0x2D102C0`.
2. At native RVA `0x2D10336`, it tail-jumps into `UPalAIActionCombatBase::ChangeNextAction` at RVA `0x2CF6FC0` when the current action ends and the AI wants the next one.
3. `ChangeNextAction` obtains the Pal's `UPalActiveSkillSlot*` and target actor. At RVA `0x2CF7040`, it **directly** calls the core slot selector at RVA `0x2CFABB0`, passing `(slot, target actor, empty ignored-Waza-ID array)`. The selector returns a signed slot ID in `EAX`.
4. If the ID is not `-1`, RVA `0x2CF708C` writes `NextWazaSlotIndex`, then resolves the Waza class. If a valid class is found, RVA `0x2CF7158` sets `NextIsWaza` and RVA `0x2CF7162` sets `NextActionClass`.
5. `-1` skips the Waza lookup. The subsequent path handles the action class or taunt. The disassembly contains a debug string equivalent to “NextActionClass is null, so taunt.” This documents the game's no-skill path; it does not yet prove every runtime outcome when a prior action class remains cached.

The public `FindMostEffectiveSlotID` UFunction thunk at RVA `0x2815AC0` calls wrapper RVA `0x2CFAB70`, which then calls the same core selector at `0x2CFABB0`. The combat action bypasses the UFunction thunk. A UE4SS UFunction hook on `FindMostEffectiveSlotID` cannot observe the combat action's direct C++ call. `FindSlotIDForWildPal` uses a different core function at RVA `0x2CFB970` and applies to the ordinary Blueprint path.

## Implemented interception

`native/src/dllmain.cpp` installs an x64 detour at RVA `0x2CFABB0`. It calls the original selector first, then replaces the return slot when the selector's `SelfActor` is controlled by `MonsterAIController_Otomo`. The current build tracks a combo phase per player Pal. The `GetCoolTime` UFunction thunk is at RVA `0x2815E10` and calls native RVA `0x2CFCF70`, which returns elapsed cooldown time. The `GetCoolTimeRate` thunk at RVA `0x2815EB0` calls native RVA `0x2CFD110`, which returns elapsed time divided by total cooldown. For a cooling skill, remaining cooldown is `elapsed * (1 - rate) / rate` when both inputs are positive and finite. The runtime verifies the selector's 15-byte entry prefix and the direct call at RVA `0x2CF7040` before installing the detour. The hook is version-specific and fails closed on a changed binary.

## Evidence and limits

- The 0.6.1 DLL startup log showed `installed native selector detour` at 13:52:24, confirming the binary guard and detour installation on this executable. The game reached the title screen and remained responsive.
- The 0.6.1 battle log showed GrimGirl's actual selected and cast slots 0→1→2, confirming the detour handles that Pal. The same log showed GravityShot when all three slots were unavailable, so the game's `-1` path can still produce a fallback Waza. The user confirmed that 0.7.0 worked on two different Pals. Version 1.0.0 changes the rotation to stateless priority; its combat outcome remains unverified.
- If combat still behaves like vanilla, first check the bounded selector diagnostics and the `SelfActor` association. If selection logs show `selected=...` yet a different Waza casts, trace `NextActionClass` assignment and the actual `StartNextAction_Event` dispatch before altering another hook.
