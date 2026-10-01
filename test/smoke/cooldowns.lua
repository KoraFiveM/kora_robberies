local H = dofile('test/harness.lua')
local callbacks, events, hooks, timers = {}, {}, {}, {}
local now, cash, items, succeed, roll, onReward = 0, 0, 0, true, 0, nil
local doors = { vault = true }
QB = {
    util = { deepClone = function(value) return value end },
    callback = { register = function(name, fn) callbacks[name] = fn end },
}
Config, QbRobberies = {}, {}
GetCurrentResourceName = function() return 'qbrobberies' end
GetGameTimer = function() return now end
GetResourceState = function() return 'started' end
RegisterNetEvent = function(name, fn) events[name] = fn end
AddEventHandler = function(name, fn) hooks[name] = fn end
SetTimeout = function(_, fn) timers[#timers + 1] = fn end
TriggerClientEvent = function() end
CreateThread = function() end -- The SQL bootstrap is outside this offline regression.
local function grant(kind, amount)
    if onReward then local fn = onReward; onReward = nil; fn() end
    if not succeed then return false end
    if kind == 'money' then cash = cash + amount else items = items + amount end
    return true
end
exports = {
    qbcore = {
        getPlayersByJobType = function() return {} end,
        addMoney = function(_, _, _, amount) return grant('money', amount) end,
        addItem = function(_, _, _, amount) return grant('item', amount) end,
    },
    qbdispatch = { createCall = function() return true end },
    qbdoorlock = {
        getDoorState = function(_, id) return doors[id] end,
        setDoorState = function(_, id, locked) doors[id] = locked; return true end,
    },
}
local originalRandom = math.random
math.random = function(low) return low or roll end
dofile('config.lua')
dofile('shared/schema.lua')
dofile('server/state.lua')
local State = QbRobberies.state
State.at = function() return true end -- Host proximity is fixed; cooldown logic remains real.
dofile(arg[1] or 'server/main.lua')
State.ready = true
local S = QbRobberies.schema
local reward = { kind = 'money', name = 'cash', min = 100, max = 100, chance = 100 }
local definition = assert(S.normalise({
    id = 'test', label = 'Test robbery', enabled = true, cooldown = 3600, minPolice = 0,
    start = { x = 0, y = 0, z = 0 }, startDoors = { 'vault' },
    steps = {
        { kind = 'search', label = 'First reward', coords = { x = 0, y = 0, z = 0 }, duration = 1000, rewards = { reward } },
        { kind = 'search', label = 'Last reward', coords = { x = 0, y = 0, z = 0 }, duration = 1000, rewards = { reward } },
    },
}))
State.definitions.test = definition
local start = callbacks['qbrobberies:server:start']
local begin = callbacks['qbrobberies:server:beginStep']
local finish = callbacks['qbrobberies:server:finishStep']
local function startRun()
    H.ok(start(1, 'test'), 'a robbery starts when no cooldown is active')
    H.equal(doors.vault, false, 'the normal start still unlocks its configured door')
end
local function finishStep(index)
    local pending = assert(begin(1, 'test', index))
    now = now + pending.duration
    return finish(1, 'test', index, pending.token)
end
local function abandon()
    source = 1
    events['qbrobberies:server:abandon']('test')
end
local function rejectRestart()
    local result, err = start(1, 'test')
    H.rejects(result, err, 'a paid early step prevents an immediate restart')
    H.ok(err:find('Available again', 1, true), 'the existing cooldown rejection is preserved')
end
local function expireCooldown()
    now = State.cooldowns.test
end

startRun()
local first = assert(finishStep(1))
H.equal(first.complete, false, 'early rewards retain staged progression')
H.equal(#first.rewards, 1, 'the early successful reward is still returned')
H.equal(cash, 100, 'the early step still pays the configured amount')
abandon()
rejectRestart()
H.equal(doors.vault, true, 'abandonment still restores doors')
expireCooldown()
startRun()
local before = State.cooldowns.test
abandon()
H.equal(State.cooldowns.test, before, 'an unpaid abandoned attempt does not extend the cooldown')
startRun()
succeed = false
local failed = assert(finishStep(1))
H.equal(#failed.rewards, 0, 'a rejected reward is still omitted')
H.equal(State.cooldowns.test, before, 'failed rewards preserve the preceding cooldown')
abandon()
startRun()
succeed, roll = true, 1
definition.steps[1].rewards[1].chance = 0.01
H.equal(#assert(finishStep(1)).rewards, 0, 'a missed chance does not grant a reward')
H.equal(State.cooldowns.test, before, 'missed rewards do not impose a cooldown')
abandon()
definition.steps[1].rewards[1].chance, roll = 100, 0

for _, stop in ipairs({
    function() source = 1; hooks.playerDropped() end,
    function() timers[#timers]() end,
}) do
    startRun()
    H.ok(finishStep(1), 'an early reward is paid')
    stop()
    rejectRestart()
    H.equal(doors.vault, true, 'disconnect and timeout restore doors')
    expireCooldown()
end

startRun()
H.ok(finishStep(1), 'early paid step is accepted')
local complete = assert(finishStep(2))
H.equal(complete.complete, true, 'normal completion is preserved')
H.equal(State.cooldowns.test, now + definition.cooldown * 1000,
    'normal completion retains its full configured cooldown from completion time')
rejectRestart()
expireCooldown()

startRun()
onReward = function()
    abandon()
    rejectRestart()
end
H.ok(finishStep(1), 'a reward may finish after the session was abandoned during the provider call')
rejectRestart()
expireCooldown()
startRun()
succeed = false
before = State.cooldowns.test
onReward = function()
    abandon()
    rejectRestart()
end
H.equal(#assert(finishStep(1)).rewards, 0, 'an awaited failed reward remains unpaid')
H.equal(State.cooldowns.test, before, 'the temporary hold is released after an unpaid provider call')
startRun()
succeed = true
before = State.cooldowns.test
onReward = function()
    abandon()
    State.cooldowns.test = now + definition.cooldown * 1000 + 1234
end
succeed = false
H.equal(#assert(finishStep(1)).rewards, 0, 'an unpaid reward still returns no grants')
H.equal(State.cooldowns.test, now + definition.cooldown * 1000 + 1234,
    'an unpaid provider result cannot erase a newer cooldown')
expireCooldown()
startRun()
succeed = true
H.ok(finishStep(1), 'an early successful payout establishes a cooldown')
before = State.cooldowns.test
definition.steps[3] = assert(S.normaliseStep({
    kind = 'search', label = 'Extra step', coords = { x = 0, y = 0, z = 0 }, duration = 1000,
}))
succeed = false
H.equal(assert(finishStep(2)).complete, false, 'a failed later payout retains staged progression')
H.equal(State.cooldowns.test, before, 'a failed later payout preserves the earlier paid cooldown')
abandon()
rejectRestart()
definition.steps[3] = nil
expireCooldown()
startRun()
succeed = true
definition.steps[1].rewards[1].kind, definition.steps[1].rewards[1].name = 'item', 'goldbar'
H.ok(finishStep(1), 'item rewards are paid through the same flow')
H.equal(items, 100, 'item reward quantities are unchanged')
abandon()
rejectRestart()
expireCooldown()
definition.cooldown = 0
startRun()
H.ok(finishStep(1), 'a deliberately zero-cooldown robbery can reward a step')
abandon()
startRun()

-- A provider can suspend after pending is retired but before this step advances.
for index, scenario in ipairs({
    { kind = 'money', name = 'cash', paid = true },
    { kind = 'item', name = 'goldbar', paid = true },
    { kind = 'money', name = 'cash', paid = false },
}) do
    if index > 1 then startRun() end
    definition.steps[1].rewards[1].kind = scenario.kind
    definition.steps[1].rewards[1].name = scenario.name
    succeed = scenario.paid
    local beforeCash, beforeItems = cash, items
    local pending = assert(begin(1, 'test', 1))
    now = now + pending.duration
    onReward = function() coroutine.yield('reward') end
    local completion = coroutine.create(function() return finish(1, 'test', 1, pending.token) end)
    local ok, phase = coroutine.resume(completion)
    H.equal(ok, true, 'completion reaches the provider without an error')
    H.equal(phase, 'reward', 'the actual State.reward export boundary yields')
    H.equal(coroutine.status(completion), 'suspended', 'reward completion is still pending')
    H.equal(State.sessions.test.step, 1, 'the step has not advanced during payout')
    H.equal(cash, beforeCash, 'suspended money export has not paid')
    H.equal(items, beforeItems, 'suspended item export has not paid')
    local duplicate, err = begin(1, 'test', 1)
    H.rejects(duplicate, err, 'a pending reward cannot begin the same step again')
    H.equal(err, 'That step cannot be started now.', 'busy begin retains the existing rejection shape')
    duplicate, err = finish(1, 'test', 1, pending.token)
    H.rejects(duplicate, err, 'a pending reward cannot be collected again')
    H.equal(callbacks['qbrobberies:server:cancelStep'](1, 'test', 1, pending.token), false,
        'cancellation cannot restore the retired pending authorization')
    local resumed, result = coroutine.resume(completion)
    H.equal(resumed, true, 'one reserved completion resumes normally')
    H.equal(coroutine.status(completion), 'dead', 'completion has finished')
    H.equal(result.complete, false, 'an early payout retains staged progression')
    H.equal(result.step, 2, 'one completion advances exactly one step')
    H.equal(#result.rewards, scenario.paid and 1 or 0, 'successful and failed provider result shapes remain unchanged')
    H.equal(cash, beforeCash + (scenario.kind == 'money' and scenario.paid and 100 or 0), 'money is granted once')
    H.equal(items, beforeItems + (scenario.kind == 'item' and scenario.paid and 100 or 0), 'items are granted once')
    succeed = true
    H.equal(assert(finishStep(2)).complete, true, 'the next step remains usable after the provider settles')
    H.equal(State.sessions.test, nil, 'normal completion still retires its session')
    H.equal(doors.vault, true, 'normal completion still restores the door')
end
math.random = originalRandom
H.finish('cooldowns')
