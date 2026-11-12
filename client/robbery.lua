local defaults = Config.Robberies.House.defaults

local doors = {}        -- house id -> target zone on its door
local inside = nil      -- while in a house: { id, house, spawned, objects, exitZone, states, searching }
local houseStates = {}  -- house id -> { state = 'open' | 'cooldown', remaining = ms, at = GetGameTimer() }; none = available

local function notify(message, kind)
    Kora.notify.send({ title = 'Robbery', message = message, type = kind or 'error' })
end

local function removeZone(id)
    if id then pcall(function() exports.kora_target:removeZone(id) end) end
end

local function cleanupInside()
    if not inside then return end
    removeZone(inside.exitZone)
    for _, zone in ipairs(inside.zones) do removeZone(zone) end
    for _, object in ipairs(inside.objects) do
        pcall(function() exports.kora_target:removeEntity(object) end)
        if DoesEntityExist(object) then DeleteEntity(object) end
    end
    RemoveShell(inside.spawned)
    inside = nil
end

local function leaveHouse()
    if not inside then return end
    Kora.callback.trigger('kora_robberies:leave', inside.id)
    Kora.visuals.fade(inside.house.coords)
    cleanupInside()
end

local function searchProp(index)
    if not inside or inside.searching then return end
    inside.searching = true

    local houseId = inside.id
    local started, err = Kora.callback.trigger('kora_robberies:prop:begin', houseId, index)
    if not started then
        if err then notify(err) end
        inside.searching = false
        return
    end

    local anim = type(started.anim) == 'table'
        and { dict = started.anim.dict, clip = started.anim.clip, flag = started.anim.flag, flags = started.anim.flag }
        or nil
    local done = Kora.progressbar.start({
        label = started.label or DefaultSearch.progressLabel,
        duration = started.duration,
        disable = started.disable or DefaultSearch.disable,
        anim = anim,
    })

    if done then
        local _, finishErr = Kora.callback.trigger('kora_robberies:prop:finish', houseId, index)
        if finishErr then notify(finishErr) end
    else
        TriggerServerEvent('kora_robberies:prop:cancel', houseId, index)
    end
    if inside then inside.searching = false end
end

local function searchOption(index, prop)
    return {
        icon = 'fa-solid fa-magnifying-glass',
        label = prop.label or 'Search',
        onSelect = function() searchProp(index) end,
        canInteract = function() return inside ~= nil and not inside.searching and inside.states[index] == nil end,
    }
end

