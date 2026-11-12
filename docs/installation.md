---
title: Installation
sidebar_position: 2
---

# Installation

## Dependencies

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

## Steps

1. Put the resource in your resources folder and ensure it after its dependencies:

   ```cfg
   ensure kora_lib
   ensure kora_sql
   ensure kora_core
   ensure kora_interior
   ensure kora_target
   ensure kora_robberies
   ```

2. Give your admins the ACE named in `Config.Creator.ace` (`command` by default). See [Commands and permissions](./commands.md).
3. Add the items the resource uses to your item list. See [Items](./items.md). The bundled `items/qb.md` has entries for the art, electronics and boombox items.
4. On first start nothing needs importing: the four tables are created and seeded (see [Database](./database.md)).
5. Hook your dispatch to the `kora_robberies:houseAlert` server event if you use security-system houses. See [Events and callbacks](./events.md).

The resource tests (`test/schema.lua`, run from the resource directory with `lua test/schema.lua`) only check that the schema and seed rows are declared. `tests/checklist-crime.feature` holds manual `kora_qa` scenarios.
