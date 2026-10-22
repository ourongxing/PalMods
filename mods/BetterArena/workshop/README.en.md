# Better Arena

1.1.1 · ourongxing

Fixes recurring background scheduling and the locked Sweep hint before the first clear. Reward initialization stops repeated world queries once verified.

Clear an Arena difficulty once, then claim its rewards instantly with daily sweeps. A higher player rank gives you more sweeps each day.

## How to use

Choose **Sweep** in the Arena main menu, then select a cleared difficulty to receive its repeat-clear rewards and victory RP immediately. No battle or timer. An animated reward banner and sound confirm the actual items and RP received.

- **Unlock each difficulty**: complete it normally once. The original Challenge option remains available.
- **Your rank sets the limit**: Bronze through Legend player ranks receive **1 / 3 / 5 / 7 / 9 / 11 / 13 sweeps per day**, regardless of the selected challenge difficulty.
- **One shared allowance**: all difficulties share the daily limit. It resets each in-game day without carryover. Ranking up adds the difference to today's allowance without clearing used sweeps.
- **Double rewards by default**: normal NPC challenges and sweeps share doubled item quantities and base victory RP, including first-clear and repeat-clear rewards. The game's rank-difference RP calculation still applies.

## Installation

1. Subscribe to and enable the required mods: UE4SSExperimentalPW and PalSchema.
2. Enable this mod in the game's Mod Management menu.
3. Fully exit the game, then launch it again.

Windows dedicated servers: install and enable this mod, UE4SSExperimentalPW, and PalSchema on both the server and clients, then fully restart both sides.

## Configuration

Open `Mods/NativeMods/UE4SS/Mods/BetterArena/` under your Palworld installation.

In multiplayer, reward multipliers and daily limits use the host or server configuration. Restart the server after changing its settings.

- **Reward multiplier**: close the game, edit `RewardMultiplier` in `Scripts/config.lua` to an **integer from 1 to 10**, save and restart. Default: 2. Use 1 for vanilla base rewards. Applies automatically when entering a world.
- **Daily limits**: edit `DailyLimits` in `Scripts/config.lua`, ordered from Bronze through Legend. Each value accepts 0–100. Save and fully restart the game.

First launch enables PalSchema automatic reloading. If it was disabled, fully restart once more to finish setup. This setting also applies to other PalSchema mods.

## Before you play

Supports single-player, co-op hosts, and Windows dedicated servers. Multiplayer sweeps are validated and awarded by the host or server using the player's clear records, allowance, and inventory. The interface follows the game language, with English, Japanese, Simplified Chinese, and Traditional Chinese support.

Reward patches use vanilla Palworld 1.0.5 data and overwrite Arena reward entries and base NPC victory RP. Mods editing the same data may conflict. Drop probabilities, defeat penalties, and PVP RP are unchanged.

Sweep usage is stored separately for each world and player in `%LOCALAPPDATA%/Pal/Saved/BetterArena/`. Include this folder when backing up or transferring your saves.

Dedicated server usage records are stored in `Pal/Saved/BetterArena/` under the server directory, separately from client single-player records.

## 1.1.0 update

Added Windows dedicated-server sweeps with server-managed allowances, reward delivery, and actual reward receipts sent to clients. Fixed the sweep screen crash after returning from a server to single-player. Locked buttons now explain why sweeping is unavailable.