local function buildProps(info)
    local spawned, targets = 0, 0
    for index, prop in ipairs(info.props) do
        local world, heading = FromShellOffset(inside.spawned, prop.offset, prop.heading)

        if not prop.model then
            if prop.loot then
                targets = targets + 1
                inside.zones[#inside.zones + 1] = exports.kora_target:addBoxZone({
                    coords = vector3(world.x, world.y, world.z),
                    size = vector3(1.5, 1.5, 2.0),
                    options = { searchOption(index, prop) },
                })
            end
        else
            local object = SpawnProp(prop.model, world, heading)
            if not object then
                Kora.print.warn(('[kora_robberies] prop %d (%s) could not be spawned'):format(index, prop.model))
            else
                spawned = spawned + 1
                inside.objects[#inside.objects + 1] = object

                if prop.loot then
                    targets = targets + 1
                    exports.kora_target:addEntity(object, { searchOption(index, prop) })
                end
            end
        end
    end

    if defaults.debug then
        Kora.print.debug(('[kora_robberies] %d props from the server, %d spawned, %d with a search target'):format(#info.props, spawned, targets))
    end
    if targets == 0 and #info.props > 0 then
        notify('None of the spots here have an item list, so there is nothing to search. Give them one in the creator.')
    end
end

local function enterHouse(id, door, info)
    local house = { coords = door.coords, shell = info.shell, lowerZ = info.lowerZ }
    local def = HouseShellByKey[house.shell]
    if not def then
        Kora.callback.trigger('kora_robberies:leave', id)
        return notify('This house uses a shell that is not in the config.')
    end

    local spawned, err = SpawnShell(def, HouseSpawnCoords(house))
    if not spawned then
        Kora.callback.trigger('kora_robberies:leave', id)
        return notify(err or 'The inside could not be loaded.')
    end

    inside = { id = id, house = house, spawned = spawned, objects = {}, zones = {}, states = info.states or {}, searching = false }

    local world = FromShellOffset(spawned, info.exit, 0.0)
    inside.exitZone = exports.kora_target:addBoxZone({
        coords = vector3(world.x, world.y, world.z),
        size = vector3(1.5, 1.5, 2.0),
        options = { { label = 'Leave', icon = 'fa-solid fa-door-open', onSelect = leaveHouse } },
    })

    buildProps(info)

    RequestCollisionAtCoord(world.x, world.y, world.z)
    SetEntityCoords(PlayerPedId(), world.x, world.y, world.z)
    Wait(300)
end

local function stateOf(id)
    local entry = houseStates[id]
    return entry and entry.state or 'available'
end

local function minutesLeft(id)
    local entry = houseStates[id]
    if not entry then return 0 end
    local left = entry.remaining - (GetGameTimer() - entry.at)
    return math.max(1, math.ceil(left / 60000))
end

local function enter(id, house)
    local info, err = Kora.callback.trigger('kora_robberies:breakin', id)
    if not info then return notify(err or 'You could not get in.') end
    enterHouse(id, house, info)
end

local function breakIn(id, house)
    if inside then return end

    local done = Kora.progressbar.start({
        label = 'Breaking in...',
        duration = defaults.breakTime,
        disable = { move = true, combat = true, car = true },
        anim = defaults.breakAnim,
    })
    if not done then return end
    enter(id, house)
end

local function doorOptions(id, house)
    local function when(state)
        return function() return inside == nil and stateOf(id) == state end
    end

    return {
        { label = 'Break in', icon = 'fa-solid fa-user-secret', canInteract = when('available'),
            onSelect = function() breakIn(id, house) end },
        { label = 'Enter', icon = 'fa-solid fa-door-open', canInteract = when('open'),
            onSelect = function() if not inside then enter(id, house) end end },
        { label = 'Recently robbed', icon = 'fa-solid fa-clock', canInteract = when('cooldown'),
            onSelect = function() notify(('Someone broke in here recently. Try again in %d minutes.'):format(minutesLeft(id))) end },
    }
end

local function clearDoors()
    for _, zone in pairs(doors) do removeZone(zone) end
    doors = {}
end

local function loadDoors()
    clearDoors()
    houseStates = {}

    local list
    for _ = 1, 20 do
        list = Kora.callback.trigger('kora_robberies:world')
        if list then break end
        Wait(1500)
    end
    list = list or {}

    if defaults.debug then Kora.print.debug(('[kora_robberies] %d house doors'):format(#list)) end
    for _, house in ipairs(list) do
        local c = house.coords
        if house.state then houseStates[house.id] = { state = house.state, remaining = house.remaining or 0, at = GetGameTimer() } end
        doors[house.id] = exports.kora_target:addBoxZone({
            coords = vector3(c.x, c.y, c.z),
            size = vector3(1.5, 1.5, 2.0),
            rotation = c.w or 0.0,
            options = doorOptions(house.id, house),
        })
    end
end

CreateThread(function()
    Wait(2000)
    loadDoors()
end)

RegisterNetEvent('kora_robberies:client:reload', function()
    if source ~= 65535 then return end
    loadDoors()
end)

RegisterNetEvent('kora_robberies:client:state', function(houseId, state, remaining)
    if source ~= 65535 then return end
    houseStates[houseId] = state and { state = state, remaining = remaining or 0, at = GetGameTimer() } or nil
end)

RegisterNetEvent('kora_robberies:client:closed', function(houseId)
    if source ~= 65535 or not inside or inside.id ~= houseId then return end
    notify('The robbery is over. You have been sent out.')
    leaveHouse()
end)

RegisterNetEvent('kora_robberies:client:prop', function(houseId, index, state)
    if source ~= 65535 or not inside or inside.id ~= houseId then return end
    inside.states[index] = state ~= 'free' and state or nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearDoors()
    cleanupInside()
end)
