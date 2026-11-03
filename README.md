# qbrobberies: house robbery creator

Staff run `/houseCreator` (needs the ace set in `Config.Creator`, `command` by default).

1. **Item lists**: make a list of items and amounts once (e.g. Kitchen) and reuse it on any prop.
2. **Shells**: pick a shell from `config.lua`, enter it, aim where the exit goes, then aim and place props and give each one an item list. Leave the prop model empty to place a box target (no prop) where you aim instead. Props are saved relative to the shell.
   Each prop has its own target label, progress text, search time, animation (dictionary, clip, flag) and the controls that are blocked while searching. New props start with `defaults.searchTime`, `defaults.searchAnim` and `defaults.searchDisable` (5000 ms, `mp_arresting` / `a_uncuff` / 49, vehicle + movement + combat). Change them when placing, or later with *Search settings* on the prop's card. The server uses the saved values, not what the client sends when a search starts.
3. **Houses**: pick a shell and aim at each door; keep placing to make many houses in one go. Houses are named for you (`Tier 1 House 1`) and can be renamed. The house uses that shell's saved setup. Each house has its own minimum police, cooldown, security flag and optional hours.

Everything is saved in MySQL (`sql/qbrobberies.sql`, the tables are also created on start).

## Robbing a house
- Every house door gets a **Break in** target. It needs the break-in item: the shell's default (`defaults.breakItem` in the config unless you set one on the shell), or the house's own. A house with the security system on also needs the security item and sends `TriggerEvent('qbrobberies:houseAlert', { house, label, coords })` on break-in. `server/alerts.lua` listens to it and calls `kora_dispatch:createCall` (code `alerts.dispatch.houseCode`); keep listening to the event if you want more.
- The server checks the minimum police, the allowed hours and the state, and a house's state is lost when the resource restarts (every house is available again).
- Every house is in one of three states, the same for every player, and its door target shows it:
  - **Available**: **Break in**. A player needs the items, enough police and the right hours.
  - **Open**: **Enter**. Someone broke in, so anyone can walk in with nothing, for `defaults.robberyTime` (15 minutes). Leaving does not end it, and a prop that was searched stays searched. When the time is up everyone still inside is sent out.
  - **Cooldown**: **Recently robbed**. Nobody can get in for the house's cooldown (the house setting in the creator). Then it is available again.
  Each prop can be searched by one player at a time, once per robbery.
- The break-in item is used up (`consumeBreakItem`). Searching gives one item from the prop's list, picked at random (with that item's amount), or nothing if the player cannot carry it.
- Hours use the server's clock. Police are counted with `playerJob()` in `server/_functions.lua`; fix that one function if your framework reads jobs differently.

Shell keys come from the label in `config.lua` ('Tier 1 House' -> `tier_1_house`). Do not reword a label after saving a setup for it.
`client/shell.lua` is the only file that knows what a spawned shell looks like.

## Stores (from qbstorerobbery)
Build them in `/houseCreator` on the **Stores** page. A store has a name, its own **minimum police**, **registers** and **safes**.
- **Registers:** aim and place as many as you like. A register uses the same settings as a prop (target text, progress text, time, animation, blocked controls) and has its own **sticky note chance**. Robbing one is a progress bar, then the skill check (`qb-minigames`, skipped if it is not running), then cash.
- **Safes:** aim and place. A sticky note carries the store's safe code, which opens any safe in that store. Without it, **Blow Up Safe** uses a thermite and, when it has burned, **Retrieve Loot** gives the cash.
- A robbed register or safe stays empty for `resetTime`. Cash amounts, items and the thermite time are in `Config.Robberies.Store.defaults`.
- Run `sql/qbrobberies.sql` (the stores table is also created on start). To import only the 19 stores that came from qbstorerobbery, run `sql/stores_seed.sql`: it is safe to run again and never overwrites a store you edited.
- Starting a register robbery, blowing a safe or opening it with the code alerts police through `kora_dispatch` (`alerts.dispatch.storeCode`), at most once per store every `alerts.dispatch.cooldown` ms. `alerts.dispatch.enabled = false` turns every robbery alert off; `stores.enabled = false` turns store robberies off.
- Settings are in `/config` (`Kora.config.adopt`); the shell list and the creator ace stay in `config.lua` only.
- The server checks the distance, the police and who is robbing what. Only positions and settings go to players; the chances and the safe code never do.
