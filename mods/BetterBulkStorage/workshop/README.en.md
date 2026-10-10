# Better Bulk Storage

1.0.0 · ourongxing

Enhances the game's Easy Bulk Storage feature to automatically store inventory items in matching chests based on their category and filter settings. Chests no longer need to contain the same item first. Empty chests work too.

You can also store items in your main base's chests while out in the wilderness. Your main base is the base in your guild with the most structures. If multiple bases have the same number of structures, the closest one to the player is selected. Inside a base, items go to the current base.

Open your inventory and use the standard Easy Bulk Storage button or shortcut (R by default on keyboard). Set the allowed item categories for each chest to organize your items by category. The original confirmation window and exclusion list remain available, and chest capacity, category settings, and access permissions still apply. Pal Eggs can also be stored in chests that allow their category and have empty slots.

Checks start only after using the storage shortcut or button and update item greying over multiple frames. Opening or sorting your inventory does not start a scan; sorting during a scan cancels it. Eligible items enter the list one at a time; confirmation processes the items already added. Wilderness storage does not require loading remote chests; the server validates the actual transfer.

Currently tested in local single-player. Multiplayer requires this mod's DLL on the server and Lua on the client. Installing only on the client cannot change the server's storage rules. Multiplayer has not been verified.

Subscribe to and enable the required mods: UE4SSExperimentalPW. Then enable this mod in the game’s Mod Management menu and restart the game.

Storage first merges matching stacks across all destination chests, then places remaining items into empty slots.

Pal transport now prefers chests with non-full matching stacks within the same transport priority tier. Distance still breaks ties between matching chests. Full stacks receive no bonus, and vanilla chest priorities, category filters and production requirements still apply. The host or server must load the DLL; the rule applies when selecting new transport targets.

Ordinary stackable items now use a shared per-slot limit of 99,999 in inventories, chests, mining sites, logging sites and other item containers. Mining and logging sites use the same limit when checking whether storage is full. This does not change production yield or work speed. Equipment, Pal Eggs and other unique-instance items keep their original rules. Filters, permissions and slot counts still apply. Existing quantities are preserved, and scattered stacks are not merged automatically. No separate stack-limit mod is needed; split oversized stacks before uninstalling. Mining stop/resume behavior, save/reload and multiplayer still need in-game verification.

This mod is open source under the GPL-3.0 license.
Source code: https://github.com/ourongxing/PalMods
