# QB Robberies

`qbrobberies` is a live, in-game robbery creator. Staff run `/robberies` and
use qblib's AppShell to create a robbery, place its start zone, create ordered
search/hack/drill steps, configure rewards, add qbdoorlock doors, and place
optional scenery. Each step can use a timed interaction alone or a
server-authorized hacking, skillbar, lockpick, or circuit challenge with easy,
standard, and hard presets. Definitions are persisted in MySQL and are live
immediately; there is no Lua configuration to edit and no restart after
authoring.

New robberies begin as drafts. The creator's readiness check requires a placed
start zone, at least one ordered step, and a reward on at least one step before
staff can enable it. Existing steps can be edited without losing their placed
location, rewards, or assigned doors.

## Gameplay

Players start a robbery at its start zone and complete each step in order. The
server owns every session and rechecks player distance, active-session lock,
on-duty police count, cooldown, completion timing, rewards, and the successful
qblib minigame proof. A robbery cannot have two concurrent runners.

Door ids are validated against `qbdoorlock` while authoring. Doors assigned to
the start or a step are unlocked only for the session and restored to their
prior state when it ends, times out, the runner leaves, or the player drops.

Robbery-start alerts are sent to `qbdispatch` when it is running; otherwise
on-duty LEO players receive a qblib notification.

## Strict entity lockdown

The only entities this resource creates are optional decorative props. They are
spawned through `QB.entities.create(..., { preset = 'static' })`, which qblib
creates as local, non-networked entities and cleans up automatically. No client
side networked entity is ever created, so this resource works with
`sv_entityLockdown strict`.

## Dependencies

`qbsql`, `qblib`, `qbcore`, and `qbdoorlock` are mandatory. `qbdispatch` is
optional but already trusted in this test server's dispatch configuration.
