# Better Pal Souls

1.0.0 · ourongxing

Quickly choose enhancement levels in the standard Statue of Power interface and automatically convert Pal Souls for the enhancement you confirm.

## Features and usage

- ◀: clears pending enhancements for that stat and returns the selection to its current enhanced level. It does not reset stats or refund spent souls.
- ▶: selects the highest affordable level while reserving souls for enhancements already selected for other stats.
- Standard − / +: adjusts one level at a time. All four stats share the available souls, with costs displayed in the standard interface.

Small, Medium, Large, and Giant Pal Souls are valued at 1 / 2 / 4 / 8. Previewing does not change inventory. Confirming an enhancement converts souls as needed and keeps all remaining value as Small Pal Souls.

Uses your backpack and containers in the current base that the standard enhancement interface can access. Free backpack slots if conversion needs more space. Enhancement effects, level caps, and costs follow the game settings. The reset page works as usual.

## Installation

1. Subscribe to and enable the required mods: UE4SSExperimentalPW.
2. Enable this mod in the game's Mod Management menu.
3. Fully exit the game, then launch it again.

## Configuration

Edit `Mods/NativeMods/UE4SS/Mods/BetterPalSouls/Scripts/config.lua` under your Palworld installation, save your changes, then fully exit and restart the game.

- `Enabled`: turns the feature on or off.
- `Language`: defaults to `auto` to follow the game language. You can also choose `zh-Hans`, `zh-Hant`, `ja`, or `en`.

## Before you play

Supports single-player and the co-op host's own character only. Joining players and dedicated servers are unsupported.

Enhancement confirmation, saving and reloading, recovery from failed operations, and controller input have not been fully verified in-game. Back up your save before first use.
