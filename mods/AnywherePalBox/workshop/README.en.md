# Anywhere Palbox

1.0.0 · ourongxing

Press K to open the standard Palbox anywhere, including the wilderness and dungeons, to view, organize, and swap your Pals.

## Features and usage

- Inside your guild's base, opens that base's Palbox.
- In the wilderness or a dungeon, selects your guild's base with the most structures. Ties are resolved by distance to the player. The selection is refreshed on every key press.
- Your guild must have a base with an available Palbox.
- Does not open a Palbox while you are inside another guild's base.
- Uses the standard Palbox interface. The shortcut is ignored while another menu is open, during screen transitions, or before the player is ready.

## Installation

1. Subscribe to and enable the required mods: UE4SSExperimentalPW.
2. Enable this mod in the game's Mod Management menu.
3. Fully exit the game, then launch it again.

## Configuration

Edit `Mods/NativeMods/UE4SS/Mods/AnywherePalBox/Scripts/config.lua` under your Palworld installation, save your changes, then fully exit and restart the game.

`Hotkey = "K"` sets the shortcut. Change it to a single key such as `"J"` or `"F6"`. Key names are case-insensitive. Missing or invalid settings use K.

## Before you play

Tested in single-player, including dungeons. Multiplayer has not been verified.

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
