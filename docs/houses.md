---
title: House robberies
sidebar_position: 4
---

# House robberies

Every house created in the [Creator](./creator.md) gets a `kora_target` box zone on its door. The door option depends on a state that is the same for every player.

| State | Door option | Meaning |
| --- | --- | --- |
| Available | Break in | A break-in is possible if the checks below pass |
| Open | Enter | Someone broke in; anyone can walk in with no items for `defaults.robberyTime` |
| Cooldown | Recently robbed | Nobody can enter for the house's cooldown minutes, then it is available again |

States are kept in server memory and are lost on resource restart.

## Break-in checks (server)

1. The player is within 4.0 units of the door and not rate limited (2 s per player).
2. The shell has a setup with an exit.
3. The state is not cooldown and the player is not already inside.
4. When the state is available: the house hours (server clock) allow it, the number of on-duty players with the job `defaults.policeJob` is at least the house minimum police, and the player has the break-in item (house item, else shell item, else `defaults.breakItem`) plus the security item when the house has the security system on.
5. If `defaults.consumeBreakItem` is true the break-in item is removed. The state becomes Open and a security house triggers the `kora_robberies:houseAlert` server event.

Entering an already Open house skips the item, police and hour checks and consumes nothing. The client plays a progress bar (`defaults.breakTime`, `defaults.breakAnim`) before asking the server.

## Inside

The client spawns the shell through the config spawn function below the door (`lowerZ`), places props relative to it and adds an exit zone labelled Leave. Props without a model become box targets. Only props with an item list that has items are searchable.

- A prop is searched by one player at a time and once per robbery.
- The server uses the saved search time, label, animation and blocked controls, not values from the client. Finishing more than 1 second faster than the duration is refused as too fast.
- A finished search gives one random entry of the list with its amount. If the player cannot carry it the prop is released again.
- When `defaults.robberyTime` ends everyone inside is sent out and the cooldown starts. Leaving does not end the robbery, and searched props stay searched.
- Players who disconnect or leave release any prop they were searching.

Police are counted with `playerJob()` in `server/_functions.lua`, which reads `job.name` and `job.onduty` from `exports.kora_core:getPlayer`. If the job cannot be read a one-time warning is printed and no police are counted.
