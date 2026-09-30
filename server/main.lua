local State = QbRobberies.state
local S = QbRobberies.schema
local RESOURCE = GetCurrentResourceName()

local function mutation(source, id, transform)
    if not State.ready then return nil, 'Robberies are still loading.' end
    if not State.isAdmin(source) then return nil, 'You cannot edit robberies.' end
    local existing = State.definitions[id]
    if not existing then return nil, 'Unknown robbery.' end
    if State.sessions[id] then return nil, 'This robbery is active and cannot be edited.' end
    local draft = json.decode(json.encode(existing))
    local ok, err = transform(draft)
    if not ok then return nil, err end
    return State.persist(draft)
end

local function validDoor(doorId)
    local ok, locked = pcall(function() return exports.qbdoorlock:getDoorState(doorId) end)
    return ok and type(locked) == 'boolean'
end

local function isReady(definition)
    if not definition.startSet then return false, 'Place the robbery start zone first.' end
    if #definition.steps == 0 then return false, 'Add at least one robbery step first.' end
    for _, step in ipairs(definition.steps) do
        if #step.rewards > 0 then return true end
    end
    return false, 'Add a reward to at least one robbery step first.'
end

QB.callback.register('qbrobberies:server:hydrate', function(source)
    return { ready = State.ready, admin = State.isAdmin(source), robberies = State.snapshot() }
end, { rateLimit = { max = 6, window = 10000 } })

QB.callback.register('qbrobberies:server:create', function(source, payload)
    if not State.ready then return nil, 'Robberies are still loading.' end
    if not State.isAdmin(source) then return nil, 'You cannot create robberies.' end
    if type(payload) ~= 'table' then return nil, 'Invalid robbery.' end
    local id = S.slug(payload.id or payload.label)
    if not id or State.definitions[id] then return nil, 'That robbery id is unavailable.' end
    local count = 0; for _ in pairs(State.definitions) do count = count + 1 end
    if count >= Config.Robberies.maxDefinitions then return nil, 'The robbery limit has been reached.' end
    local position = GetEntityCoords(GetPlayerPed(source))
    return State.persist({
        id = id, label = payload.label, enabled = false, startSet = false, cooldown = payload.cooldown,
        minPolice = payload.minPolice, startRadius = payload.startRadius,
        start = { x = position.x, y = position.y, z = position.z }, steps = {}, props = {},
    })
end, { rateLimit = { max = 4, window = 30000 } })

QB.callback.register('qbrobberies:server:policy', function(source, id, payload)
    if type(payload) ~= 'table' then return nil, 'Invalid policy.' end
    return mutation(source, id, function(draft)
        draft.label = payload.label or draft.label
        draft.cooldown = payload.cooldown
        draft.minPolice = payload.minPolice
        if payload.enabled == true then
            local ready, err = isReady(draft)
            if not ready then return false, err end
        end
        draft.enabled = payload.enabled == true
        return true
    end)
end, { rateLimit = { max = 10, window = 30000 } })

QB.callback.register('qbrobberies:server:setStart', function(source, id, start, radius)
    return mutation(source, id, function(draft)
        if not S.coords(start) or not S.number(radius, 0.5, 15) then return false, 'Invalid start zone.' end
        draft.start, draft.startRadius, draft.startSet = start, radius, true
        return true
    end)
end, { rateLimit = { max = 8, window = 30000 } })

