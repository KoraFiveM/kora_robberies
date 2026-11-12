---
title: Items
sidebar_position: 12
---

# Items

Items are checked against the shared item list (`GetShared('Items')` from `qb-core` if available, else `kora_core:getShared('items')`). The creator refuses item names that do not exist, except entries already stored in a list.

## Used by configuration

| Item | Used for |
| --- | --- |
| `lockpick` | Default break-in item (consumed) |
| `electronickit` | Default security-system item (checked, not consumed) |
| `cash` | Register and safe payouts (as an inventory item) |
| `stickynote` | Given by registers, with metadata `code` |
| `thermite` | Consumed to blow a safe |

## Bundled examples

`items/qb.md` lists qb-style definitions with images in `items/` for `art_1` to `art_5`, `art_7`, `boombox`, `hacking_laptop`, `hacking_tablet`, `qbr_desktop`, `qbr_laptop`, `qbr_monitor` and `qbr_speakers`. The seeded lists also reference other items (for example `rolex`, `goldchain`, `trojan_usb`, `weapon_pistol`) and the seeded shells use `advancedlockpick` and `hacking_tablet` as break-in items. Define these in your item list or edit the lists in the creator.

Items given from a prop come from the saved item list; when the inventory refuses the item (full) the prop stays unsearched.
