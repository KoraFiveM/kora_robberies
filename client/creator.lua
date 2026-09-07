-- The AppShell is the creator's permanent interface. It only gathers admin
-- intent; every mutation travels to the server and is validated/persisted
-- there. World capture is deliberately delegated to qblib's zone and placement
-- creators, so coordinates never need to be typed or pasted.
QbRobberies = QbRobberies or {}
local Creator = { admin = false, snapshot = {} }
QbRobberies.creator = Creator

local APP_ID = 'qbrobberies:creator'

local function notify(message, kind)
    QB.notify.send({ title = 'Robbery creator', message = message, type = kind or 'info' })
end

function Creator.setAdmin(value) Creator.admin = value == true end

local function arraySnapshot()
    local out = {}
    for _, definition in pairs(Creator.snapshot) do out[#out + 1] = definition end
    table.sort(out, function(a, b) return a.label:lower() < b.label:lower() end)
    return out
end

local function setSnapshot(definitions)
    Creator.snapshot = {}
    for _, definition in ipairs(definitions or {}) do Creator.snapshot[definition.id] = definition end
end

local function recordView(id) return 'robbery:' .. id end
local function idFromView(viewId) return type(viewId) == 'string' and viewId:match('^robbery:([%w_]+)$') or nil end
local function stepFromItem(itemId)
    if type(itemId) ~= 'string' then return nil end
    local id, index = itemId:match('^step:([%w_]+):(%d+)$')
    return id, tonumber(index)
end

local function zoneFields(result)
    if not result or result.type ~= 'sphere' then return nil end
    return { x = result.opts.coords.x, y = result.opts.coords.y, z = result.opts.coords.z }, result.opts.radius
end

local definition

local function refreshed(saved)
    if type(saved) == 'table' and saved.id then Creator.snapshot[saved.id] = saved end
    return { update = definition(arraySnapshot()), notice = { tone = 'success', message = 'Robbery saved.' } }
end

local function startZoneFlow(id)
    local existing = Creator.snapshot[id]
    local seed = existing and { coords = vector3(existing.start.x, existing.start.y, existing.start.z), radius = existing.startRadius } or nil
    local captured = QB.zones.startCreator('sphere', seed)
    local coords, radius = zoneFields(captured)
    if not coords then return end
    local saved, err = QB.callback.trigger('qbrobberies:server:setStart', id, coords, radius)
    if saved then Creator.snapshot[id] = saved; notify('Start location saved.', 'success') else notify(err or 'Could not save start location.', 'error') end
    Creator.open(id)
end

local function stepFlow(id)
    local values = QB.nui.openInputDialog({
        { id = 'kind', label = 'Step type', type = 'select', required = true, options = {
            { value = 'hack', label = 'Hack (security minigame)' }, { value = 'search', label = 'Search (timed)' }, { value = 'drill', label = 'Drill (skillbar)' },
        } },
        { id = 'label', label = 'Player prompt', type = 'text', required = true, default = 'Search the container' },
        { id = 'duration', label = 'Action time (milliseconds)', type = 'number', required = true, default = 7000, min = 1000, max = 120000 },
        { id = 'radius', label = 'Interaction radius', type = 'number', required = true, default = 1.2, min = 0.4, max = 8 },
    }, 'New robbery step', 'Choose the action, then place its sphere zone in the world.')
    if not values then return Creator.open(id) end
    local captured = QB.zones.startCreator('sphere')
    local coords, _ = zoneFields(captured)
    if not coords then return Creator.open(id) end
    local saved, err = QB.callback.trigger('qbrobberies:server:addStep', id, {
        kind = values.kind, label = values.label, duration = values.duration, radius = values.radius, coords = coords,
    })
    if saved then Creator.snapshot[id] = saved; notify('Robbery step added.', 'success') else notify(err or 'Could not add step.', 'error') end
    Creator.open(id)
end

local function propFlow(id)
    local values = QB.nui.openInputDialog({ { id = 'model', label = 'GTA model name', type = 'text', required = true } }, 'Place a local robbery prop')
    if not values then return Creator.open(id) end
    if not IsModelValid(joaat(values.model)) then notify('That is not a valid GTA model.', 'error'); return Creator.open(id) end
    local placement = QB.placement.start(values.model)
    if not placement then return Creator.open(id) end
    local saved, err = QB.callback.trigger('qbrobberies:server:addProp', id, {
        model = values.model,
        coords = { x = placement.coords.x, y = placement.coords.y, z = placement.coords.z, w = placement.heading or 0 },
    })
    if saved then Creator.snapshot[id] = saved; notify('Local prop added.', 'success') else notify(err or 'Could not add prop.', 'error') end
    Creator.open(id)
end

definition = function(definitions)
    local navigation = {
        {
            id = 'overview', label = 'Robberies', icon = 'Mask', content = {
                title = 'Robbery creator', description = 'Build live, database-backed robberies without editing files or restarting the server.',
                actions = {
                    { id = 'creator:create', label = 'Create robbery', icon = 'Plus', variant = 'primary', fields = {
                        { id = 'id', label = 'Internal id', type = 'text', required = true, description = 'Lowercase text; spaces are converted to underscores.' },
                        { id = 'label', label = 'Display name', type = 'text', required = true },
                        { id = 'cooldown', label = 'Cooldown (seconds)', type = 'number', default = Config.Robberies.defaultCooldown, min = 0, max = 604800 },
                        { id = 'minPolice', label = 'Minimum police on duty', type = 'number', default = Config.Robberies.defaultMinPolice, min = 0, max = 64 },
                    } },
                    { id = 'creator:refresh', label = 'Refresh', icon = 'RefreshCw', variant = 'secondary' },
                },
                blocks = {
                    { type = 'stats', items = {
                        { label = 'Configured', value = #definitions, icon = 'MapPinned' },
                        { label = 'Enabled', value = (function() local n = 0; for _, d in ipairs(definitions) do if d.enabled then n = n + 1 end end; return n end)(), icon = 'CircleCheck', tone = 'success' },
                    } },
                    { type = 'list', title = 'Definitions', layout = 'cards', searchable = true, searchPlaceholder = 'Search robberies…', items = (function()
                        local rows = {}
                        for _, d in ipairs(definitions) do rows[#rows + 1] = {
                            id = d.id, label = d.label, icon = 'Landmark', tone = d.enabled and 'success' or 'warning',
                            description = ('%d steps · %d police · %ds cooldown'):format(#d.steps, d.minPolice, d.cooldown),
                            action = { id = 'creator:open', label = 'Edit', icon = 'Settings' },
                        } end
                        return rows
                    end)(), empty = { title = 'No robberies yet', description = 'Create one here, then place the start, steps, doors, props, and rewards in-game.', icon = 'MapPlus' } },
                },
            },
        },
    }
    for _, d in ipairs(definitions) do
        local steps, props = {}, {}
        for index, step in ipairs(d.steps) do
            steps[#steps + 1] = {
                id = ('step:%s:%d'):format(d.id, index), label = ('%d. %s'):format(index, step.label), icon = step.kind == 'hack' and 'Terminal' or step.kind == 'drill' and 'Drill' or 'Search',
                description = ('%s · %d ms · %d reward(s) · %d door(s)'):format(step.kind, step.duration, #step.rewards, #step.unlockDoors),
                actions = {
                    { id = 'creator:add-reward', label = 'Add reward', icon = 'Gift', fields = {
                        { id = 'kind', label = 'Reward type', type = 'select', required = true, options = { { value = 'money', label = 'Money' }, { value = 'item', label = 'Inventory item' } } },
                        { id = 'name', label = 'Account or item name', type = 'text', required = true, description = 'Money: cash or bank.' },
                        { id = 'min', label = 'Minimum amount', type = 'number', required = true, default = 1, min = 1, max = 1000000 },
                        { id = 'max', label = 'Maximum amount', type = 'number', required = true, default = 1, min = 1, max = 1000000 },
                        { id = 'chance', label = 'Chance (%)', type = 'number', required = true, default = 100, min = 0.01, max = 100 },
                    } },
                    { id = 'creator:step-door', label = 'Unlock door', icon = 'DoorOpen', fields = { { id = 'doorId', label = 'qbdoorlock id', type = 'text', required = true } } },
                    { id = 'creator:remove-reward', label = 'Remove reward', icon = 'BadgeMinus', fields = { { id = 'rewardIndex', label = 'Reward number', type = 'number', required = true, min = 1, max = 12 } } },
                    { id = 'creator:remove-step-door', label = 'Remove door', icon = 'DoorClosed', fields = { { id = 'doorId', label = 'qbdoorlock id', type = 'text', required = true } } },
                    { id = 'creator:remove-step', label = 'Remove', icon = 'Trash2', variant = 'destructive', confirm = 'Remove this step and all of its rewards?' },
                },
            }
        end
        for index, prop in ipairs(d.props) do props[#props + 1] = {
            id = ('prop:%s:%d'):format(d.id, index), label = prop.model, description = ('%.1f, %.1f, %.1f'):format(prop.coords.x, prop.coords.y, prop.coords.z), icon = 'Box',
            action = { id = 'creator:remove-prop', label = 'Remove', icon = 'Trash2', variant = 'destructive', confirm = 'Remove this local prop?' },
        } end
        navigation[#navigation + 1] = {
            id = recordView(d.id), label = d.label, icon = 'Landmark', content = {
                title = d.label, description = 'All changes go live immediately. Door states are restored when a session ends.',
                actions = {
                    { id = 'creator:policy', label = 'Edit policy', icon = 'SlidersHorizontal', fields = {
                        { id = 'label', label = 'Display name', type = 'text', required = true, default = d.label },
                        { id = 'cooldown', label = 'Cooldown (seconds)', type = 'number', required = true, default = d.cooldown, min = 0, max = 604800 },
                        { id = 'minPolice', label = 'Minimum police', type = 'number', required = true, default = d.minPolice, min = 0, max = 64 },
                        { id = 'enabled', label = 'Enabled', type = 'checkbox', default = d.enabled },
                    } },
                    { id = 'creator:set-start', label = 'Place start zone', icon = 'MapPin', variant = 'primary', closeBeforeAction = true },
                    { id = 'creator:add-step-flow', label = 'Place step', icon = 'Plus', closeBeforeAction = true },
                    { id = 'creator:add-prop-flow', label = 'Place local prop', icon = 'Box', closeBeforeAction = true },
                    { id = 'creator:start-door', label = 'Unlock start door', icon = 'DoorOpen', fields = { { id = 'doorId', label = 'qbdoorlock id', type = 'text', required = true } } },
                    { id = 'creator:remove-start-door', label = 'Remove start door', icon = 'DoorClosed', fields = { { id = 'doorId', label = 'qbdoorlock id', type = 'text', required = true } } },
                    { id = 'creator:delete', label = 'Delete robbery', icon = 'Trash2', variant = 'destructive', confirm = 'Delete this robbery permanently?' },
                },
                blocks = {
                    { type = 'stats', items = {
                        { label = 'Steps', value = #d.steps, icon = 'ListChecks' }, { label = 'Local props', value = #d.props, icon = 'Box' },
                        { label = 'Start doors', value = #d.startDoors, icon = 'DoorOpen' }, { label = 'Status', value = d.enabled and 'Enabled' or 'Disabled', icon = 'CircleCheck', tone = d.enabled and 'success' or 'warning' },
                    } },
                    { type = 'details', title = 'Start', items = { { label = 'Coordinates', value = ('%.2f, %.2f, %.2f'):format(d.start.x, d.start.y, d.start.z) }, { label = 'Radius', value = ('%.1f m'):format(d.startRadius) }, { label = 'Start doors', value = #d.startDoors > 0 and table.concat(d.startDoors, ', ') or 'None' } } },
                    { type = 'list', title = 'Robbery steps', layout = 'list', items = steps, empty = { title = 'No steps', description = 'Place one or more steps to make this robbery playable.', icon = 'ListPlus' } },
                    { type = 'list', title = 'Client-local decorative props', layout = 'list', items = props, empty = { title = 'No local props', description = 'Place optional scenery. qblib spawns it non-networked on each nearby client.', icon = 'Box' } },
                },
            },
        }
    end
    return {
        id = APP_ID, title = 'Robbery Creator', description = 'Live in-game robbery authoring', icon = 'Mask', accent = '#dc2626', defaultView = 'overview',
        footer = 'Zones, placement, local entities, minigames, and focus are provided by qblib.', navigation = navigation,
        onAction = function(actionId, context)
            local id = idFromView(context and context.viewId)
            if actionId == 'creator:refresh' then
                local data, err = QB.callback.trigger('qbrobberies:server:hydrate')
                if not data or not data.admin then error(err or 'Could not refresh robberies.') end
                setSnapshot(data.robberies)
                return { update = definition(arraySnapshot()), notice = { tone = 'success', message = 'Robberies refreshed.' } }
            end
            if actionId == 'creator:open' then return { navigate = { viewId = recordView(context.itemId) } } end
            if actionId == 'creator:create' then
                local saved, err = QB.callback.trigger('qbrobberies:server:create', context.value)
                if not saved then error(err or 'Could not create robbery.') end
                Creator.snapshot[saved.id] = saved
                return { update = definition(arraySnapshot()), navigate = { viewId = recordView(saved.id) }, notice = { tone = 'success', message = 'Robbery created. Place its start zone next.' } }
            end
            if not id then error('No robbery is selected.') end
            if actionId == 'creator:policy' then
                local saved, err = QB.callback.trigger('qbrobberies:server:policy', id, context.value)
                if not saved then error(err or 'Could not save policy.') end
                return refreshed(saved)
            end
            if actionId == 'creator:set-start' then CreateThread(function() startZoneFlow(id) end); return end
            if actionId == 'creator:add-step-flow' then CreateThread(function() stepFlow(id) end); return end
            if actionId == 'creator:add-prop-flow' then CreateThread(function() propFlow(id) end); return end
            if actionId == 'creator:start-door' then
                local saved, err = QB.callback.trigger('qbrobberies:server:addDoor', id, 'start', context.value.doorId)
                if not saved then error(err or 'Could not add door.') end
                return refreshed(saved)
            end
            if actionId == 'creator:remove-start-door' then
                local saved, err = QB.callback.trigger('qbrobberies:server:removeDoor', id, 'start', context.value.doorId)
                if not saved then error(err or 'Could not remove door.') end
                return refreshed(saved)
            end
            if actionId == 'creator:delete' then
                local ok, err = QB.callback.trigger('qbrobberies:server:delete', id)
                if not ok then error(err or 'Could not delete robbery.') end
                Creator.snapshot[id] = nil
                return { update = definition(arraySnapshot()), navigate = { viewId = 'overview', replace = true }, notice = { tone = 'success', message = 'Robbery deleted.' } }
            end
            local propId, propIndex
            if type(context.itemId) == 'string' then propId, propIndex = context.itemId:match('^prop:([%w_]+):(%d+)$') end
            if actionId == 'creator:remove-prop' then
                if propId ~= id then error('No robbery prop is selected.') end
                local saved, err = QB.callback.trigger('qbrobberies:server:removeProp', id, tonumber(propIndex))
                if not saved then error(err or 'Could not remove prop.') end
                return refreshed(saved)
            end
            local stepId, index = stepFromItem(context.itemId)
            if stepId ~= id or not index then error('No robbery step is selected.') end
            if actionId == 'creator:add-reward' then
                local saved, err = QB.callback.trigger('qbrobberies:server:addReward', id, index, context.value)
                if not saved then error(err or 'Could not add reward.') end
                return refreshed(saved)
            end
            if actionId == 'creator:remove-reward' then
                local saved, err = QB.callback.trigger('qbrobberies:server:removeReward', id, index, context.value.rewardIndex)
                if not saved then error(err or 'Could not remove reward.') end
                return refreshed(saved)
            end
            if actionId == 'creator:step-door' then
                local saved, err = QB.callback.trigger('qbrobberies:server:addDoor', id, index, context.value.doorId)
                if not saved then error(err or 'Could not add door.') end
                return refreshed(saved)
            end
            if actionId == 'creator:remove-step-door' then
                local saved, err = QB.callback.trigger('qbrobberies:server:removeDoor', id, index, context.value.doorId)
                if not saved then error(err or 'Could not remove door.') end
                return refreshed(saved)
            end
            if actionId == 'creator:remove-step' then
                local saved, err = QB.callback.trigger('qbrobberies:server:removeStep', id, index)
                if not saved then error(err or 'Could not remove step.') end
                return refreshed(saved)
            end
            error('Unknown robbery creator action.')
        end,
    }
end

function Creator.open(focusId)
    if not Creator.admin then return notify('You do not have permission to edit robberies.', 'error') end
    CreateThread(function()
        local data, err = QB.callback.trigger('qbrobberies:server:hydrate')
        if not data or not data.admin then return notify(err or 'Could not load the robbery creator.', 'error') end
        setSnapshot(data.robberies)
        QB.nui.registerApp(definition(arraySnapshot()))
        QB.nui.openApp(APP_ID, focusId and { viewId = recordView(focusId) } or nil)
    end)
end

RegisterCommand(Config.Robberies.command, function() Creator.open() end, false)
