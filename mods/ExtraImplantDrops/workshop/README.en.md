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

## Report a problem

Report problems on GitHub Issues: https://github.com/ourongxing/PalMods/issues

Without the UE4SS log, I cannot diagnose and fix bugs.

Please include:

- The mod name, game and mod versions, and game language.
- Whether you are playing alone, hosting co-op, joining another player, or using a dedicated server.
- Steps to reproduce the problem, expected and actual behavior, relevant screenshots, and other enabled mods.
- The complete `UE4SS.log` from the session where the problem occurred, uploaded as an attachment.

In Steam, right-click Palworld → Manage → Browse local files, then open `Mods\NativeMods\UE4SS\UE4SS.log`.
For example, with the game installed on drive G:
`G:\SteamLibrary\steamapps\common\Palworld\Mods\NativeMods\UE4SS\UE4SS.log`

Use your own drive letter and Steam library location. Copy the log before launching the game again so the record of the problem is not overwritten.

## Source code

Open source under GPL-3.0.
https://github.com/ourongxing/PalMods
