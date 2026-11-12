---
title: Commands and permissions
sidebar_position: 7
---

# Commands and permissions

| Command | Access | Effect |
| --- | --- | --- |
| `/robberyCreator` | ACE from `Config.Creator.ace` | Opens the Robbery Creator on the caller's client |

The name comes from `Config.Creator.command`. It is registered with `Kora.commands.add` and has a permission check that calls `IsPlayerAceAllowed(source, Config.Creator.ace)`. The default ACE is `command`, which depends on how your `server.cfg` grants it. Use a dedicated ACE for finer control:

```cfg
add_ace group.admin kora_robberies.creator allow
```

then set `ace = 'kora_robberies.creator'` in `Config.Creator`.

Every creator callback (`kora_robberies:creator:*`) re-checks the same ACE on the server and refuses with Admin permission required, so opening the UI some other way does not bypass it. The console (source 0) is not treated as an admin by those callbacks.

Older README text mentions `/houseCreator`; the real command is `Config.Creator.command`.
