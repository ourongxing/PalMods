# Better Storage

1.1.0 · ourongxing

Send items back to base from the wilderness and fit more into each inventory slot.

## Main features

- **Store from anywhere**: open your inventory and press R (default) to store items at your main base. Inside a base, storage uses that base. Your main base is the guild base with the most structures; ties go to the nearest.
- **Larger stacks**: ordinary stackable items fit at least 99,999 per slot. Higher existing limits stay unchanged, as do non-stackable items such as equipment.
- **Smarter Pal transport**: at equal transport priority, Pals prefer chests with matching stacks that have room left.
- **Schematic storage**: the antique bookshelf and antique large cabinet become schematic-only storage with 360 slots. Rebuild existing furniture to apply this.
- **Larger guild storage**: newly created guild inventories have 360 shared slots. Existing inventories cannot be expanded, even by rebuilding guild chests.

Quick storage only uses chests that already contain the same item type. Vanilla categories, permissions, exclusions, and confirmation still apply.

## Installation

1. Subscribe to and enable the required mods: UE4SSExperimentalPW, PalSchema.
2. Enable this mod in the game's Mod Management menu.
3. Fully exit the game, then launch it again.

## Configuration

Edit `Mods/NativeMods/UE4SS/Mods/PalSchema/mods/BetterStorage/blueprints/storage.json` under your Palworld installation, save your changes, then fully exit and restart the game.

The two `SlotNum` settings control the bookshelf and cabinet capacities separately. `GuildChestSlotNum` sets the capacity of new guild storage.

## Before you play

Wilderness storage and eligibility highlighting have been tested in single-player. Multiplayer is unverified. Stack, transport, and capacity changes require host or server installation; installing only on a joining player's computer cannot change server rules. New guild storage capacity and multiplayer synchronization are also unverified.

Do not enable together with BetterBulkStorage. The 360-slot furniture interface may lower frame rates; you can reduce the capacity for furniture you build afterwards.

Existing separate stacks are not automatically merged. Split stacks exceeding vanilla limits before uninstalling.
