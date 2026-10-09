# Pal Combo

1.0.0 · ourongxing

Makes the player's Pals chain skill slot 1 into slot 2, using slot 3 between combos.

A combo starts when slot 1 is ready and slot 2 is either ready or within the configured cooldown window. Once slot 1 enters cooldown, the Pal waits for slot 2 without inserting slot 3. When slot 2 enters cooldown, the combo resets. Mounted skills remain manually controlled; automatic combat resumes after dismounting.

Configuration: `EarlyStartSeconds` in `config.ini`. The default is 3 seconds; the supported range is 0–30 seconds. Set it to 0 to wait until slot 2 is fully ready. Restart the game after changing the setting. This mod adds no in-game text.

Subscribe to and enable the required mods: UE4SSExperimentalPW. Then enable this mod in the game’s Mod Management menu and restart the game.

This mod is open source under the GPL-3.0 license.
Source code: https://github.com/ourongxing/PalMods
