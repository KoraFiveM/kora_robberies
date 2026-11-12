local defaults = Config.Robberies.Store.defaults
local State = {}

local function notify(src, message, kind)
    Kora.notify.send(src, { title = Kora.lang('robbery_title'), message = message, type = kind or 'error' })
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
    TriggerClientEvent('kora_robberies:client:store', -1, storeId, kind, index, name)
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
    if not spot then return nil, Kora.lang('unknown_spot') end
    if not isNear(src, spot.coords, 5.0) then return nil, Kora.lang('you_are_too_far_away') end
    if PoliceOnDuty() < store.minPolice then return nil, Kora.lang('police_needed') end
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

Kora.callback.register('kora_robberies:stores', function()
    if not DataLoaded then return false end

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

Kora.callback.register('kora_robberies:register:begin', function(src, storeId, index)
    if onCooldown(src, 'register') then return false, Kora.lang('slow_down') end
    startCooldown(src, 'register', 500)

    local store, spot = spotFor(src, storeId, 'registers', index)
    if not store then return false, spot end

    local register = spotState(storeId, 'registers', index)
    if register.robbed then return false, Kora.lang('this_register_is_empty') end
    if isBusy(register) then return false, Kora.lang('register_being_robbed') end

    for _, other in pairs(stateOf(storeId).registers) do
        if other.busyBy == src and isBusy(other) then return false, Kora.lang('finish_current_action') end
    end

    register.busyBy, register.started, register.duration = src, GetGameTimer(), spot.time or DefaultSearch.time
    broadcast(storeId, 'registers', index, 'busy')
    return { duration = register.duration, label = spot.progressLabel, anim = spot.anim, disable = spot.disable }
end)

Kora.callback.register('kora_robberies:register:finish', function(src, storeId, index)
    local store, spot = spotFor(src, storeId, 'registers', index)
    if not store then return false, spot end

    local register = spotState(storeId, 'registers', index)
    if not (register.busyBy == src and not register.robbed) then return false, Kora.lang('you_are_not_robbing_that') end
    if GetGameTimer() - register.started < register.duration - 1000 then
        Kora.print.warn(('[kora_robberies] player %s finished a register too fast'):format(src))
        releaseRegister(storeId, index)
        return false, Kora.lang('too_fast')
    end

    local amount = pay(src, defaults.registerCash)
    if not amount then
        releaseRegister(storeId, index)
        return false, Kora.lang('you_cannot_carry_that')
    end

    register.robbed, register.busyBy = true, nil
    broadcast(storeId, 'registers', index, 'robbed')
    later(storeId, function()
        register.robbed = false
        broadcast(storeId, 'registers', index, 'free')
    end)

    notify(src, Kora.lang('cash_taken', amount), 'success')
    if math.random(100) <= (spot.stickyChance or 0) then
        exports['qb-inventory']:AddItem(src, defaults.stickyNoteItem, 1, nil, { code = stickyCode(storeId) })
        notify(src, Kora.lang('sticky_note_found'), 'success')
    end
    return true
end)

RegisterNetEvent('kora_robberies:register:cancel', function(storeId, index)
    local src = source
    local store = validId(storeId) and Stores[storeId]
    if not (store and type(index) == 'number' and store.registers[index]) then return end
    if spotState(storeId, 'registers', index).busyBy == src then releaseRegister(storeId, index) end
end)

local function closedSafe(src, storeId, index)
    local store, spot = spotFor(src, storeId, 'safes', index)
    if not store then return nil, spot end
    local safe = spotState(storeId, 'safes', index)
    if safe.robbed then return nil, Kora.lang('this_safe_is_empty') end
    if safe.blowing then return nil, Kora.lang('the_safe_is_being_blown') end
    if safe.blown then return nil, Kora.lang('the_safe_is_already_open') end
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

Kora.callback.register('kora_robberies:safe:code', function(src, storeId, index, code)
    if onCooldown(src, 'safe') then return false, Kora.lang('slow_down') end
    startCooldown(src, 'safe', 1000)

    local safe, err = closedSafe(src, storeId, index)
    if not safe then return false, err end
    local state = stateOf(storeId)
    if not (state.code and tonumber(code) == state.code) then return false, Kora.lang('wrong_code') end
    local amount = pay(src, defaults.safeCash)
    if not amount then return false, Kora.lang('you_cannot_carry_that') end
    emptySafe(storeId, index, safe)
    notify(src, Kora.lang('cash_taken', amount), 'success')
    return true
end)

Kora.callback.register('kora_robberies:safe:blow', function(src, storeId, index)
    if onCooldown(src, 'safe') then return false, Kora.lang('slow_down') end
    startCooldown(src, 'safe', 1000)

    local safe, err = closedSafe(src, storeId, index)
    if not safe then return false, err end
    if not exports['qb-inventory']:RemoveItem(src, defaults.thermiteItem, 1) then return false, Kora.lang('you_need_thermite') end

    local time = math.random(defaults.blowTime.min, defaults.blowTime.max)
    safe.blowing = true
    broadcast(storeId, 'safes', index, 'blowing')

    local state = stateOf(storeId)
    SetTimeout(time, function()
        if State[storeId] ~= state then return end
        safe.blowing, safe.blown = false, true
        broadcast(storeId, 'safes', index, 'blown')
        later(storeId, function()
            if safe.blown then
                safe.blown = false
                broadcast(storeId, 'safes', index, 'free')
            end
        end)
    end)
    return time
end)

Kora.callback.register('kora_robberies:safe:loot', function(src, storeId, index)
    if onCooldown(src, 'safe') then return false, Kora.lang('slow_down') end
    startCooldown(src, 'safe', 1000)

    local store, spot = spotFor(src, storeId, 'safes', index)
    if not store then return false, spot end
    local safe = spotState(storeId, 'safes', index)
    if safe.robbed or not safe.blown then return false, Kora.lang('there_is_nothing_to_take') end

    local amount = pay(src, defaults.safeCash)
    if not amount then return false, Kora.lang('you_cannot_carry_that') end
    emptySafe(storeId, index, safe)
    notify(src, Kora.lang('cash_taken', amount), 'success')
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
