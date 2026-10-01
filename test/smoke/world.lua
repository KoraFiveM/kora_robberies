-- Run from qbrobberies: lua test/smoke/world.lua [world-source]
local H = dofile('test/harness.lua')
for _, order in ipairs({ { 1, 2 }, { 2, 1 } }) do
    local zones, events, hooks, calls, abandoned = {}, {}, {}, {}, {}
    local interact, text, serverStep = nil, nil, nil
    QB = {
        notify = { send = function() end },
        entities = { remove = function() end },
        zones = { sphere = function(options)
            local zone = { options = options, removed = false }
            zone.remove = function() zone.removed = true; return true end
            zones[#zones + 1] = zone
            return zone
        end },
        textui = {
            show = function(value) text = value; return 1 end,
            update = function(_, value) text = value end,
            hide = function() text = nil end,
        },
        keybind = { add = function(options) interact = options.onPressed end },
        progressbar = { start = function(payload) H.equal(payload.canCancel, true, 'step cancellation policy retained'); return true end },
        callback = { trigger = function(name, id, index)
            calls[#calls + 1] = { name = name, id = id, index = index }
            H.equal(id, 'test', 'only selected robbery reaches server callbacks')
            if name == 'qbrobberies:server:start' then serverStep = 1; return { id = id, step = 1, label = 'Test robbery' } end
            H.equal(index, serverStep, 'only current sequential step reaches server callbacks')
            if name == 'qbrobberies:server:beginStep' then return { token = 'token', duration = 1000, label = 'Step' } end
            if name == 'qbrobberies:server:finishStep' then serverStep = serverStep + 1; return { complete = serverStep > 2, step = serverStep, rewards = {} } end
            error('Unexpected callback ' .. name)
        end },
    }
    Config, QbRobberies = {}, {}
    vector3 = function(x, y, z) return { x = x, y = y, z = z } end
    CreateThread = function(fn) fn() end
    RegisterNetEvent = function(name, fn) events[name] = fn end
    AddEventHandler = function(name, fn) hooks[name] = fn end
    GetCurrentResourceName = function() return 'qbrobberies' end
    TriggerServerEvent = function(name, id) abandoned[#abandoned + 1] = { name = name, id = id } end
    dofile('config.lua')
    dofile('shared/schema.lua')
    local S = QbRobberies.schema
    local definition = assert(S.normalise({ id = 'test', label = 'Test robbery', start = { x = 0, y = 0, z = 0 }, props = {}, steps = {
        { kind = 'search', label = 'First', coords = { x = 0, y = 0, z = 0 }, duration = 1000 },
        { kind = 'search', label = 'Second', coords = { x = 0, y = 0, z = 0 }, duration = 1000 },
    } }))
    local other = assert(S.normalise({ id = 'other', label = 'Other robbery', start = { x = 0, y = 0, z = 0 }, props = {}, steps = {
        { kind = 'search', label = 'Other step', coords = { x = 0, y = 0, z = 0 }, duration = 1000 },
    } }))
    dofile(arg[1] or 'client/world.lua')
    local World = QbRobberies.world
    World.apply({ definition, other })
    zones[2].options.onEnter()
    for _, index in ipairs(order) do zones[index + 2].options.onEnter() end
    H.equal(interact(), nil, 'start key handler return retained')
    H.equal(World.nearbyStep.id, 'test', 'active robbery owns selected target')
    H.equal(World.nearbyStep.index, 1, 'first step selected regardless of enter order')
    H.equal(text, 'First [E]', 'first prompt is visible inside overlapping zones')
    zones[7].options.onEnter()
    H.equal(World.nearbyStep.id, 'test', 'another robbery cannot replace active target')
    zones[7].options.onExit()
    H.equal(text, 'First [E]', 'unrelated exit retains current prompt')
    zones[3].options.onExit()
    H.equal(World.nearbyStep, nil, 'exiting active step clears selected target')
    H.equal(text, nil, 'exiting active step clears prompt')
    local before = #calls
    interact()
    H.equal(#calls, before, 'no out-of-zone step request')
    zones[3].options.onEnter()
    interact()
    H.equal(World.active.step, 2, 'normal server transition retained')
    H.equal(World.nearbyStep.index, 2, 'next overlapping step selected without another enter')
    H.equal(text, 'Second [E]', 'next overlapping prompt immediately visible')
    zones[3].options.onExit()
    H.equal(text, 'Second [E]', 'old step exit cannot clear new step prompt')
    interact()
    H.equal(World.active, nil, 'normal completion clears active robbery')
    H.equal(World.busy, false, 'normal completion clears busy state')
    H.equal(text, 'start Test robbery [E]', 'completion restores existing start prompt')
    local oldCount = #zones
    World.apply({ definition, other })
    for index = 1, oldCount do
        H.equal(zones[index].removed, true, 'rebuild removes existing zones')
    end
    H.equal(World.nearbyStep, nil, 'rebuild clears nearby membership')
    H.equal(text, nil, 'rebuild clears old prompt')
    zones[9].options.onEnter(); interact()
    H.equal(text, nil, 'starting after rebuild cannot reuse old step membership')
    zones[10].options.onEnter()
    H.equal(text, 'First [E]', 'new step membership restores prompt')
    events['qbrobberies:client:ended']('other', 'Unrelated')
    H.equal(World.active.id, 'test', 'unrelated end event leaves active robbery')
    events['qbrobberies:client:ended']('test', 'Ended')
    H.equal(World.active, nil, 'matching end event retains existing retirement')
    H.equal(World.busy, false, 'matching end event clears busy state')
    interact()
    hooks.onClientResourceStop('foreign')
    H.equal(#abandoned, 0, 'foreign resource stop retains world')
    hooks.onClientResourceStop('qbrobberies')
    H.equal(abandoned[1].name, 'qbrobberies:server:abandon', 'own stop retains original abandonment event')
    H.equal(abandoned[1].id, 'test', 'own stop abandons active robbery')
    H.equal(next(World.live), nil, 'own stop clears all live membership')
    H.equal(World.nearbyStep, nil, 'own stop clears selected target')
end
H.finish('world')
