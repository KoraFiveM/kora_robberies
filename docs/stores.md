---
title: Store robberies
sidebar_position: 5
---

# Store robberies

Stores are built on the Stores page of the [Creator](./creator.md). The server checks distance (5.0 units), the store's minimum police and who is robbing what. Runtime state is memory only and resets on resource restart or when the store is edited in the creator.

## Registers

1. The player selects the register target (default label Rob Register). The server starts a robbery with the register's saved duration, animation and blocked controls.
2. The client plays the progress bar, then the `qb-minigames` skillbar if it is running (it is skipped if the export errors).
3. The server pays random cash between `registerCash.min` and `registerCash.max` as the `cashItem` item. Finishing more than 1 second early is refused.
4. The register stays empty for `resetTime`. A player can only work on one register at a time, and one register is robbed by one player at a time.
5. After a successful register, the register's own sticky note chance rolls. A hit gives one `stickyNoteItem` with item metadata `code`.

## Safes

A safe target offers three options:

- **Enter Code** - the code in a sticky note opens any safe in that store. A correct code pays `safeCash` and empties the safe.
- **Blow Up Safe** - needs one `thermiteItem` (consumed on the server). The safe burns for a random time between `blowTime.min` and `blowTime.max`, then the client explodes it and the state becomes blown.
- **Retrieve Loot** - on a blown safe, after a 5 second progress bar, pays `safeCash`.

A blown safe that nobody loots closes again after `resetTime`. An emptied safe is available again after `resetTime`. The store's sticky note code (random 1000 to 999999999) is created when the first note drops, expires after `resetTime`, and is cleared when any safe in that store is emptied. Codes and chances are never sent to players.
