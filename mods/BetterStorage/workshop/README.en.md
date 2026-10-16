# Better Storage

1.1.0 · ourongxing

Use vanilla Easy Bulk Storage in the wilderness, increase stack limits, improve Pal transport, and add larger schematic furniture and configurable guild storage capacity.

## Features and usage

Open your inventory and use the standard Easy Bulk Storage button or shortcut (R by default on keyboard).

- Destination: the current base while inside a base; otherwise your guild's base with the most structures. Ties are resolved by distance to the player.
- Vanilla storage rules: a destination chest must already contain the same item type. New types are not placed in empty chests or chests containing only other items. Keeps eligibility highlighting, the exclusion list, and confirmation window, respecting categories, permissions, and capacity.
- Stack limits: ordinary stackable items have a minimum per-slot limit of 99,999 across inventory, chests, and production storage. Higher vanilla limits are preserved, including the 99,999,999 coin limit. Equipment and other items that do not stack normally retain their original rules.
- Pal transport: prefers chests with matching partial stacks within the same transport priority. Existing categories, permissions, and priorities remain in effect.
- Schematic furniture: the antique bookshelf and antique large cabinet have 360 slots and accept schematics only. Rebuild existing copies to apply the capacity and category settings.
- Guild storage: newly created guild storage defaults to 360 slots. All guild chests still share one inventory. Existing guild storage is not expanded, and rebuilding a guild chest does not change its capacity.

## Installation

1. Subscribe to and enable the required mods: UE4SSExperimentalPW, PalSchema.
2. Enable this mod in the game's Mod Management menu.
3. Fully exit the game, then launch it again.

## Configuration

Edit `Mods/NativeMods/UE4SS/Mods/PalSchema/mods/BetterStorage/blueprints/storage.json` under your Palworld installation, save your changes, then fully exit and restart the game.

The two `SlotNum` settings control the bookshelf and cabinet capacities separately. `GuildChestSlotNum` sets the capacity of new guild storage.

Fully restart the game or server after editing. Changes apply only to matching furniture or guild inventories created afterwards.

## Before you play

Wilderness storage and eligibility highlighting have been tested in single-player. Multiplayer is unverified. Stack, transport, and capacity changes require host or server installation; installing only on a joining player's computer cannot change server rules. New guild storage capacity and multiplayer synchronization are also unverified.

Do not enable together with BetterBulkStorage. The 360-slot furniture interface may lower frame rates; you can reduce the capacity for furniture you build afterwards.

Existing separate stacks are not automatically merged. Split stacks exceeding vanilla limits before uninstalling.

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
