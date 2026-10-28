QbRobberies = QbRobberies or {}
local State = { definitions = {}, sessions = {}, bySource = {}, cooldowns = {}, ready = false }
QbRobberies.state = State

local S = QbRobberies.schema

local copy = QB.util.deepClone

function State.snapshot()
    local out = {}
    for _, definition in pairs(State.definitions) do out[#out + 1] = copy(definition) end
    table.sort(out, function(a, b) return a.label:lower() < b.label:lower() end)
    return out
end

function State.broadcast(target)
    TriggerClientEvent('qbrobberies:client:sync', target or -1, State.snapshot())
end

function State.isAdmin(source)
    local ok, allowed = pcall(function() return exports.kora_core:hasPermission(source, Config.Robberies.adminPermission) end)
    return ok and allowed == true
end

function State.persist(raw)
    local definition, err = S.normalise(raw)
    if not definition then return nil, err end
    local _, writeErr = QB.sql.execute([[INSERT INTO `qbrobberies` (`id`,`label`,`definition`) VALUES (?,?,?)
        ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `definition` = VALUES(`definition`)]], {
        definition.id, definition.label, json.encode(definition),
    })
    if writeErr then return nil, 'Could not save the robbery.' end
    State.definitions[definition.id] = definition
    State.broadcast()
    return definition
end

function State.remove(id)
    if not State.definitions[id] then return false, 'Unknown robbery.' end
    if State.sessions[id] then return false, 'That robbery is currently active.' end
    local _, err = QB.sql.execute('DELETE FROM `qbrobberies` WHERE `id` = ?', { id })
    if err then return false, 'Could not delete the robbery.' end
    State.definitions[id] = nil
    State.cooldowns[id] = nil
    State.broadcast()
    return true
end

function State.load()
    local rows, err = QB.sql.query('SELECT `definition` FROM `qbrobberies`')
    if not rows then return false, err end
    for _, row in ipairs(rows) do
        local decoded = type(row.definition) == 'string' and json.decode(row.definition) or nil
        local definition, normaliseErr = S.normalise(decoded)
        if definition then
            State.definitions[definition.id] = definition
        else
            print(('^3[qbrobberies]^7 skipped malformed definition: %s'):format(tostring(normaliseErr)))
        end
    end
    return true
end

function State.at(source, point, distance)
    local ped = GetPlayerPed(source)
    if not ped or ped <= 0 then return false end
    local coords = GetEntityCoords(ped)
    return #(coords - vector3(point.x, point.y, point.z)) <= distance
end

function State.policeCount()
    local ok, officers = pcall(function() return exports.kora_core:getPlayersByJobType(Config.Robberies.policeJobType, true) end)
    return ok and type(officers) == 'table' and #officers or 0
end

function State.setDoor(session, doorId, locked)
    local ok, previous = pcall(function() return exports.kora_doorlock:getDoorState(doorId) end)
    if not ok or type(previous) ~= 'boolean' then return false, ('Unknown qbdoorlock id "%s".'):format(doorId) end
    if session.doorStates[doorId] == nil then session.doorStates[doorId] = previous end
    local changed = exports.kora_doorlock:setDoorState(doorId, locked)
    return changed == true
end

function State.restoreDoors(session)
    for doorId, locked in pairs(session.doorStates) do
        pcall(function() exports.kora_doorlock:setDoorState(doorId, locked) end)
    end
end

function State.stop(session, reason)
    if not session or State.sessions[session.robberyId] ~= session then return end
    State.restoreDoors(session)
    State.sessions[session.robberyId] = nil
    State.bySource[session.source] = nil
    TriggerClientEvent('qbrobberies:client:ended', session.source, session.robberyId, reason)
end

function State.raiseAlert(definition)
    local payload = {
        title = 'Robbery in progress', message = definition.label,
        priority = 'high', code = '10-90', icon = 'Siren',
        coords = definition.start, jobTypes = { Config.Robberies.policeJobType },
        duration = Config.Robberies.sessionTimeout,
    }
    if GetResourceState('kora_dispatch') == 'started' then
        local ok = pcall(function() return exports.kora_dispatch:createCall(payload) end)
        if ok then return end
    end
    local ok, officers = pcall(function() return exports.kora_core:getPlayersByJobType(Config.Robberies.policeJobType, true) end)
    if ok then
        for _, officer in ipairs(officers or {}) do
            QB.notify.send(officer, { title = 'Robbery in progress', message = definition.label, type = 'warning' })
        end
    end
end

function State.reward(source, step)
    local granted = {}
    for _, reward in ipairs(step.rewards) do
        if math.random() * 100 <= reward.chance then
            local amount = math.random(reward.min, reward.max)
            local ok
            if reward.kind == 'money' then
                ok = exports.kora_core:addMoney(source, reward.name, amount, 'robbery-reward')
            else
                ok = exports.kora_core:addItem(source, reward.name, amount, nil, nil, 'robbery-reward')
            end
            if ok then granted[#granted + 1] = ('%dx %s'):format(amount, reward.name) end
        end
    end
    return granted
end
