# Better Storage

1.1.0 · ourongxing

Use vanilla Easy Bulk Storage outside your base, increase stack limits, and add larger schematic furniture and a configurable guild storage capacity.

Inside a base, items go to that base. Outside a base, they go to your guild's base with the most buildings; ties are resolved by distance to the player. Open your inventory and use the vanilla Easy Bulk Storage button or shortcut (R by default on keyboard).

Keeps vanilla eligibility highlighting, exclusion list and confirmation dialog, and respects chest categories, access permissions and capacity. A destination chest must already contain the same item type. New item types will not be placed in empty chests or chests containing only other items.

Ordinary stackable items have a minimum stack limit of 99,999 across inventory, chests and production storage. Higher vanilla limits are preserved, including the 99,999,999 coin limit. Unstackable and individually instanced items keep vanilla rules. Existing separate stacks are not automatically merged. Split stacks exceeding vanilla limits before uninstalling.

When Pals transport items, chests with a matching partial stack are preferred within the same transport priority. Existing chest categories, permissions and priorities still apply.

The antique bookshelf and antique large cabinet (Shelf01_Stone and Shelf07_Stone) have 360 slots and accept schematics only. Rebuild existing copies of these furniture items to apply the capacity and filter settings.

Newly created guild storage defaults to 360 slots. All guild chests still share one inventory. Existing guild storage is not expanded, and rebuilding a guild chest does not change its capacity. The vanilla interface for 360-slot furniture can be expensive to display.

Capacity configuration: UE4SS/Mods/PalSchema/mods/BetterStorage/blueprints/storage.json. Adjust each furniture item's SlotNum and the guild's GuildChestSlotNum separately, then fully restart the game or server. Changes only affect matching containers or guild inventories created afterwards.

Subscribe to and enable UE4SSExperimentalPW and PalSchema, then enable this mod in the game Mod Management menu, fully exit the game, and restart. Do not enable it together with BetterBulkStorage.

Outside-base storage and eligibility highlighting have been tested locally in single-player; the quick-storage optimization also received positive player feedback. Multiplayer is unverified. Stack limits, transport and capacity patches require host or server installation; client-only installation cannot change server rules. New guild storage capacity and synchronization still need in-game verification.

Open source under GPL-3.0.
Source: https://github.com/ourongxing/PalMods
