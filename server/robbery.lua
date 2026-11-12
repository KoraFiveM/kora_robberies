local States = {}
local Sessions = {}
local defaults = Config.Robberies.House.defaults
local robberyTime = math.floor((defaults.robberyTime or (1000 * 60) * 15) / 1000) -- seconds

local function notify(src, message, kind)
    Kora.notify.send(src, { title = 'Robbery', message = message, type = kind or 'error' })
end

local function itemLabel(name)
    local info = itemEntry(allItems(), name)
    return info and info.label or name
end

local function broadcast(houseId, index, state)
    local session = Sessions[houseId]
    if not session then return end
    for src in pairs(session.players) do
        TriggerClientEvent('kora_robberies:client:prop', src, houseId, index, state)
    end
end

local function releaseProp(houseId, index)
    local session = Sessions[houseId]
    local prop = session and session.props[index]
    if prop and prop.busyBy and not prop.looted then
        prop.busyBy = nil
        broadcast(houseId, index, 'free')
    end
end

local function isBusy(prop)
    return prop and prop.busyBy ~= nil and (GetGameTimer() - prop.started) < (prop.duration + 10000)
end

local function leaveSession(src, houseId)
    local session = Sessions[houseId]
    if not (session and session.players[src]) then return end

    session.players[src] = nil
    for index, prop in pairs(session.props) do
        if prop.busyBy == src then releaseProp(houseId, index) end
    end
end

AddEventHandler('playerDropped', function()
    local src = source
    for houseId in pairs(Sessions) do leaveSession(src, houseId) end
end)

local function setState(houseId, state, seconds)
    States[houseId] = state and { state = state, endsAt = os.time() + seconds } or nil
    TriggerClientEvent('kora_robberies:client:state', -1, houseId, state, state and seconds * 1000 or nil)
end

local function remainingSeconds(houseId)
    local entry = States[houseId]
    return entry and math.max(0, entry.endsAt - os.time()) or 0
end

local function closeHouse(houseId)
    local session = Sessions[houseId]
    Sessions[houseId] = nil
    for src in pairs(session and session.players or {}) do
        TriggerClientEvent('kora_robberies:client:closed', src, houseId)
    end

    local house = Houses[houseId]
    local cooldown = (house and house.cooldown or 0) * 60
    setState(houseId, cooldown > 0 and 'cooldown' or nil, cooldown)
end

local function advance(houseId)
    local entry = States[houseId]
    if not entry then return end
    if entry.state == 'open' then closeHouse(houseId) else setState(houseId, nil) end
end

