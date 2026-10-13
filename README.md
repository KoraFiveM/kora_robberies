# qbrobberies: house robbery creator

Staff run `/houseCreator` (needs the ace set in `Config.Creator`, `command` by default).

1. **Item lists**: make a list of items and amounts once (e.g. Kitchen) and reuse it on any prop.
2. **Shells**: pick a shell from `config.lua`, enter it, aim where the exit goes, then aim and place props and give each one an item list. Props are saved relative to the shell.
3. **Houses**: pick a shell and aim at each door; keep placing to make many houses in one go. Houses are named for you (`Tier 1 House 1`) and can be renamed. The house uses that shell's saved setup. Each house has its own minimum police, cooldown, security flag and optional hours.

Everything is saved in MySQL (`sql/qbrobberies.sql`, the tables are also created on start).
This resource is the creator only: entering a house and searching its props is not built yet.

Shell keys come from the label in `config.lua` ('Tier 1 House' -> `tier_1_house`). Do not reword a label after saving a setup for it.
`client/shell.lua` is the only file that knows what a spawned shell looks like.
