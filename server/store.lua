local defaults = Config.Robberies.Store.defaults
local State = {}

local function notify(src, message, kind)
    QB.notify.send(src, { title = 'Robbery', message = message, type = kind or 'error' })
end

local function stateOf(storeId)
    State[storeId] = State[storeId] or { registers = {}, safes = {} }
    return State[storeId]
end

local function spotState(storeId, kind, index)
    local state = stateOf(storeId)
    state[kind][index] = state[kind][index] or {}
    return state[kind][index]
end

function ResetStoreState(storeId)
    State[storeId] = nil
end

local function broadcast(storeId, kind, index, name)
    TriggerClientEvent('qbrobberies:client:store', -1, storeId, kind, index, name)
end

local function later(storeId, fn)
    local state = stateOf(storeId)
    SetTimeout(defaults.resetTime, function()
        if State[storeId] == state then fn() end
    end)
end

local function isBusy(register)
    return register.busyBy ~= nil and (GetGameTimer() - register.started) < (register.duration + 10000)
end

local function registerName(register)
    if register.robbed then return 'robbed' end
    if isBusy(register) then return 'busy' end
end

local function safeName(safe)
    if safe.robbed then return 'robbed' end
    if safe.blowing then return 'blowing' end
    if safe.blown then return 'blown' end
end

local function releaseRegister(storeId, index)
    local register = spotState(storeId, 'registers', index)
    if register.busyBy and not register.robbed then
        register.busyBy = nil
        broadcast(storeId, 'registers', index, 'free')
    end
end

local function spotFor(src, storeId, kind, index)
    local store = validId(storeId) and Stores[storeId]
    local spot = store and type(index) == 'number' and store[kind][index]
    if not spot then return nil, 'Unknown spot.' end
    if not isNear(src, spot.coords, 5.0) then return nil, 'You are too far away.' end
    if PoliceOnDuty() < store.minPolice then return nil, 'Not enough police in the city.' end
    return store, spot
end

local function pay(src, range)
    local amount = math.random(range.min, range.max)
    return exports['qb-inventory']:AddItem(src, defaults.cashItem, amount) and amount or nil
end

local function stickyCode(storeId)
    local state = stateOf(storeId)
    if not state.code then
        local code = math.random(1000, 999999999)
        state.code = code
        later(storeId, function() if state.code == code then state.code = nil end end)
    end
    return state.code
end

