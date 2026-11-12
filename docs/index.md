---
title: kora_robberies
sidebar_position: 1
---

# kora_robberies

`kora_robberies` is a robbery resource for Kora servers with an in-game creator. Staff build everything in a `kora_lib` NUI app: **item lists**, reusable **shell setups** (searchable props inside an interior), **houses** (doors that lead into a shell) and **stores** (cash registers and safes). Players then break into houses, search props for items, rob registers and open safes. All limits, loot, police counts and timing are decided on the server.

Current version: see `version` in `fxmanifest.lua`.

## Features

- **Robbery creator** - `/robberyCreator` (admin only) opens the creator app. See [Creator](./creator.md).
- **Item lists** - named lists of item and amount pairs, reusable on any prop.
- **Shell setups** - per interior shell: an exit point, props or box targets that give a list, a per-shell break-in item.
- **House robberies** - doors with a Break in / Enter / Recently robbed target, shared Available / Open / Cooldown state, police and hour gating, optional security system. See [House robberies](./houses.md).
- **Store robberies** - registers (skill check, cash, sticky note chance) and safes (sticky note code or thermite). See [Store robberies](./stores.md).
- **Persistence** - everything is saved as JSON in four MySQL tables, created and seeded automatically. See [Database](./database.md).
- **Optional FFT test hooks** - inert unless the `fft_kora_hooks` convar is `true`. See [Events and callbacks](./events.md).

## Requirements

Declared in `fxmanifest.lua`: `kora_lib`, `kora_sql`, `kora_core`, `kora_interior`. Used but not declared: `kora_target`, an inventory that provides the `qb-inventory` exports, and optionally `qb-minigames`. Details in [Installation](./installation.md).

## Pages

- [Installation](./installation.md) - dependencies, server.cfg order, first start
- [Creator](./creator.md) - the staff app: lists, shells, houses, stores
- [House robberies](./houses.md) - how a house robbery works for players
- [Store robberies](./stores.md) - registers, safes and sticky notes
- [Configuration](./configuration.md) - `config.lua`, limits and defaults
- [Commands and permissions](./commands.md) - the creator command and its ACE
- [Events and callbacks](./events.md) - events, callbacks, FFT hooks
- [Database](./database.md) - tables and stored JSON
- [Items](./items.md) - items the resource uses
- [Troubleshooting](./troubleshooting.md) - common problems and limitations

The resource has no exports and no locale files (all text is English and written in the code).
