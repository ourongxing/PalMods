# Better Workbench

1.0.0 · ourongxing

Automatically calculates materials for missing intermediate items at the same crafting station, adds a scrollable material list, and lets you instantly disassemble finished items.

## Features and usage

- Uses intermediate items you already own first, then resolves only the shortfall using unlocked recipes at the current station. Recipes from other stations are unavailable.
- For example, if you need 3 ingots and own 1, a station that can craft those ingots uses the owned ingot plus the ore needed for the other 2.
- The material list shows 5 rows by default. Scroll with the mouse wheel to see additional materials.
- Select the owned-item count at the top right of the recipe details to switch between crafting and disassembly. Choose the number of batches and confirm to consume complete recipe batches and return all original recipe materials to your backpack.
- Craft up to 256 batches at once. Work time follows the selected finished-item recipe; intermediate crafting does not add extra work time.

## Installation

1. Subscribe to and enable the required mods: UE4SSExperimentalPW.
2. Enable this mod in the game's Mod Management menu.
3. Fully exit the game, then launch it again.

## Configuration

Edit `Mods/NativeMods/UE4SS/Mods/BetterWorkbench/Scripts/config.lua` under your Palworld installation, save your changes, then fully exit and restart the game.

- `Enabled`: turns the feature on or off.
- `MaterialScroll.Enabled`, `MaterialScroll.VisibleRows`: enables material-list scrolling and sets the visible row count.
- `Disassembly.Enabled`: enables or disables instant disassembly.
- `Disassembly.Language`: defaults to `auto` to follow the game language. You can also choose `zh-Hans`, `zh-Hant`, `ja`, or `en`. Item names use the game's translations.

## Before you play

Disassembly supports single-player and the co-op host's own character only. Multiplayer crafting-task synchronization is not yet supported.

Item consumption, material returns, recovery after saving, and controller input have not been fully verified in-game. When backing up or moving your save, also keep the `Jobs` folder inside this mod's installation folder: unfinished crafting tasks depend on its contents.