CreateThread(function()
    while true do
        Wait(1000)
        local now, due = os.time(), {}
        for houseId, entry in pairs(States) do
            if entry.endsAt <= now then due[#due + 1] = houseId end
        end
        for _, houseId in ipairs(due) do advance(houseId) end
    end
end)

local function inHours(hours)
    if not hours then return true end
    local hour = os.date('*t').hour
    if hours.from <= hours.to then return hour >= hours.from and hour <= hours.to end
    return hour >= hours.from or hour <= hours.to -- runs past midnight
end

local function requiredItems(house, setup)
    local needs = { { item = house.breakItem or setup.breakItem or defaults.breakItem, amount = 1 } }
    if house.security then
        needs[#needs + 1] = { item = house.securityItem or defaults.securityItem, amount = 1 }
    end
    return needs
end

local function checkBreakIn(src, house, setup)
    if not inHours(house.hours) then return false, 'Nobody leaves this house empty right now. Come back at another time.' end
    if PoliceOnDuty() < house.minPolice then return false, 'Not enough police in the city.' end

    local missing = {}
    for _, need in ipairs(requiredItems(house, setup)) do
        if not exports['qb-inventory']:HasItem(src, need.item, need.amount) then
            missing[#missing + 1] = itemLabel(need.item)
        end
    end
    if #missing > 0 then return false, 'You need: ' .. table.concat(missing, ', ') .. '.' end
    return true
end

local function entryInfo(houseId, house, setup)
    local props, states = {}, {}
    for index, prop in ipairs(setup.props) do
        local list = prop.list and Lists[prop.list]
        props[index] = { model = prop.model, offset = prop.offset, heading = prop.heading, label = prop.label, loot = list ~= nil and #list.items > 0 }
    end
    for index, prop in pairs(Sessions[houseId].props) do
        if prop.looted then states[index] = 'looted' elseif isBusy(prop) then states[index] = 'busy' end
    end
    return { shell = house.shell, lowerZ = house.lowerZ, exit = setup.exit, props = props, states = states }
end

Kora.callback.register('kora_robberies:world', function()
    if not DataLoaded then return false end -- not ready yet: the client asks again

    local list = {}
    for id, house in pairs(Houses) do
        local entry = States[id]
        list[#list + 1] = {
            id = id, coords = house.coords,
            state = entry and entry.state, remaining = entry and remainingSeconds(id) * 1000,
        }
    end
    return list
end)

Kora.callback.register('kora_robberies:breakin', function(src, houseId)
    if onCooldown(src, 'breakin') then return false, 'Slow down.' end
    startCooldown(src, 'breakin', 2000)

    local house = validId(houseId) and Houses[houseId]
    if not house then return false, 'Unknown house.' end
    if not isNear(src, house.coords, 4.0) then return false, 'You are too far away.' end

    local setup = Setups[house.shell]
    if not (setup and setup.exit) then return false, 'Nothing to rob here.' end

    local state = States[houseId] and States[houseId].state
    if state == 'cooldown' then
        return false, ('Someone broke in here recently. Try again in %d minutes.'):format(math.ceil(remainingSeconds(houseId) / 60))
    end

    local session = Sessions[houseId]
    if session and session.players[src] then return false, 'You are already inside.' end

    if state ~= 'open' then
        local ok, message = checkBreakIn(src, house, setup)
        if not ok then return false, message end

        local needs = requiredItems(house, setup)
        if defaults.consumeBreakItem and not exports['qb-inventory']:RemoveItem(src, needs[1].item, 1) then
            return false, 'You need: ' .. itemLabel(needs[1].item) .. '.'
        end

        session = { players = {}, props = {} }
        Sessions[houseId] = session
        setState(houseId, 'open', robberyTime)

        if house.security then
            TriggerEvent('kora_robberies:houseAlert', { house = houseId, label = house.label, coords = house.coords })
        end
    end

    session = Sessions[houseId] or session
    if not session then session = { players = {}, props = {} } Sessions[houseId] = session end
    session.players[src] = true
    return entryInfo(houseId, house, setup)
end)

Kora.callback.register('kora_robberies:leave', function(src, houseId)
    if not validId(houseId) then return false end
    leaveSession(src, houseId)
    return true
end)

local function searchable(src, houseId, index)
    local session = validId(houseId) and Sessions[houseId]
    if not (session and session.players[src]) then return nil, 'You are not inside.' end

    local house = Houses[houseId]
    local setup = house and Setups[house.shell]
    local prop = setup and type(index) == 'number' and setup.props[index]
    local list = prop and prop.list and Lists[prop.list]
    if not (list and #list.items > 0) then return nil, 'There is nothing here.' end

    if not isNear(src, HouseSpawnCoords(house), 120.0) then return nil, 'You are too far away.' end
    return session, list, prop
end

Kora.callback.register('kora_robberies:prop:begin', function(src, houseId, index)
    if onCooldown(src, 'search') then return false, 'Slow down.' end
    startCooldown(src, 'search', 500)

    local session, list, prop = searchable(src, houseId, index)
    if not session then return false, list end

    local state = session.props[index] or {}
    if state.looted then return false, 'Already searched.' end
    if isBusy(state) then return false, 'Someone is already searching this.' end

    for _, other in pairs(session.props) do
        if other.busyBy == src and isBusy(other) then return false, 'Finish what you are doing first.' end
    end

    state.busyBy, state.started, state.duration = src, GetGameTimer(), prop.time or DefaultSearch.time
    session.props[index] = state
    broadcast(houseId, index, 'busy')
    return { duration = state.duration, label = prop.progressLabel, anim = prop.anim, disable = prop.disable }
end)

Kora.callback.register('kora_robberies:prop:finish', function(src, houseId, index)
    local session, list = searchable(src, houseId, index)
    if not session then return false, list end

    local state = session.props[index]
    if not (state and state.busyBy == src and not state.looted) then return false, 'You are not searching that.' end
    if GetGameTimer() - state.started < state.duration - 1000 then
        Kora.print.warn(('[kora_robberies] player %s finished a search too fast'):format(src))
        releaseProp(houseId, index)
        return false, 'Too fast.'
    end

    local entry = list.items[math.random(#list.items)]
    if not exports['qb-inventory']:AddItem(src, entry.item, entry.amount) then
        releaseProp(houseId, index)
        return false, 'You cannot carry that.'
    end

    state.looted, state.busyBy = true, nil
    broadcast(houseId, index, 'looted')

    notify(src, ('You found %dx %s.'):format(entry.amount, itemLabel(entry.item)), 'success')
    return true
end)

RegisterNetEvent('kora_robberies:prop:cancel', function(houseId, index)
    local src = source
    local session = validId(houseId) and Sessions[houseId]
    local state = session and type(index) == 'number' and session.props[index]
    if state and state.busyBy == src then releaseProp(houseId, index) end
end)

-- FFT seam: used only by fft_hooks_server.lua (inert unless fft_kora_hooks is true).
RobberyFFT = { States = States, Sessions = Sessions, setState = setState }
