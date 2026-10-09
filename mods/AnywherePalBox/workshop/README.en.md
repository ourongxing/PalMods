# Anywhere Palbox

1.0.0 · ourongxing

Press K to open the standard Palbox from the wilderness or a dungeon, making it easy to view, organize, and swap your Pals.

Inside your guild's base, opens that base's Palbox. Outside a base or inside a dungeon, selects the base in your guild with the most structures. If multiple bases have the same number of structures, selects the closest one to the player. The selection is refreshed on every key press. Your guild must have a base, and its terminal model must be available.

Uses the game's standard terminal interface and closing behavior. Key presses are ignored while another menu is open, during screen fades, or before the player is ready. Inside another guild's base, the mod does not open a terminal or switch to one of your guild's bases.

The default shortcut is K. Edit `Mods/NativeMods/UE4SS/Mods/AnywherePalBox/Scripts/config.lua` in the game installation and change `Hotkey = "K"` to a UE4SS key name such as `"J"` or `"F6"`, then restart the game. Key names are case-insensitive. Only a single key is supported. Missing or invalid configuration falls back to K and reports the issue in the UE4SS log.

Verified in local single-player, including dungeons. Multiplayer has not been verified.

Subscribe to and enable the required mod: UE4SSExperimentalPW. Then enable this mod in the game's Mod Management menu and restart the game.
