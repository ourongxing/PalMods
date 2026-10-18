# Custom Presets

1.0.0 · ourongxing

Save and reuse your custom world settings and character appearances.

## Features and usage

- World presets: save, switch, update or delete your custom settings. Original difficulty presets remain unchanged.
- Character presets: save your appearance in the character editor's Presets category and choose it later from upper-body thumbnail cards.
- New presets use the game's naming dialog. The default name is Custom Preset; duplicate names are allowed.
- Opening the settings preserves current edits. Deleting a preset selects the previous preset, or the next one if needed.
- Character changes show an unsaved indicator. Save explicitly to update a preset.
- Follows the game language: English, Simplified Chinese, Traditional Chinese and Japanese.

This mod saves existing game options. It does not add character models, faces, hairstyles or outfits, and does not extend slider limits. Character names, equipment and save identities are not included. Apply or cancel appearances with the game's original controls.

## Installation

1. Enable the required UE4SSExperimentalPW mod.
2. Enable Custom Presets in Mod Management.
3. Fully exit and restart the game.

## Saved data

Presets and images are stored in `%LOCALAPPDATA%/Pal/Saved/CustomPresets/presets/`, separately from installation files. Back up this folder when moving computers; this mod does not provide cloud sync.

Each preset is a separate `world-N.preset` or `character-N.preset` file containing its name and all settings. Character thumbnails use matching `character-N.png` files. Backups are kept in the adjacent `../backups/` folder.

This is a client UI mod; dedicated servers do not need it. Keyboard and mouse operation has been tested during development. Controller navigation still needs testing.
