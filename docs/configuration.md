---
title: Configuration
sidebar_position: 9
---

# Configuration

Everything is in `config.lua`, plus fixed limits in `shared/constants.lua`. Durations in `config.lua` are milliseconds.

## `Config.Robberies.House.defaults`

| Option | Default | Meaning |
| --- | --- | --- |
| `minPolice` | `0` | Minimum police for new houses |
| `cooldown` | 15 minutes | Cooldown for new houses (stored in minutes) |
| `robberyTime` | 15 minutes | How long a broken-into house stays open to everyone |
| `lowerZ` | `-20` | Default depth below the door where the shell spawns |
| `debug` | `false` | Prints debug counts on the client |
| `breakItem` | `lockpick` | Break-in item unless shell or house overrides it |
| `securityItem` | `electronickit` | Extra item for security-system houses |
| `consumeBreakItem` | `true` | Remove the break-in item on success |
| `breakTime` | `8000` | Break-in progress bar |
| `searchTime` | `5000` | Starting search time for new props |
| `searchLabel` | `Searching...` | Starting progress text |
| `policeJob` | `police` | Job name counted as police |
| `breakAnim` | `missheistfbisetup1` / `hassle_intro_loop_f`, flags 49 | Break-in animation |
| `searchAnim` | `mp_arresting` / `a_uncuff`, flag 49 | Starting prop animation |
| `searchDisable` | vehicle, move, combat | Starting blocked controls |
| `maxSteps`, `maxProps` | `20`, `30` | Not read anywhere in the resource (dead options). The real prop limit is `Limits.props` |

`searchTime`, `searchLabel`, `searchAnim` and `searchDisable` are only starting values for new props and registers; saved entries keep their own.

## `Config.Robberies.House.shells`

A list of entries with a `label` and a `spawn(coords)` function that returns a table with `id` (the shell handle, or a table whose first entry is) and `exit`. The defaults call `kora_interior` exports. Each label becomes a key (lower case, non-alphanumerics to underscores, truncated to 36 characters, numbered on duplicates). Keep labels stable once setups are saved.

## `Config.Creator`

| Option | Default | Meaning |
| --- | --- | --- |
| `command` | `robberyCreator` | Chat command name |
| `ace` | `command` | ACE permission checked for the command and every creator callback |

## `Config.Robberies.Store.defaults`

| Option | Default | Meaning |
| --- | --- | --- |
| `minPolice` | `2` | Minimum police for new stores |
| `resetTime` | 30 minutes | Empty time for robbed registers and safes, also sticky note code lifetime |
| `stickyNoteChance` | `10` | Percent for new registers |
| `registerCash` | 50 to 200 | Register payout range |
| `safeCash` | 500 to 1000 | Safe payout range |
| `blowTime` | 5000 to 10000 | Thermite burn time |
| `cashItem`, `stickyNoteItem`, `thermiteItem` | `cash`, `stickynote`, `thermite` | Item names |

## Limits (`shared/constants.lua`)

100 lists, 30 items per list, amount up to 1000, 100 props per shell, 20 registers and 10 safes per store, 24 search results.
