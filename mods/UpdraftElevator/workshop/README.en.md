# Updraft Elevator

1.1.1 · ourongxing

Build updraft elevators and press jump inside their range to launch into the air using the game's original updraft jump animation.

## Features and usage

- Small: default height 8 m, area diameter 2 m.
- Medium: default height 16 m, area diameter 4 m.
- Large: default height 32 m, area diameter 6 m.
- Overlapping updrafts use the highest lift setting.

Unlock all three sizes at level 9 in Ancient Technology for 1 Ancient Technology Point. Each elevator costs 10 Paldium Fragments, 30 Stone, and 3 Ancient Civilization Parts.

Place elevators from the Infrastructure/Updraft Elevator section of the build menu. Completed elevators are invisible. To dismantle one, enter disassembly mode and aim at the base of the updraft.

## Installation

1. Subscribe to and enable the required mods: UE4SSExperimentalPW, PalSchema.
2. Enable this mod in the game's Mod Management menu.
3. Fully exit the game, then launch it again.

## Configuration

Edit `Mods/NativeMods/UE4SS/Mods/UpdraftElevator/Scripts/config.lua` under your Palworld installation, save your changes, then fully exit and restart the game.

`Small`, `Medium`, and `Large` set the lift height for each size in metres. Defaults are 8, 16, and 32. Values from 0.1 to 1000, including decimals, are supported; invalid values use the defaults.

Building and technology text supports Simplified Chinese, Traditional Chinese, Japanese, and English. Other languages use English. Restart the game after changing its language.
