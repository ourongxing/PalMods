# Extra Implant Drops

1.0.0 · ourongxing

Pals can drop additional implants matching their passive skills when they die or are butchered.

## Features and usage

- Supports 28 implants, with a separate drop roll for each eligible passive skill.
- The default chance is 50%, with a base quantity of 1.
- Quantity is affected by game drop bonuses and world settings.
- Normal material drops are preserved.

## Installation

1. Subscribe to and enable the required mods: UE4SSExperimentalPW.
2. Enable this mod in the game's Mod Management menu.
3. Fully exit the game, then launch it again.

## Configuration

Edit `Mods/NativeMods/UE4SS/Mods/ExtraImplantDrops/config.ini` under your Palworld installation, save your changes, then fully exit and restart the game.

- `DropChance=0.5` under `[Harvest]`: drop probability from 0 to 1. Set 0 for no drops or 1 to always pass the probability check.
- `[Implants]`: enable or disable individual passive-skill implant drops with 1 or 0. Enabled drops still require a successful probability check.
