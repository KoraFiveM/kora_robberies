---
title: Database
sidebar_position: 9
---

# Database

Declared in `server/schema.lua` and created by `Kora.sql.ensureTables` on start (no SQL import). Each table has two columns, `id` (`varchar(48)`, primary key) and `data` (`longtext`, JSON), collation `utf8mb4_general_ci`.

| Table | Row id | Stored JSON |
| --- | --- | --- |
| `kora_robberies_lists` | list id | `label`, `items` (array of `item`, `amount`) |
| `kora_robberies_shells` | shell key | `exit`, `props`, optional `breakItem` |
| `kora_robberies_houses` | house id | `label`, `shell`, `coords`, `minPolice`, `cooldown` (minutes), `security`, optional `hours`, `breakItem`, `securityItem`, `lowerZ` |
| `kora_robberies_stores` | store id | `label`, `minPolice`, `registers`, `safes` |

## Seeding

On the first start where a table does not exist, bundled example rows are inserted: 108 houses, 11 lists, 6 shell setups and 19 stores (checked by `test/schema.lua`). Existing tables are never re-seeded, so deleted rows stay deleted.

## Loading

After `kora_sql` is ready the server reads all tables, passing every row through the validators in `server/rules.lua`. Invalid rows are skipped or cleaned (unknown lists are removed from props). Shell rows whose key is not in the config are ignored. If the database cannot be read, `DataLoaded` stays false and creator callbacks answer that data is still loading. The client asks again for up to 20 attempts.

Writes use a select followed by an update or insert per row. Runtime robbery state is not stored.
