---
title: Creator
sidebar_position: 3
---

# Creator

Run `/robberyCreator` (or the command set in `Config.Creator.command`) as an admin. The **Robbery Creator** app has four pages. Every change is validated and saved by the server; the client never writes to the database.

## Item lists

Create a named list (up to 100 lists). Search all shared items by name or label (up to 24 results shown), add them with an amount (1 to 1000), edit or remove entries. A list holds at most 30 different items. Deleting a list also clears it from every prop that used it.

## Shells

Shells come from `Config.Robberies.House.shells`. Pick one, then **Enter the shell to edit**:

- **Exit** - aim where the exit should be and set it. A house whose shell has no exit cannot be robbed.
- **Props** - enter a prop model and an item list, then aim and place. Leave the model empty to place a box target (no prop) instead. Positions are stored relative to the shell. Up to 100 props per shell.
- **Per-prop settings** - target label, progress text, search time (500 to 300000 ms), animation dictionary, clip and flag, and the controls blocked while searching (movement, combat, vehicle, car). New props start from the `defaults.search*` config values.
- **Break-in item** - an item that overrides `defaults.breakItem` for every house on this shell.
- **Clear setup** - deletes the whole setup for the shell.

The shell key is made from its config label (`Tier 1 House` becomes `tier_1_house`). Renaming a label detaches the saved setup. See [Configuration](./configuration.md).

## Houses

Pick a shell and aim at each door; keep placing to make many houses. Names default to the shell label plus a number and can be renamed. Per house:

| Setting | Range / meaning |
| --- | --- |
| Name | up to 48 characters |
| Minimum police | 0 to 100 |
| Cooldown | 0 to 1440 minutes (0 means no cooldown) |
| Security system | needs the security item and fires `kora_robberies:houseAlert` |
| Break-in item / Security item | optional per-house overrides (must exist in shared items) |
| Shell depth | -300 to 0, how far below the door the shell is spawned (default `defaults.lowerZ`) |
| Robbery times | any time, or from and to hour (0 to 23, may span midnight) |

The entrance can be moved with **Aim and move the entrance**. Players reload door zones whenever a house is saved or deleted.

## Stores

Create a store, set its name and minimum police (0 to 100), then aim and place registers (up to 20) and safes (up to 10). Each register has the same search settings as a prop (shown as robbery settings) plus a **sticky note chance** from 0 to 100 percent. Safes have a position and heading only. Saved changes reload store zones for all players and reset that store's runtime state.

## Placement

Placement uses `Kora.raycast.getCoords` at the aimed point. The menu closes while you place and reopens afterwards. Leaving the resource while inside a shell leaves the shell.
