QbRobberies = QbRobberies or {}
local World = { definitions = {}, live = {}, active = nil, nearbyStart = nil, nearbyStep = nil, prompt = nil, busy = false }
QbRobberies.world = World

local function notify(message, kind)
    QB.notify.send({ title = 'Robberies', message = message, type = kind or 'info' })
end

local function vector(position)
    return vector3(position.x, position.y, position.z)
end

local function removeProps(live)
    for _, entity in ipairs(live.entities) do QB.entities.remove(entity) end
    live.entities = {}
end

local function spawnProps(id)
    local live, definition = World.live[id], World.definitions[id]
    if not live or not definition or live.loaded then return end
    live.loaded = true
    CreateThread(function()
        for _, prop in ipairs(definition.props) do
            if not live.loaded then return end
            -- qblib's entity module intentionally creates local, non-networked
            -- entities. These decorative robbery props are never networked,
            -- which keeps strict entity lockdown enabled server-wide.
            local entity = QB.entities.create(prop.model, vector4(prop.coords.x, prop.coords.y, prop.coords.z, prop.coords.w or 0), { preset = 'static' })
            if entity then live.entities[#live.entities + 1] = entity end
        end
    end)
end

local function refreshPrompt()
    local text, icon
    if World.active and World.nearbyStep and World.nearbyStep.id == World.active.id and World.nearbyStep.index == World.active.step then
        text, icon = ('%s [%s]'):format(World.nearbyStep.label, 'E'), 'CirclePlay'
    elseif not World.active and World.nearbyStart then
        text, icon = ('start %s [%s]'):format(World.nearbyStart.label, 'E'), 'Mask'
    end
    if not text then
        if World.prompt then QB.textui.hide(World.prompt); World.prompt = nil end
        return
    end
    if World.prompt then
        QB.textui.update(World.prompt, text, { key = 'E', icon = icon, position = 'right-center' })
    else
        World.prompt = QB.textui.show(text, { key = 'E', icon = icon, position = 'right-center' })
    end
end

local function build(definition)
    local id = definition.id
    local live = { zones = {}, entities = {}, loaded = false }
    World.live[id] = live
    live.zones[#live.zones + 1] = QB.zones.sphere({
        coords = vector(definition.start), radius = Config.Robberies.definitionDistance, debug = Config.Robberies.debug,
        onEnter = function() spawnProps(id) end,
        onExit = function() live.loaded = false; removeProps(live) end,
    })
    live.zones[#live.zones + 1] = QB.zones.sphere({
        coords = vector(definition.start), radius = definition.startRadius, debug = Config.Robberies.debug,
        onEnter = function() World.nearbyStart = { id = id, label = definition.label }; refreshPrompt() end,
        onExit = function() if World.nearbyStart and World.nearbyStart.id == id then World.nearbyStart = nil; refreshPrompt() end end,
    })
    for index, step in ipairs(definition.steps) do
        live.zones[#live.zones + 1] = QB.zones.sphere({
            coords = vector(step.coords), radius = step.radius, debug = Config.Robberies.debug,
            onEnter = function() World.nearbyStep = { id = id, index = index, label = step.label }; refreshPrompt() end,
            onExit = function()
                if World.nearbyStep and World.nearbyStep.id == id and World.nearbyStep.index == index then World.nearbyStep = nil; refreshPrompt() end
            end,
        })
    end
end

local function clear()
    if World.prompt then QB.textui.hide(World.prompt); World.prompt = nil end
    World.nearbyStart, World.nearbyStep = nil, nil
    for _, live in pairs(World.live) do
        for _, zone in ipairs(live.zones) do zone.remove() end
        removeProps(live)
    end
    World.live, World.definitions = {}, {}
end

function World.apply(definitions)
    clear()
    for _, definition in ipairs(definitions or {}) do
        World.definitions[definition.id] = definition
        build(definition)
    end
end

local function doStep()
    local target, active = World.nearbyStep, World.active
    if World.busy or not target or not active or target.id ~= active.id or target.index ~= active.step then return end
    World.busy = true
    CreateThread(function()
        local begun, err = QB.callback.trigger('qbrobberies:server:beginStep', active.id, active.step)
        if not begun then World.busy = false; return notify(err or 'This step is unavailable.', 'error') end
        local function cancel()
            QB.callback.trigger('qbrobberies:server:cancelStep', active.id, active.step, begun.token)
        end
        local proof
        if begun.game then
            local result = QB.minigames.play(begun.game.type, nil, begun.game.authorization)
            if not result or not result.success then
                World.busy = false
                cancel()
                if not (result and result.cancelled) then notify('Security challenge failed.', 'error') end
                return
            end
            proof = result.proof
        end
        local completed = QB.progressbar.start({
            label = begun.label, duration = begun.duration, canCancel = true,
            disable = { move = true, combat = true, car = true },
        })
        if not completed then World.busy = false; cancel(); return notify('Action cancelled.', 'error') end
        local result, finishErr = QB.callback.trigger('qbrobberies:server:finishStep', active.id, active.step, begun.token, proof)
        World.busy = false
        if not result then cancel(); return notify(finishErr or 'The robbery step could not be completed.', 'error') end
        if #result.rewards > 0 then notify('Collected: ' .. table.concat(result.rewards, ', '), 'success') end
        if result.complete then
            World.active = nil
            notify('Robbery complete. The area is cooling down.', 'success')
        else
            World.active.step = result.step
            notify('Move to the next robbery step.', 'info')
        end
        refreshPrompt()
    end)
end

local function start()
    if World.busy or not World.nearbyStart or World.active then return end
    World.busy = true
    CreateThread(function()
        local started, err = QB.callback.trigger('qbrobberies:server:start', World.nearbyStart.id)
        World.busy = false
        if not started then return notify(err or 'This robbery cannot be started.', 'error') end
        World.active = started
        notify('Robbery started. Find the first step.', 'warning')
        refreshPrompt()
    end)
end

QB.keybind.add({
    name = 'qbrobberies_interact', description = 'Interact with a robbery', defaultKey = 'E', defaultMapper = 'keyboard',
    onPressed = function()
        if World.active then doStep() else start() end
    end,
})

RegisterNetEvent('qbrobberies:client:sync', World.apply)
RegisterNetEvent('qbrobberies:client:ended', function(id, reason)
    if World.active and World.active.id == id then World.active = nil; World.busy = false; refreshPrompt(); notify(reason or 'Robbery ended.', 'warning') end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if World.active then TriggerServerEvent('qbrobberies:server:abandon', World.active.id) end
    clear()
end)
