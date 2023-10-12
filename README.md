# FezzedTech

This mod includes scripts and tech that allow the use of my custom items as intended. For non-Steam downloads and `/spawnitem` commands, see the releases.

## Requirements

Some features of this mod require xSB-2 xClient, OpenStarbound, StarExtensions 1.9.11+, or `starlight` v1.0+:

- xSB-2 is available [here](https://github.com/FezzedOne/xSB-2/releases).
- OpenStarbound is available [here](https://github.com/OpenStarbound/OpenStarbound).
- StarExtensions is available [here](https://github.com/StarExtensions/StarExtensions/releases).
- `starlight` is available [here](https://gitee.com/erodeesfleurs/starlight/releases).

If you're not on Windows, use xSB-2 or OpenStarbound, or use WINE to play `starlight` or Starbound with StarExtensions.

## Keybinds

FezzedTech comes with the following keybinds:

- **Sitting:** Press `G` (by default) to sit. Should be obvious what this one does.
- **Roleplay mode:** Press `Z` (by default) to activate roleplay mode. In this mode, your character has a more "realistic" jump height, but can still climb onto platforms, blocks and objects just above him if next to them.
- **Roleplay ruler:** Press `X` by default to activate the roleplay ruler. This ruler gives distances from your character in metres and feet, and also gives a GURPS range modifier. Currently doesn't work on OpenStarbound.

These keybinds require xSB-2, OpenStarbound or StarExtensions. If using xSB-2 or OpenStarbound, you can rebind this key in the **Mod Binds** dialogue. StarExtensions users must type in `/binds` while in game to access the dialogue.

## Built-in commands

This mod adds four built-in commands for in-game dice rolling:

- `/roll:` Rolls dice. Takes the following arguments: `[dice] <is public> <comment>`. Dice are in "dice + adds" format; both addition and subtraction are currently supported, but not multiple "adds" or other arithmetical operations. If you specify the die size as only "d" (with no size number), it defaults to d6 (this is standard GURPS notation).
- `/rab:` Rolls dice multiple times and tallies them up. Takes the following arguments: `[number of rolls] [dice] <is public> <comment>`. Dice are in "dice + adds" format (see above).
- `/ra:` Makes a GURPS skill or stat roll. Takes the following arguments: `[skill or stat value] <is public> <comment>`. The skill or stat value is a simple integer; no arithmetic is currently supported. Critical failures and successes are handled as per standard GURPS rules.
- `/raba:` Makes multiple GURPS skill or stat rolls. Takes the following arguments: `[number of rolls] [skill or stat value] <is public> <comment>`. See above.

The last two *optional* arguments to all the above commands are explained below:

- `<is public>:` Takes any of the following values: `local`, `global`, `party`, `none`. If any other value is specified, this argument is skipped (defaulting to `no`) and the value is parsed as a `<comment>` instead (see below). If `no`, only you see the results of the dice roll. If `local`, the roll is automatically posted in local chat. If `global`, it's posted in global chat. If `party`, it's posted in party chat.
- `<comment>:` An optional comment for the roll which shows up in the roll message. If you're using StarExtensions, surround the argument with quotes if the comment has spaces in it. If using xSB, no quotes are required (and in fact they'll show up in the message).

The commands require xSB v2.0.0+ or StarExtensions to work.

## Uninstallation

Make sure not to have FezzedTech or any of the "empty" techs equipped before uninstalling this mod (or use [this mod](https://steamcommunity.com/sharedfiles/filedetails/?id=2127561004)).

## Redistribution and modification

This mod is under the MIT licence. I.e., you may freely redistribute or modify the mod and its associated items as you see fit. Just please make sure to credit me, alright?

## Helpful links

- **Discord server:** [https://discord.gg/S46Gk2t](https://discord.gg/S46Gk2t)