QB.callback.register('qbrobberies:stores', function()
    if not DataLoaded then return false end -- not ready yet: the client asks again

    local list = {}
    for id, store in pairs(Stores) do
        local registers, states = {}, { registers = {}, safes = {} }
        for index, register in ipairs(store.registers) do
            registers[index] = {
                coords = register.coords, label = register.label,
            }
            states.registers[index] = registerName(spotState(id, 'registers', index))
        end

        local safes = {}
        for index, safe in ipairs(store.safes) do
            safes[index] = { coords = safe.coords }
            states.safes[index] = safeName(spotState(id, 'safes', index))
        end
        list[#list + 1] = { id = id, registers = registers, safes = safes, states = states }
    end
    return list
end)

QB.callback.register('qbrobberies:register:begin', function(src, storeId, index)
    if onCooldown(src, 'register') then return false, 'Slow down.' end
    startCooldown(src, 'register', 500)

    local store, spot = spotFor(src, storeId, 'registers', index)
    if not store then return false, spot end

    local register = spotState(storeId, 'registers', index)
    if register.robbed then return false, 'This register is empty.' end
    if isBusy(register) then return false, 'Someone is already robbing this.' end

    for _, other in pairs(stateOf(storeId).registers) do
        if other.busyBy == src and isBusy(other) then return false, 'Finish what you are doing first.' end
    end

    register.busyBy, register.started, register.duration = src, GetGameTimer(), spot.time or DefaultSearch.time
    broadcast(storeId, 'registers', index, 'busy')
    return { duration = register.duration, label = spot.progressLabel, anim = spot.anim, disable = spot.disable }
end)

QB.callback.register('qbrobberies:register:finish', function(src, storeId, index)
    local store, spot = spotFor(src, storeId, 'registers', index)
    if not store then return false, spot end

    local register = spotState(storeId, 'registers', index)
    if not (register.busyBy == src and not register.robbed) then return false, 'You are not robbing that.' end
    if GetGameTimer() - register.started < register.duration - 1000 then
        QB.print.warn(('[qbrobberies] player %s finished a register too fast'):format(src))
        releaseRegister(storeId, index)
        return false, 'Too fast.'
    end

    local amount = pay(src, defaults.registerCash)
    if not amount then
        releaseRegister(storeId, index)
        return false, 'You cannot carry that.'
    end

    register.robbed, register.busyBy = true, nil
    broadcast(storeId, 'registers', index, 'robbed')
    later(storeId, function()
        register.robbed = false
        broadcast(storeId, 'registers', index, 'free')
    end)

    notify(src, ('You took $%d.'):format(amount), 'success')
    if math.random(100) <= (spot.stickyChance or 0) then
        exports['qb-inventory']:AddItem(src, defaults.stickyNoteItem, 1, nil, { code = stickyCode(storeId) })
        notify(src, 'There was a sticky note with a number on it.', 'success')
    end
    return true
end)

RegisterNetEvent('qbrobberies:register:cancel', function(storeId, index)
    local src = source
    local store = validId(storeId) and Stores[storeId]
    if not (store and type(index) == 'number' and store.registers[index]) then return end
    if spotState(storeId, 'registers', index).busyBy == src then releaseRegister(storeId, index) end
end)

local function closedSafe(src, storeId, index)
    local store, spot = spotFor(src, storeId, 'safes', index)
    if not store then return nil, spot end
    local safe = spotState(storeId, 'safes', index)
    if safe.robbed then return nil, 'This safe is empty.' end
    if safe.blowing then return nil, 'The safe is being blown.' end
    if safe.blown then return nil, 'The safe is already open.' end
    return safe
end

local function emptySafe(storeId, index, safe)
    safe.robbed, safe.blown, safe.blowing = true, false, false
    stateOf(storeId).code = nil
    broadcast(storeId, 'safes', index, 'robbed')
    later(storeId, function()
        safe.robbed = false
        broadcast(storeId, 'safes', index, 'free')
    end)
end

QB.callback.register('qbrobberies:safe:code', function(src, storeId, index, code)
    if onCooldown(src, 'safe') then return false, 'Slow down.' end
    startCooldown(src, 'safe', 1000)

    local safe, err = closedSafe(src, storeId, index)
    if not safe then return false, err end
    local state = stateOf(storeId)
    if not (state.code and tonumber(code) == state.code) then return false, 'Wrong code.' end
    local amount = pay(src, defaults.safeCash)
    if not amount then return false, 'You cannot carry that.' end
    emptySafe(storeId, index, safe)
    notify(src, ('You took $%d.'):format(amount), 'success')
    return true
end)

QB.callback.register('qbrobberies:safe:blow', function(src, storeId, index)
    if onCooldown(src, 'safe') then return false, 'Slow down.' end
    startCooldown(src, 'safe', 1000)

    local safe, err = closedSafe(src, storeId, index)
    if not safe then return false, err end
    if not exports['qb-inventory']:RemoveItem(src, defaults.thermiteItem, 1) then return false, 'You need thermite.' end

    local time = math.random(defaults.blowTime.min, defaults.blowTime.max)
    safe.blowing = true
    broadcast(storeId, 'safes', index, 'blowing')

    local state = stateOf(storeId)
    SetTimeout(time, function()
        if State[storeId] ~= state then return end
        safe.blowing, safe.blown = false, true
        broadcast(storeId, 'safes', index, 'blown')
        later(storeId, function() -- nobody took it: it closes again
            if safe.blown then
                safe.blown = false
                broadcast(storeId, 'safes', index, 'free')
            end
        end)
    end)
    return time
end)

QB.callback.register('qbrobberies:safe:loot', function(src, storeId, index)
    if onCooldown(src, 'safe') then return false, 'Slow down.' end
    startCooldown(src, 'safe', 1000)

    local store, spot = spotFor(src, storeId, 'safes', index)
    if not store then return false, spot end
    local safe = spotState(storeId, 'safes', index)
    if safe.robbed or not safe.blown then return false, 'There is nothing to take.' end

    local amount = pay(src, defaults.safeCash)
    if not amount then return false, 'You cannot carry that.' end
    emptySafe(storeId, index, safe)
    notify(src, ('You took $%d.'):format(amount), 'success')
    return true
end)

AddEventHandler('playerDropped', function()
    local src = source
    for storeId, state in pairs(State) do
        for index, register in pairs(state.registers) do
            if register.busyBy == src then releaseRegister(storeId, index) end
        end
    end
end)
