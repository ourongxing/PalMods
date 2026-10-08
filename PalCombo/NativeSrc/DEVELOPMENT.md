# PalCombo native development

## Current build

Version 1.0.6-dev replaces the native active-skill slot selector used by player-controlled Otomo combat actions. It keeps the original selector's side effects and substitutes the slot result by slot position for every player Pal. Repeated selections before a skill enters cooldown return the same slot, so two native calls during one action transition cannot advance 0 to 1 prematurely. After slot 0 enters cooldown, slot 1 is selected when ready. After slot 1 enters cooldown, the pair resets; slot 2 can fill until the next pair qualifies. A target change resets the pending selection. `EarlyStartSeconds` compares against remaining cooldown calculated from the elapsed cooldown and its rate. The default is 3.0 seconds. It does not call `CancelAction`.

The active runtime is `Mods/PalCombo`, enabled by `Mods/mods.txt` (`PalCombo : 1`). Its `dlls/main.dll` is now 1.0.6-dev (SHA-256 `FAF161A0BE90D2978BDF873CF4EBFB9DA5FABAFCCB4B31BB42F53A849C73ACBF`); `config.ini` sets `EarlyStartSeconds=3.0`. The replacement compiled and passed the pure rotation test but still needs in-game verification. The diagnostic log at 17:25:34 shows two selector calls 0.00024 seconds apart with all slots ready: selected 0 then selected 1. This confirms phase advancement on selection rather than on actual cooldown as the cause of the immediate slot-2 action. Log values for `GetCoolTime(1)` increase from 0 after casting, proving they are elapsed time, not remaining time; the new build combines `GetCoolTime` with `GetCoolTimeRate` to calculate remaining seconds. The prior diagnostic DLL is backed up at `NativeSrc/build/PalCombo-1.0.4-diagnostic-backup.dll`.

## Reverse engineering

See [DECOMPILATION.md](DECOMPILATION.md) for the extracted Blueprint path and the actual native call chain. The direct native call explains why earlier UFunction hooks registered but did not affect the selected skill.

## Past failure

- `PlayAction_ToALL` could be skipped but the same skill still entered `OnBeginAction`.
- Synchronous `CancelAction` in `OnBeginAction` recursively triggered `StartNextAction_Event` and froze the game. The cancellation build is retained in the cleanup backup outside this repository.
- A previous post-hook rewrite of `NextWazaSlotIndex` and `NextActionClass` did not prevent the game from choosing slots 1 and 2 separately.
- Hooking `ChoiceEnableSlotIDByRandom` and `FindMostEffectiveSlotID` as UFunctions registered successfully but callbacks did not fire for the real combat selection path.

## Build and verification

Build `PalComboFillerNative` in `Game__Shipping__Win64`, then copy its DLL to `dlls/main.dll` while the game is stopped. The pure rotation test is `MyCPPMods/PalComboFillerNative/tests/rotation_test.cpp`. The hook checks the native selector's first 15 bytes and the direct call target before installing; an unknown game build logs `unsupported game binary` and leaves game behavior alone.
