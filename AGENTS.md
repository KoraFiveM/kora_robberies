# kora_robberies agent guide

`kora_robberies` is a Kora robbery resource with an in-game creator: staff build item lists, shell setups, houses and stores in a `kora_lib` NUI app (`/robberyCreator`), and players rob houses (props inside spawned shells) and stores (registers and safes). Layout: `fxmanifest.lua`, `config.lua`, `shared/` (limits, shell keys), `server/` (schema and seed data, validation in `rules.lua`, data store, creator callbacks, house and store robbery logic), `client/` (creator app, shell spawning, house and store interaction), `fft_hooks_server.lua` (optional test hooks), `items/` (item definitions), `test/` and `tests/`.

## Documentation

User-facing documentation lives in `docs/` (Markdown, published via the Kora Docusaurus site, kora_docs_next). Read `docs/index.md` first for an overview of features, configuration, commands, exports, events and database usage.

When you add, change, or remove a feature, config option, command, export, event, item, permission, or database table/column, update the matching page in `docs/` in the same change. Keep docs accurate to the code; do not document behaviour that does not exist.

Docs rules: plain Markdown with `title`/`sidebar_position` front matter (no `id`/`slug`), relative links only between docs pages, assets inside `docs/`, fenced code blocks with a language, and no raw `<`, `>`, `{`, `}` outside code (pages are parsed as MDX). The release version comes from `fxmanifest.lua`'s `version` field.
