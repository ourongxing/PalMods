# Better Workbench

1.0.0 · ourongxing

Skip intermediate crafting steps and turn unwanted finished items back into materials.

## Main features

- **Craft from raw materials**: uses intermediate items you own first, then covers the shortfall with their ingredients. Only unlocked recipes at the current station are available; recipes from other stations cannot be used.
- **Scrollable material list**: shows 5 rows by default. Use the mouse wheel to see the rest.
- **Instant disassembly**: consumes finished items in complete recipe batches and returns all original recipe materials to your backpack.

## How to use

Select a recipe and craft as usual. Click the **owned-item count** at the top right of the recipe details to switch between crafting and disassembly, then choose the batch count and confirm.

Craft up to 256 batches at once. Work time follows the finished-item recipe, with no extra time added for intermediate items.

## Installation

1. Subscribe to and enable the required mods: UE4SSExperimentalPW.
2. Enable this mod in the game's Mod Management menu.
3. Fully exit the game, then launch it again.

## Configuration

Edit `Mods/NativeMods/UE4SS/Mods/BetterWorkbench/Scripts/config.lua` under your Palworld installation, save your changes, then fully exit and restart the game.

## Before you play

Disassembly supports single-player and the co-op host's own character only. Multiplayer crafting-task synchronization is not yet supported.

Item consumption, material returns, recovery after saving, and controller input have not been fully verified in-game. When backing up or moving your save, also keep the `Jobs` folder inside this mod's installation folder: unfinished crafting tasks depend on its contents.
