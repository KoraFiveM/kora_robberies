---
title: "How to use"
sidebar_position: 3
---


# How to use

There are two separate player-facing systems sharing one creator tool and one set of database tables: house break-ins (with searchable loot props) and store robberies (registers and safes). Everything players interact with — which houses exist, what shell layout they use, what each prop drops — is authored through `/robberyCreator`, not through `config.lua`.

## Configuration shape

`config.lua` only holds system-wide defaults, the list of available shell layouts (interiors from kora_interior), and the creator command/ACE. Individual houses, stores, item lists and per-shell prop setups all live in the database and are edited in-game.

```lua title="config.lua"
Config.Robberies.House.defaults = {
    minPolice = 0,
    cooldown = 15 * 60 * 1000,   -- ms a broken-into house stays empty for everyone after it is next closed
    robberyTime = 15 * 60 * 1000, -- ms a broken-into house stays OPEN to any player once someone gets in
    breakItem = 'lockpick',         -- consumed on a successful break-in, unless the shell or house overrides it
    securityItem = 'electronickit', -- also required/consumed when a house has 'security' on
    consumeBreakItem = true,
    breakTime = 8000,  searchTime = 5000,
    policeJob = 'police',
}
Config.Robberies.Store.defaults = {
    minPolice = 2,
    resetTime = 30 * 60 * 1000,
    stickyNoteChance = 10,      -- % chance a robbed register also gives the safe code
    registerCash = { min = 50, max = 200 },
    safeCash = { min = 500, max = 1000 },
    blowTime = { min = 5000, max = 10000 },
    cashItem = 'cash', stickyNoteItem = 'stickynote', thermiteItem = 'thermite',
}
```

## Database tables and seed data

Four tables, each `(id varchar(48) primary key, data longtext)` holding a JSON blob: `kora_robberies_houses`, `kora_robberies_lists`, `kora_robberies_shells`, `kora_robberies_stores`.

- Seeding is explicitly marked `once = true` in `server/data.lua` before the schema is applied (`for _, spec in ipairs(KoraRobberiesSchema) do if spec.seed then spec.seed.once = true end end`), and kora_sql only runs a `seed.once` table's INSERT when its `ensureTables` report says the table was just created (`!report.created` skips it). In practice this means: on a brand-new database the seed rows (108 houses, 11 item lists, 6 shells, 19 stores) are inserted once; on every later boot, including after this resource is upgraded, those rows are left exactly as they are in the live database. A config code change can only affect what a *newly created* table gets seeded with — it cannot retroactively fix rows already sitting in an existing database.
- All data is loaded into memory at boot (`Lists`, `Setups`, `Houses`, `Stores` tables in `server/data.lua`) and kept there; every read (break-in checks, the creator UI, the player-facing house/store lists) works off this cache, refreshed by the same process's own writes. `DataLoaded` only becomes true after the whole load succeeds, and callbacks that depend on it return `false` until then so a client retries rather than seeing a half-loaded world.

## The seed-data break-in-item casing issue (fixed going forward, not retroactively)

```lua title="server/schema.lua + server/rules.lua"
-- server/schema.lua seed rows (kora_robberies_houses), as shipped today:
{ id = "furnished_mid_apartment_10", data = "{\"breakItem\":\"advancedlockpick\", ...}" }

-- server/rules.lua: how a saved house row is read back.
function readHouse(id, raw)
    local stored = decodeJson(raw, {})
    ...
    return cleanHouseDetails({
        ..., breakItem = stored.breakItem, securityItem = stored.securityItem, ...
    }, { shell = stored.shell, coords = coords })
end
```

- A house row's difficulty-relevant break-in item is read from the JSON field `breakItem` (exact case) by `readHouse` in `server/rules.lua` — `stored.breakItem`. Lua's `json.decode` preserves JSON key casing exactly, so a row whose JSON used any different casing for that key (for example a lowercase or differently-capitalised variant) would decode to a table with no `breakItem` field at all; `stored.breakItem` would then read as `nil`.
- When a house has no `breakItem` of its own, `requiredItems()` in `server/robbery.lua` falls through to the shell's own `breakItem` and finally to `Config.Robberies.House.defaults.breakItem` (`'lockpick'`, the easiest/baseline break-in item) — so a row silently missing its intended harder item (for example `advancedlockpick` or `hacking_laptop`) would quietly accept the easy default instead, with no error anywhere.
- This was a seed-data bug affecting the bulk of the shipped house rows and has been corrected going forward: every row in the current `server/schema.lua` seed data uses the exact, consistent key `breakItem`. Because seeding only ever runs once per table (see above), **this fix only benefits a table created fresh from this version of the resource.** An existing live database that was already seeded under an older version may still carry rows with the old, wrongly-cased key, which will keep silently defaulting to the easy break-in item until someone re-saves those houses through the creator (which rewrites the row with the current, correct field name) or corrects the data directly.
- If you are running a live server from before this fix, check your `kora_robberies_houses` rows for a house whose intended difficulty does not match what players can actually use to break in — that is the symptom to look for.

