---
title: Events and callbacks
sidebar_position: 10
---

# Events and callbacks

The resource has no exports. All names below are internal except `kora_robberies:houseAlert`.

## Event for other resources

| Event | Side | Payload |
| --- | --- | --- |
| `kora_robberies:houseAlert` | server (local `TriggerEvent`) | table with `house` (id), `label` and `coords`, fired when a security-system house is broken into |

## Net events (client to server)

| Event | Payload | Behaviour |
| --- | --- | --- |
| `kora_robberies:prop:cancel` | house id, prop index | Frees a prop the sender was searching |
| `kora_robberies:register:cancel` | store id, register index | Frees a register the sender was robbing |

## Net events (server to client)

Handlers ignore anything not sent by the server.

| Event | Payload | Behaviour |
| --- | --- | --- |
| `kora_robberies:creator:open` | none | Opens the creator |
| `kora_robberies:client:reload` | none | Reloads house doors |
| `kora_robberies:client:reloadStores` | none | Reloads store zones |
| `kora_robberies:client:state` | house id, state, remaining ms | Updates a door state |
| `kora_robberies:client:closed` | house id | Sends the player out of the house |
| `kora_robberies:client:prop` | house id, index, state | Updates a prop state (busy, looted, free) |
| `kora_robberies:client:store` | store id, kind, index, name | Updates a register or safe state |

## Callbacks (`Kora.callback`)

| Callback | Purpose |
| --- | --- |
| `kora_robberies:world` | Houses with coords and state |
| `kora_robberies:breakin` | Break in or enter a house |
| `kora_robberies:leave` | Leave a house session |
| `kora_robberies:prop:begin`, `kora_robberies:prop:finish` | Start and finish a prop search |
| `kora_robberies:stores` | Store positions and state |
| `kora_robberies:register:begin`, `kora_robberies:register:finish` | Register robbery |
| `kora_robberies:safe:code`, `kora_robberies:safe:blow`, `kora_robberies:safe:loot` | Safe actions |
| `kora_robberies:creator:get` | Full creator payload |
| `kora_robberies:creator:lists:create`, `:items`, `:search`, `:delete` | Item list editing |
| `kora_robberies:creator:shells:exit`, `:props`, `:breakItem`, `:clear` | Shell setup editing |
| `kora_robberies:creator:houses:create`, `:details`, `:coords`, `:delete` | House editing |
| `kora_robberies:creator:stores:create`, `:details`, `:registers`, `:safes`, `:delete` | Store editing |

Player actions are rate limited per player (break-in 2 s, search and register 0.5 s, safe actions 1 s). Creator callbacks require the admin ACE.

## FFT hooks

`fft_hooks_server.lua` is loaded last and returns immediately unless the convar `fft_kora_hooks` is `true`. When enabled it exports `fftVersion` and `fftAction`; `fftAction` only works when called by the resource named `fft` for a player whose state bag `fftSession` is a string. Actions: `house`, `store` (read-only summaries), `claim`, `cooldown` (30 to 300 seconds) and `reset`, all limited to untouched houses claimed by that tester. Use is for automated testing only.

## Events from other resources

`playerDropped` is listened to on the server to release props, registers and rate limit entries.
