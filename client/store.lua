local defaults = Config.Robberies.Store.defaults

local zones = {}
local states = {}      -- store id -> { registers = { [i] = 'busy' | 'robbed' }, safes = { [i] = 'blowing' | 'blown' | 'robbed' } }
local working = false  -- this player is in the middle of something

local function notify(message, kind)
    QB.notify.send({ title = 'Robbery', message = message, type = kind or 'error' })
end

local function stateOf(storeId, kind, index)
    return states[storeId] and states[storeId][kind][index]
end

local function progress(label, duration, anim, disable)
    return QB.progressbar.start({
        label = label,
        duration = duration,
        useWhileDead = false,
        canCancel = true,
        disable = disable or { move = true, combat = true, vehicle = true },
        anim = type(anim) == 'table' and { dict = anim.dict, clip = anim.clip, flag = anim.flag, flags = anim.flag } or nil,
    })
end

local function busyWith(fn)
    if working then return end
    working = true
    local ok, err = pcall(fn)
    working = false
    if not ok then QB.print.warn(('[qbrobberies] %s'):format(tostring(err))) end
end

local function robRegister(storeId, index)
    local started, err = QB.callback.trigger('qbrobberies:register:begin', storeId, index)
    if not started then
        if err then notify(err) end
        return
    end

    local done = progress(started.label, started.duration, started.anim, started.disable)
    if done then
        -- the skill check; if qb-minigames is not running it is skipped
        local ok, passed = pcall(function() return exports['qb-minigames']:Skillbar() end)
        done = not ok or passed
    end
    if not done then
        TriggerServerEvent('qbrobberies:register:cancel', storeId, index)
        return
    end

    local _, finishErr = QB.callback.trigger('qbrobberies:register:finish', storeId, index)
    if finishErr then notify(finishErr) end
end

local function enterCode(storeId, index)
    local input = QB.nui.openInputDialog({
        { id = 'code', label = 'Code', type = 'number', required = true },
    }, 'Enter Safe Code')
    if not (input and input.values and tonumber(input.values.code)) then return end

    local _, err = QB.callback.trigger('qbrobberies:safe:code', storeId, index, tonumber(input.values.code))
    if err then notify(err) end
end

local function blowSafe(storeId, index, coords)
    local time, err = QB.callback.trigger('qbrobberies:safe:blow', storeId, index)
    if not time then
        if err then notify(err) end
        return
    end

    local object = QB.entities.create('hei_prop_heist_thermite', vector3(coords.x, coords.y, coords.z), { freeze = true, invincible = true })
    Wait(time)
    AddExplosion(coords.x, coords.y, coords.z, 2, 1.0, true, false, 1.0)
    if object then DeleteEntity(object) end
end

local function takeLoot(storeId, index)
    if not progress('Retrieving Loot...', 5000) then return end
    local _, err = QB.callback.trigger('qbrobberies:safe:loot', storeId, index)
    if err then notify(err) end
end

local function clearZones()
    for _, zone in ipairs(zones) do pcall(function() exports.kora_target:removeZone(zone) end) end
    zones = {}
end

local function addZone(coords, options)
    zones[#zones + 1] = exports.kora_target:addBoxZone({
        coords = vector3(coords.x, coords.y, coords.z),
        size = vector3(1.0, 1.0, 1.0),
        options = options,
    })
end

local function loadStores()
    clearZones()
    local list
    for _ = 1, 20 do
        list = QB.callback.trigger('qbrobberies:stores')
        if list then break end
        Wait(1500)
    end
    list = list or {}

    states = {}
    for _, store in ipairs(list) do
        local storeId = store.id
        states[storeId] = store.states

        for index, register in ipairs(store.registers) do
            addZone(register.coords, { {
                icon = 'fas fa-cash-register',
                label = register.label or 'Rob Register',
                onSelect = function() busyWith(function() robRegister(storeId, index) end) end,
                canInteract = function() return not working and not stateOf(storeId, 'registers', index) end,
            } })
        end

        for index, safe in ipairs(store.safes) do
            local coords = safe.coords
            addZone(coords, {
                {
                    icon = 'fas fa-lock',
                    label = 'Enter Code',
                    onSelect = function() busyWith(function() enterCode(storeId, index) end) end,
                    canInteract = function() return not working and not stateOf(storeId, 'safes', index) end,
                },
                {
                    icon = 'fas fa-hand-holding',
                    label = 'Blow Up Safe',
                    onSelect = function() busyWith(function() blowSafe(storeId, index, coords) end) end,
                    canInteract = function()
                        return not working and not stateOf(storeId, 'safes', index) and exports['qb-inventory']:HasItem(defaults.thermiteItem)
                    end,
                },
                {
                    icon = 'fas fa-hand-holding',
                    label = 'Retrieve Loot',
                    onSelect = function() busyWith(function() takeLoot(storeId, index) end) end,
                    canInteract = function() return not working and stateOf(storeId, 'safes', index) == 'blown' end,
                },
            })
        end
    end
end

CreateThread(function()
    Wait(2000)
    loadStores()
end)

-- A store was added, changed or deleted in the creator.
RegisterNetEvent('qbrobberies:client:reloadStores', function()
    if source ~= 65535 then return end
    loadStores()
end)

-- A register or safe changed state. 'free' means it is available again.
RegisterNetEvent('qbrobberies:client:store', function(storeId, kind, index, name)
    if source ~= 65535 or not states[storeId] then return end
    states[storeId][kind][index] = name ~= 'free' and name or nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearZones()
end)