QB.callback.register('qbrobberies:server:addStep', function(source, id, payload)
    return mutation(source, id, function(draft)
        if #draft.steps >= Config.Robberies.maxSteps then return false, 'This robbery already has the maximum number of steps.' end
        local step, err = S.normaliseStep(payload)
        if not step then return false, err end
        draft.steps[#draft.steps + 1] = step
        return true
    end)
end, { rateLimit = { max = 12, window = 30000 } })

QB.callback.register('qbrobberies:server:removeStep', function(source, id, index)
    return mutation(source, id, function(draft)
        index = S.integer(index, 1, #draft.steps)
        if not index then return false, 'Unknown robbery step.' end
        table.remove(draft.steps, index)
        return true
    end)
end, { rateLimit = { max = 12, window = 30000 } })

QB.callback.register('qbrobberies:server:updateStep', function(source, id, index, payload)
    return mutation(source, id, function(draft)
        index = S.integer(index, 1, #draft.steps)
        if not index or type(payload) ~= 'table' then return false, 'Invalid robbery step.' end
        payload.coords = draft.steps[index].coords
        payload.rewards = draft.steps[index].rewards
        payload.unlockDoors = draft.steps[index].unlockDoors
        local step, err = S.normaliseStep(payload)
        if not step then return false, err end
        draft.steps[index] = step
        return true
    end)
end, { rateLimit = { max = 12, window = 30000 } })

QB.callback.register('qbrobberies:server:addReward', function(source, id, index, reward)
    return mutation(source, id, function(draft)
        index = S.integer(index, 1, #draft.steps)
        local normalised, err = S.normaliseReward(reward)
        if not index or not normalised then return false, err or 'Invalid reward.' end
        if #draft.steps[index].rewards >= 12 then return false, 'This step already has enough rewards.' end
        draft.steps[index].rewards[#draft.steps[index].rewards + 1] = normalised
        return true
    end)
end, { rateLimit = { max = 16, window = 30000 } })

QB.callback.register('qbrobberies:server:removeReward', function(source, id, index, rewardIndex)
    return mutation(source, id, function(draft)
        index = S.integer(index, 1, #draft.steps)
        if not index then return false, 'Unknown robbery step.' end
        rewardIndex = S.integer(rewardIndex, 1, #draft.steps[index].rewards)
        if not rewardIndex then return false, 'Unknown reward.' end
        table.remove(draft.steps[index].rewards, rewardIndex)
        return true
    end)
end, { rateLimit = { max = 16, window = 30000 } })

QB.callback.register('qbrobberies:server:addDoor', function(source, id, index, doorId)
    return mutation(source, id, function(draft)
        doorId = S.text(doorId, 96)
        if not doorId or not validDoor(doorId) then return false, 'That qbdoorlock id does not exist.' end
        local list
        if index == 'start' then list = draft.startDoors else
            index = S.integer(index, 1, #draft.steps)
            if not index then return false, 'Unknown robbery step.' end
            list = draft.steps[index].unlockDoors
        end
        for _, current in ipairs(list) do if current == doorId then return false, 'That door is already assigned.' end end
        list[#list + 1] = doorId
        return true
    end)
end, { rateLimit = { max = 12, window = 30000 } })

QB.callback.register('qbrobberies:server:removeDoor', function(source, id, index, doorId)
    return mutation(source, id, function(draft)
        doorId = S.text(doorId, 96)
        local list
        if index == 'start' then list = draft.startDoors else
            index = S.integer(index, 1, #draft.steps)
            if not index then return false, 'Unknown robbery step.' end
            list = draft.steps[index].unlockDoors
        end
        for position, current in ipairs(list) do
            if current == doorId then table.remove(list, position); return true end
        end
        return false, 'That door is not assigned here.'
    end)
end, { rateLimit = { max = 12, window = 30000 } })

QB.callback.register('qbrobberies:server:addProp', function(source, id, prop)
    return mutation(source, id, function(draft)
        if #draft.props >= Config.Robberies.maxProps then return false, 'This robbery already has the maximum number of props.' end
        local model, position = type(prop) == 'table' and S.text(prop.model, 96), type(prop) == 'table' and S.coords(prop.coords)
        if not model or not position then return false, 'Invalid prop.' end
        draft.props[#draft.props + 1] = { model = model, coords = position }
        return true
    end)
end, { rateLimit = { max = 10, window = 30000 } })

QB.callback.register('qbrobberies:server:removeProp', function(source, id, index)
    return mutation(source, id, function(draft)
        index = S.integer(index, 1, #draft.props)
        if not index then return false, 'Unknown prop.' end
        table.remove(draft.props, index)
        return true
    end)
end, { rateLimit = { max = 12, window = 30000 } })

QB.callback.register('qbrobberies:server:delete', function(source, id)
    if not State.isAdmin(source) then return false, 'You cannot delete robberies.' end
    return State.remove(id)
end, { rateLimit = { max = 4, window = 30000 } })

QB.callback.register('qbrobberies:server:start', function(source, id)
    if not State.ready then return nil, 'Robberies are still loading.' end
    local definition = State.definitions[id]
    if not definition or not definition.enabled then return nil, 'This robbery is unavailable.' end
    if State.sessions[id] then return nil, 'Someone is already running this robbery.' end
    if State.bySource[source] then return nil, 'Finish or abandon your current robbery first.' end
    if #definition.steps == 0 then return nil, 'This robbery has no steps yet.' end
    if not State.at(source, definition.start, definition.startRadius + 1.0) then return nil, 'Move closer to the robbery start.' end
    local cooldown = State.cooldowns[id] or 0
    if cooldown > GetGameTimer() then return nil, ('Available again in %d seconds.'):format(math.ceil((cooldown - GetGameTimer()) / 1000)) end
    local police = State.policeCount()
    if police < definition.minPolice then return nil, ('At least %d police must be on duty.'):format(definition.minPolice) end
    local session = { robberyId = id, source = source, step = 1, doorStates = {}, expiresAt = GetGameTimer() + Config.Robberies.sessionTimeout }
    State.sessions[id], State.bySource[source] = session, session
    for _, doorId in ipairs(definition.startDoors) do
        local unlocked, doorErr = State.setDoor(session, doorId, false)
        if not unlocked then
            State.stop(session, 'Robbery setup failed.')
            return nil, doorErr or 'A configured robbery door is unavailable.'
        end
    end
    State.raiseAlert(definition)
    SetTimeout(Config.Robberies.sessionTimeout, function() State.stop(session, 'The robbery timed out.') end)
    return { id = id, step = 1, label = definition.label }
end, { rateLimit = { max = 6, window = 10000 } })

QB.callback.register('qbrobberies:server:beginStep', function(source, id, index)
    local session, definition = State.sessions[id], State.definitions[id]
    index = S.integer(index, 1, definition and #definition.steps or 0)
    if not session or session.source ~= source or not index or session.step ~= index then return nil, 'That robbery step is no longer active.' end
    if session.pending or session.expiresAt <= GetGameTimer() then return nil, 'That step cannot be started now.' end
    local step = definition.steps[index]
    if not State.at(source, step.coords, step.radius + 1.0) then return nil, 'Move closer to this step.' end
    local token = ('%d:%d:%d'):format(source, GetGameTimer(), math.random(100000, 999999))
    local authorization
    if step.game then authorization = QB.minigames.authorizeProof(source, step.game.type, step.game.opts) end
    session.pending = { index = index, token = token, startedAt = GetGameTimer(), authorization = authorization }
    return { token = token, duration = step.duration, game = step.game and { type = step.game.type, authorization = authorization } or nil, label = step.label }
end, { rateLimit = { max = 12, window = 10000 } })

QB.callback.register('qbrobberies:server:finishStep', function(source, id, index, token, proof)
    local session, definition = State.sessions[id], State.definitions[id]
    index = S.integer(index, 1, definition and #definition.steps or 0)
    if not session or session.source ~= source or not index then return nil, 'That robbery step is no longer active.' end
    local pending = session.pending
    if not pending or pending.index ~= index or pending.token ~= token then return nil, 'This step was not started.' end
    local step = definition.steps[index]
    if GetGameTimer() - pending.startedAt < step.duration then return nil, 'Finish the action before collecting the reward.' end
    if not State.at(source, step.coords, step.radius + 1.0) then return nil, 'You moved too far away.' end
    if step.game and not QB.minigames.consumeProof(source, proof, step.game.type, pending.authorization) then return nil, 'The security challenge was not completed.' end
    session.pending = nil
    local previousCooldown = State.cooldowns[id]
    local rewardCooldown = GetGameTimer() + definition.cooldown * 1000
    -- Hold the cooldown while reward exports yield; release it only if nothing was paid.
    if #step.rewards > 0 then State.cooldowns[id] = rewardCooldown end
    local rewards = State.reward(source, step)
    if #rewards == 0 and State.cooldowns[id] == rewardCooldown then
        State.cooldowns[id] = previousCooldown
    end
    for _, doorId in ipairs(step.unlockDoors) do State.setDoor(session, doorId, false) end
    session.step = index + 1
    if session.step > #definition.steps then
        State.cooldowns[id] = GetGameTimer() + definition.cooldown * 1000
        State.stop(session, 'Robbery complete.')
        return { complete = true, rewards = rewards }
    end
    return { complete = false, step = session.step, rewards = rewards }
end, { rateLimit = { max = 12, window = 10000 } })

-- Cancellation is deliberately separate from abandonment: a player who backs
-- out of a minigame/progress bar may retry the same step, but cannot retain a
-- pending authorization forever and turn it into a free retry later.
QB.callback.register('qbrobberies:server:cancelStep', function(source, id, index, token)
    local session, definition = State.sessions[id], State.definitions[id]
    index = S.integer(index, 1, definition and #definition.steps or 0)
    if not session or session.source ~= source or not index then return false end
    local pending = session.pending
    if pending and pending.index == index and pending.token == token then session.pending = nil; return true end
    return false
end, { rateLimit = { max = 12, window = 10000 } })

RegisterNetEvent('qbrobberies:server:abandon', function(id)
    local session = State.sessions[id]
    if session and session.source == source then State.stop(session, 'Robbery abandoned.') end
end)

AddEventHandler('playerDropped', function()
    local session = State.bySource[source]
    if session then State.stop(session, 'Robber disconnected.') end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    -- qbdoorlock state is external server state, so it must be restored even
    -- when this resource is restarted while a robbery is in progress.
    local sessions = {}
    for _, session in pairs(State.sessions) do sessions[#sessions + 1] = session end
    for _, session in ipairs(sessions) do State.stop(session, 'Robbery service restarted.') end
end)

CreateThread(function()
    if not QB.sql.ready(60000) then return print('^1[qbrobberies]^7 qbsql was not ready; resource disabled.') end
    local _, err = QB.sql.migrateFiles(RESOURCE, {
        { version = 1, name = 'robberies', file = 'sql/001_robberies.sql' },
    })
    if err then return print(('^1[qbrobberies]^7 migration failed: %s'):format(err)) end
    local loaded, loadErr = State.load()
    if not loaded then return print(('^1[qbrobberies]^7 could not load robberies: %s'):format(tostring(loadErr))) end
    State.ready = true
    print(('^2[qbrobberies]^7 %d robbery definition(s) live.'):format(#State.snapshot()))
end)
