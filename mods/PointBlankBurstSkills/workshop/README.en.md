# Point-Blank Burst Skills

1.1.0 · ourongxing

Makes Pals move close to their target before using Volcanic Rain, Rockburst, or Poison Shower.

## Features and usage

Pals must be within approximately 0.5 m of their target to use these three skills automatically. Power, cooldowns, attack areas, and damage detection keep their original values.

## Installation

1. Subscribe to and enable the required mods: UE4SSExperimentalPW, PalSchema.
2. Enable this mod in the game's Mod Management menu.
3. Fully exit the game, then launch it again.

## Configuration

Edit `Mods/NativeMods/UE4SS/Mods/PalSchema/mods/PointBlankBurstSkills/raw/point_blank_burst_skills.json` under your Palworld installation, save your changes, then fully exit and restart the game.

`MaxRange` sets the maximum activation distance for automatic use. The default is 50 game units, approximately 0.5 m.

## Before you play

If another enabled mod changes the activation range of these skills, the result depends on load order.