## House break-ins

```text title="server/robbery.lua — the real fix"
-- server/robbery.lua: checkBreakIn() already validated the player holds the item(s).
-- The fix is that the house is only opened if the item is actually removed.
if defaults.consumeBreakItem and not exports['qb-inventory']:RemoveItem(src, needs[1].item, 1) then
    return false, 'You need: ' .. itemLabel(needs[1].item) .. '.'
end

session = { players = {}, props = {} }
Sessions[houseId] = session
setState(houseId, 'open', robberyTime)
```

- Houses get a door `kora_target` box zone from the player-facing dashboard (`kora_robberies:world`). Three states: `available` (Break in), `open` (Enter — already broken into within `Config.Robberies.House.defaults.robberyTime`), `cooldown` (Recently robbed, shows minutes left).
- Breaking in (`kora_robberies:breakin`) checks, in order: not on a 2-second anti-spam cooldown, the house and its shell setup exist and the shell has an exit point configured, the house is not already on cooldown, the player is not already inside, then — only if the house is not already `open` — the time-of-day window (`house.hours`), the configured minimum on-duty police (`PoliceOnDuty() >= house.minPolice`), and that the player actually holds the required break-in item(s) (the base item, plus the security item too if `house.security` is on).
- The break-in item is only consumed, and the house only opens, after the inventory removal actually succeeds.
- Once open, every player who interacts with the door can enter and loot; the house stays open for `robberyTime` from the *first* break-in, then goes on `cooldown` for `house.cooldown` minutes. If `house.security` is on, breaking in also fires the local event `kora_robberies:houseAlert` with the house id, label and coordinates — this resource does not handle that alert itself, so something else (for example a dispatch resource) must listen for it to actually notify police.
- Inside, each searchable prop is a `kora_target` entity (or a box zone, for a "prop" with no model — used as an invisible search spot) tied to an item list. Searching takes `prop.time` (or the shell default), can be cancelled, and gives one random item from the list's weighted-by-nothing (uniform) pick on completion; a prop can only be looted once per session.
- If a shell has no exit point configured yet, affected houses are flagged in the console at boot (and a player cannot enter them) until an admin sets one in the creator.

## Store robberies

- Each store has independent registers and safes, both gated by `store.minPolice` police on duty and 5 m proximity. State (busy/robbed/blown) is server-memory-only, keyed per store, and resets automatically `resetTime` milliseconds after it changes.
- Robbing a register takes a progress bar, pays a random amount in `defaults.registerCash`'s range as the configured cash item, then has a per-register `stickyChance`% of also giving a sticky-note item carrying a safe code (a random 4-9 digit number, regenerated whenever none is currently active for that store).
- A safe can be opened two ways: entering the correct code (`kora_robberies:safe:code`) or blowing it with thermite (`kora_robberies:safe:blow`, consumes the configured thermite item, burns for a random duration in `blowTime`'s range, then stays `blown` and lootable until someone takes the cash or it resets unclaimed). Either path pays a random amount in `safeCash`'s range.

## The in-game creator

An admin-only kora_lib AppShell app (`/robberyCreator`, gated by the ACE in `Config.Creator.ace`) with four sections: Item lists, Shells, Houses, Stores.

- Item lists: named lists of `{ item, amount }` entries (search the shared item catalog to add). Deleting a list also strips it from every shell prop that referenced it.
- Shells: for each configured interior layout (from `config.lua`), set its exit point (by standing where you want it and saving), its break-in item override, and place/edit its loot props (each with its own search time, animation and disabled controls, or left at the shell defaults).
- Houses: create a house at your current position against a chosen shell, then edit its label, minimum police, cooldown, break-in/security items, optional opening-hours window, and whether its security system (extra item + alert) is on.
- Stores: create a store, then place registers and safes (each register with its own sticky-note chance and search settings).
- Every creator action is server-validated against `shared/constants.lua`'s `Limits` (lists, items per list, props per shell, registers/safes per store) and against the live shared item catalog — an item name that does not exist in kora_core's shared items is rejected outright.

## Additional details from the code

- Breaking in also requires the player to be within 4 m of the house door (`server/robbery.lua:151`), and the check happens before the cooldown and item checks. Store registers and safes use a 5 m limit (`server/store.lua:61`).
- The seeded counts above (108 houses, 11 lists, 6 shells, 19 stores) match `server/schema.lua`.
- See [House robberies](./houses.md), [Store robberies](./stores.md) and [Creator](./creator.md) for the player and staff views in more detail, and [Configuration](./configuration.md) for every `config.lua` key.
