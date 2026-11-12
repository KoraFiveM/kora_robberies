---
title: "Commands"
sidebar_position: 4
---


# Commands

Kora Robberies registers one command, server-side, through kora_core's command system.

## Built-in commands

### `/robberyCreator`

Opens the robbery creator AppShell app for the calling player.

| Field | Details |
| --- | --- |
| Context | In-game · server command (kora_core) |
| Arguments | No arguments. |
| Access | The ACE named by `Config.Creator.ace` (default `command`). Checked both by kora_core's command permission system and again inside every individual creator callback (`isAdmin`), so the gate cannot be bypassed by calling a callback directly. |

**Example**

```text
/robberyCreator
```

**Result**

Opens the creator UI; with no permission, kora_core's own "no permission" handling applies and the UI never opens.

## Changing the command or permission

Set `Config.Creator.command` and `Config.Creator.ace` in `config.lua`. The ACE is passed straight to `IsPlayerAceAllowed`, so it can be any ACE name your `server.cfg` grants to a group, for example `command.robberyadmin`.

## Dedicated ACE, callbacks and notes

The command name comes from `Config.Creator.command`. It is registered with `Kora.commands.add` and has a permission check that calls `IsPlayerAceAllowed(source, Config.Creator.ace)`. The default ACE is `command`, which depends on how your `server.cfg` grants it. Use a dedicated ACE for finer control:

```cfg
add_ace group.admin kora_robberies.creator allow
```

then set `ace = 'kora_robberies.creator'` in `Config.Creator`.

Every creator callback (`kora_robberies:creator:*`) re-checks the same ACE on the server and refuses with Admin permission required, so opening the UI some other way does not bypass it. The console (source 0) is not treated as an admin by those callbacks.
