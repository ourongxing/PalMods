# Better Workbench

1.0.0 · ourongxing

Automatically resolves missing intermediate materials using recipes available at the same crafting station. Also adds a scrollable material list and instant disassembly.

Crafting uses intermediate items you already own first, then calculates the raw materials needed for the shortfall using unlocked recipes at that station. Select the owned-item count in the recipe details to switch to disassembly. Choose the number of batches and confirm to consume complete recipe batches and return all original recipe materials to your inventory.

Configuration: `Scripts/config.lua`. `Disassembly.Language` defaults to `auto` and follows the game language. You can also select `zh-Hans`, `zh-Hant`, `ja`, or `en`. Item names come from the game.

Disassembly currently supports single-player and the multiplayer host. Multiplayer task-definition synchronization is not implemented. Inventory deductions, controller input, material returns, and save restoration still require in-game verification. Keep `Jobs/*.bwj` for unfinished tasks alongside your save files.

Subscribe to and enable the required mods: UE4SSExperimentalPW. Then enable this mod in the game’s Mod Management menu and restart the game.

This mod is open source under the GPL-3.0 license.
Source code: https://github.com/ourongxing/PalMods
