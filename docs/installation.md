---
title: "Installation"
sidebar_position: 2
---


# Installation

Kora Robberies is an in-game content creator plus runtime for two kinds of robbery: breaking into houses built from reusable "shell" interiors with searchable loot props, and robbing store registers and safes. Everything a server operator configures — item lists, shell prop layouts, individual houses, individual stores — is created and edited in-game through an admin tool and stored as JSON blobs in four database tables. The resource ships with ~108 pre-built houses, 19 stores, 6 shell layouts and 11 item lists as seed data.

## Install Kora Robberies

1. **Add the folder** — Place `kora_robberies` in your resources directory (on the Kora recipe it is `resources/[kora]/kora_robberies`).

2. **Have its dependencies running** — The manifest declares `kora_lib`, `kora_sql`, `kora_core` and `kora_interior`. `kora_interior` supplies every shell-spawning function referenced in `config.lua` (`CreateApartmentShell`, `CreateTier1House`, `CreateTrevorsShell`, and so on) — the config will error at load if `kora_interior` is not running first.

3. **Note the inventory and target dependency** — The code also calls `exports['qb-inventory']` directly (`HasItem`, `RemoveItem`, `AddItem`) and `exports.kora_target` for zones and entity targets. These are not declared `dependency` entries in the manifest, so make sure a resource providing the `qb-inventory` export name (such as kora_inventory) and kora_target are both running before this one.

4. **Start it** — Tables are created and seeded automatically on first boot; there is nothing to run by hand.

   ```bash title="server.cfg"
   ensure kora_lib
   ensure kora_sql
   ensure kora_target
   ensure kora_inventory
   ensure kora_core
   ensure kora_interior
   ensure kora_robberies
   ```

5. **Open the creator** — In-game, a player with the ACE named by `Config.Creator.ace` (default `command`, i.e. the general console-command ACE) can run `/robberyCreator` (configurable via `Config.Creator.command`) to manage item lists, shell layouts, houses and stores.

## Manifest and load order

- Server scripts load in a fixed, dependency-respecting order: `server/schema.lua` (table + seed definitions) → `server/_functions.lua` (shared helpers: JSON decode, validation, `dbSave`/`dbRows`, cooldowns, police-on-duty counting) → `server/rules.lua` (input-cleaning functions used by both the creator and the loader) → `server/data.lua` (in-memory state, save/delete helpers, and the boot thread that creates tables and loads everything) → `server/creator.lua` (admin callbacks) → `server/robbery.lua` (house break-in gameplay) → `server/store.lua` (store gameplay).
- `client/main.lua` is present in the manifest but is an empty file — it contributes nothing.
- `shared/constants.lua` defines `Limits` (how many lists/items/props/registers/safes, etc. the creator allows) and `ProgressDisableOptions`/`DefaultSearch`. `shared/shells.lua` turns `Config.Robberies.House.shells` into an ordered, keyed list (`HouseShells`, `HouseShellByKey`) by slugging each shell's label into a stable key (for example "Tier 1 House" → `tier_1_house`) — renaming a shell's label later changes its key and orphans any house or shell-setup row saved under the old one.

## Dependencies in detail


Declared in `fxmanifest.lua`:

| Resource | Used for |
| --- | --- |
| `kora_lib` | NUI app, callbacks, notifications, progress bar, commands, raycast, entities |
| `kora_sql` | Table creation, seeding and queries |
| `kora_core` | Player data (`getPlayer`) and the shared items list (`getShared`) |
| `kora_interior` | The shell spawners called from `config.lua` (`CreateTier1House` and so on) |

Used in code but not declared as a dependency:

| Resource | Used for |
| --- | --- |
| `kora_target` | Door, prop, register and safe interaction zones (client) |
| An inventory exposing the `qb-inventory` exports | `HasItem`, `RemoveItem` and `AddItem`, called as `exports['qb-inventory']` on server and client |
| `qb-minigames` (optional) | `Skillbar()` after a register progress bar. If the call errors (not running) the skill check is skipped |
| `qb-core` (optional) | `GetShared('Items')` is tried first, with `kora_core` as fallback |
| `kora_inventory` | Item images in the creator are loaded from `nui://kora_inventory/images/` |

### Setup checklist

1. Put the resource in your resources folder and ensure it after its dependencies:

   ```cfg
   ensure kora_lib
   ensure kora_sql
   ensure kora_core
   ensure kora_interior
   ensure kora_target
   ensure kora_robberies
   ```

2. Give your admins the ACE named in `Config.Creator.ace` (`command` by default). See [Commands](./commands.md).
3. Add the items the resource uses to your item list. See [Items](./items.md). The bundled `items/qb.md` has entries for the art, electronics and boombox items.
4. On first start nothing needs importing: the four tables are created and seeded (see [Database](./database.md)).
5. Hook your dispatch to the `kora_robberies:houseAlert` server event if you use security-system houses. See [Events and callbacks](./events.md).

The resource tests (`test/schema.lua`, run from the resource directory with `lua test/schema.lua`) only check that the schema and seed rows are declared. `tests/checklist-crime.feature` holds manual `kora_qa` scenarios.
