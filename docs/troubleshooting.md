---
title: Troubleshooting
sidebar_position: 13
---

# Troubleshooting

- **Creator says Admin permission required** - the player lacks the ACE in `Config.Creator.ace`.
- **Creator says data is still loading** - `kora_sql` was not ready or the database read failed; check the console for `[kora_robberies]` warnings and restart.
- **Nobody can get into a house** - its shell has no exit, or the shell is no longer in the config. The server prints a warning at start for houses without an exit.
- **Saved setup disappeared after editing the config** - a shell label was reworded, which changes its key. Restore the label or rebuild the setup.
- **Police are never counted** - `playerJob()` could not read `job` from `kora_core:getPlayer`; a warning is printed once. Adjust that function.
- **Props have no search target** - the prop has no item list, or the list is empty.
- **Items not given or missing** - the item is not in your inventory item list, or the inventory does not provide the `qb-inventory` exports.
- **House stays open or cooldown disappears after restart** - house and store state is memory only.
- **Register skill check never appears** - `qb-minigames` is not running; the check is skipped.
- **Texts are English only** - there are no locale files.
