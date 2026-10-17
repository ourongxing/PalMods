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
