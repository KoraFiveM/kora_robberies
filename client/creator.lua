local APP_ID = 'qbrobberies:creator'

local data = { lists = {}, setups = {}, houses = {}, items = {} } -- what the server last sent
local currentView = 'lists'
local selectedList, selectedShell, selectedHouse = nil, nil, nil
local search = { query = nil, results = {}, total = 0 } -- item search on the list page
local editing = nil     -- while inside a shell: { key, spawned, origin, heading, preview }
local pendingTool = nil -- something to do with the menu closed: enter, leave or place props

-- ----------------------------------------------------------------------------
-- Small helpers
-- ----------------------------------------------------------------------------

local function notice(message, tone)
    return { tone = tone or 'success', message = message }
end

-- A form value as trimmed text ('' when it is missing or not text).
local function text(value)
    return type(value) == 'string' and value:match('^%s*(.-)%s*$') or ''
end

local function toast(message, kind)
    QB.notify.send({ title = 'House Creator', message = message, type = kind or 'error' })
end

-- Asks the admin to confirm. True when they did.
local function confirmed(title, message)
    local answer = QB.nui.openAlert({ title = title, message = message, confirmLabel = 'Delete' })
    return answer and answer.confirmed == true
end

local function find(list, id)
    for _, entry in ipairs(list) do
        if entry.id == id then return entry end
    end
end

local function itemLabel(name)
    local info = data.items[name]
    return info and info.label or name
end

local function itemImage(name)
    local info = data.items[name]
    return info and info.image or nil
end

local function coordsLabel(c)
    return ('%.1f, %.1f, %.1f'):format(c.x, c.y, c.z)
end

local function setupFor(key)
    return data.setups[key] or { props = {} }
end

local function listLabel(id)
    local list = id and find(data.lists, id)
    return list and list.label or 'No list'
end

-- Calls the server. Every change answers with the whole data, which replaces what we have.
local function call(name, ...)
    local result, err = QB.callback.trigger('qbrobberies:creator:' .. name, ...)
    if not result then return nil, err or 'Something went wrong.' end
    if result.lists then data = result end
    return result
end

local function copyProps(key)
    local props = {}
    for index, prop in ipairs(setupFor(key).props) do props[index] = prop end
    return props
end

-- ----------------------------------------------------------------------------
-- Inside a shell: spawn it, show the saved props, put the player back
-- ----------------------------------------------------------------------------

local function clearPreview()
    if not editing then return end
    for _, entity in ipairs(editing.preview) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
    editing.preview = {}
end

-- Shows every saved prop where it will be, so you can see what is already placed.
local function rebuildPreview()
    if not editing then return end
    clearPreview()
    for _, prop in ipairs(setupFor(editing.key).props) do
        local world, heading = FromShellOffset(editing.spawned, prop.offset, prop.heading)
        local ok, entity = pcall(QB.entities.create, prop.model, vector4(world.x, world.y, world.z, heading), { freeze = true, invincible = true })
        if ok and entity then
            SetEntityHeading(entity, heading)
            editing.preview[#editing.preview + 1] = entity
        end
    end
end

local function enterShell(key)
    local ped = PlayerPedId()
    local origin, heading = GetEntityCoords(ped), GetEntityHeading(ped)
    local lower = Config.Robberies.House.defaults.lowerZ or -20

    local spawned, err = SpawnShell(HouseShellByKey[key], vector3(origin.x, origin.y, origin.z + lower))
    if not spawned then return toast(err) end

    editing = { key = key, spawned = spawned, origin = origin, heading = heading, preview = {} }

    local entry = ShellEntryCoords(spawned)
    RequestCollisionAtCoord(entry.x, entry.y, entry.z)
    SetEntityCoords(ped, entry.x, entry.y, entry.z)
    Wait(500)
    rebuildPreview()
end

local function leaveShell()
    if not editing then return end
    clearPreview()
    RemoveShell(editing.spawned)

    local ped, origin = PlayerPedId(), editing.origin
    SetEntityCoords(ped, origin.x, origin.y, origin.z)
    SetEntityHeading(ped, editing.heading)
    editing = nil
end

-- Aims at the shell and saves one prop at a time until the admin cancels.
local function placeProps(tool)
    while editing do
        local aimed = QB.raycast.getCoords({ type = 'object', object = tool.model })
        local c = aimed and aimed.coords
        if not c then return end

        local offset, heading = ToShellOffset(editing.spawned, vector3(c.x, c.y, c.z), c.w or aimed.heading or 0.0)
        local props = copyProps(editing.key)
        props[#props + 1] = { model = tool.model, offset = offset, heading = heading, list = tool.list, label = tool.label }

        local result, err = call('shells:props', editing.key, props)
        if not result then return toast(err) end
        rebuildPreview()
    end
end

-- Aim at a spot and read it: { x, y, z, w } or nil when the admin cancels.
local function aim()
    local aimed = QB.raycast.getCoords({})
    local c = aimed and aimed.coords
    if not c then return nil end
    return { x = c.x, y = c.y, z = c.z, w = c.w or aimed.heading or 0.0 }
end

-- The exit goes where you aim, inside the shell.
local function placeExit()
    if not editing then return end
    local c = aim()
    if not c then return end

    local offset = ToShellOffset(editing.spawned, vector3(c.x, c.y, c.z), c.w)
    local result, err = call('shells:exit', editing.key, offset)
    if not result then return toast(err) end
    toast('Exit saved.', 'success')
end

-- Houses go where you aim, one after another, until you cancel. They all use the same shell.
local function placeHouses(key)
    local placed = 0
    while true do
        local c = aim()
        if not c then break end

        local result, err = call('houses:create', key, c)
        if not result then return toast(err) end
        placed = placed + 1
        toast(('House %d placed.'):format(placed), 'success')
    end
end

local function moveHouse(id)
    local c = aim()
    if not c then return end

    local result, err = call('houses:coords', id, c)
    if not result then return toast(err) end
    toast('Entrance moved.', 'success')
end

local function runPendingTool()
    local tool = pendingTool
    pendingTool = nil

    if tool.kind == 'enter' then enterShell(tool.key)
    elseif tool.kind == 'leave' then leaveShell()
    elseif tool.kind == 'props' then placeProps(tool)
    elseif tool.kind == 'exit' then placeExit()
    elseif tool.kind == 'houses' then placeHouses(tool.key)
    elseif tool.kind == 'moveHouse' then moveHouse(tool.id) end
end

-- ----------------------------------------------------------------------------
-- Views
-- ----------------------------------------------------------------------------

local function listsView()
    local items = {}
    for _, list in ipairs(data.lists) do
        items[#items + 1] = {
            id = list.id, label = list.label, icon = 'Package',
            description = ('%d items'):format(#list.items),
            action = 'list:select:' .. list.id,
        }
    end

    return {
        id = 'lists', label = 'Item lists', icon = 'Package',
        content = {
            title = 'Item lists',
            description = 'Make a list of items and amounts once, then give it to props in any shell. e.g. Kitchen.',
            blocks = {
                {
                    type = 'form', id = 'list-create', title = 'New list',
                    fields = { { id = 'name', label = 'Name', type = 'text', required = true } },
                    action = { id = 'list:create', label = 'Create list' },
                },
                { type = 'list', id = 'list-list', layout = 'cards', columns = 3, items = items, empty = 'No lists yet.' },
            },
        },
    }
end

local function foundCards(results)
    local cards = {}
    for _, result in ipairs(results) do
        cards[#cards + 1] = {
            id = result.name, label = result.label, description = result.name, image = result.image,
            metadata = result.added and { { label = 'Status', value = 'Already in the list' } } or nil,
            actions = result.added and {} or { { id = 'list:add:' .. result.name, label = 'Add', icon = 'Plus', variant = 'primary' } },
        }
    end
    return cards
end

local function listView()
    local list = find(data.lists, selectedList)
    if not list then
        return {
            id = 'list', label = 'List', icon = 'Package',
            content = { title = 'List', blocks = { { type = 'empty', title = 'Pick a list first.' } } },
        }
    end

    local items = {}
    for _, entry in ipairs(list.items) do
        items[#items + 1] = {
            id = entry.item, label = itemLabel(entry.item), description = entry.item, image = itemImage(entry.item),
            metadata = { { label = 'Amount', value = ('%dx'):format(entry.amount) } },
            actions = {
                { id = 'list:edit:' .. entry.item, label = 'Edit', icon = 'Pencil', variant = 'primary' },
                { id = 'list:remove:' .. entry.item, label = 'Remove', icon = 'Trash2', variant = 'destructive' },
            },
        }
    end

    local found = foundCards(search.results)
    local blocks = {
        { type = 'list', id = 'list-items', layout = 'cards', columns = 3, title = ('Items (%d)'):format(#items), items = items, empty = 'Nothing in this list yet. Search below.' },
        {
            type = 'form', id = 'list-search', title = 'Add items',
            fields = { { id = 'query', label = 'Search all items', type = 'text', default = search.query or '',
                description = 'Part of an item name or label.' } },
            action = { id = 'list:search', label = 'Search' },
        },
    }
    if search.query then
        local more = search.total > #found and (' of ' .. search.total) or ''
        blocks[#blocks + 1] = {
            type = 'list', id = 'list-results', layout = 'cards', columns = 3,
            title = ('Results for "%s" (%d%s)'):format(search.query, #found, more),
            items = found, empty = 'No items match that search.',
        }
    end
    blocks[#blocks + 1] = {
        type = 'actions', title = 'Danger zone',
        actions = { { id = 'list:delete', label = 'Delete list', variant = 'destructive' } },
    }

    return {
        id = 'list', label = list.label, icon = 'Package',
        content = { title = list.label, description = 'The items and amounts a prop gives. Used by every prop that has this list.', blocks = blocks },
    }
end

local function shellsView()
    local items = {}
    for _, shell in ipairs(HouseShells) do
        local setup = data.setups[shell.key]
        items[#items + 1] = {
            id = shell.key, label = shell.label, icon = 'Door',
            description = setup and ('%d props · exit %s'):format(#setup.props, setup.exit and 'set' or 'not set') or 'Not set up yet',
            action = 'shell:select:' .. shell.key,
        }
    end

    return {
        id = 'shells', label = 'Shells', icon = 'Door',
        content = {
            title = 'Shells',
            description = 'Set a shell up once: its exit and its props. Every house that uses it gets the same setup.',
            blocks = { { type = 'list', id = 'shell-list', layout = 'cards', columns = 3, items = items, empty = 'No shells in the config.' } },
        },
    }
end

local function propCards(props)
    local cards = {}
    for index, prop in ipairs(props) do
        cards[#cards + 1] = {
            id = tostring(index),
            label = prop.label or prop.model,
            icon = 'MapPin',
            description = ('%s · %s'):format(prop.model, coordsLabel(prop.offset)),
            metadata = { { label = 'Gives', value = listLabel(prop.list) } },
            actions = {
                { id = 'prop:list:' .. index, label = 'Change list', icon = 'Pencil', variant = 'primary' },
                { id = 'prop:remove:' .. index, label = 'Delete', icon = 'Trash2', variant = 'destructive' },
            },
        }
    end
    return cards
end

local function listOptions()
    local options = { { value = 'none', label = 'No list' } }
    for _, list in ipairs(data.lists) do options[#options + 1] = { value = list.id, label = list.label } end
    return options
end

local function shellView()
    local def = HouseShellByKey[selectedShell]
    if not def then
        return {
            id = 'shell', label = 'Shell', icon = 'Door',
            content = { title = 'Shell', blocks = { { type = 'empty', title = 'Pick a shell first.' } } },
        }
    end

    local setup = setupFor(def.key)
    local inside = editing and editing.key == def.key
    local blocks = {}

    if inside then
        blocks[#blocks + 1] = {
            type = 'actions',
            actions = {
                { id = 'shell:exit', label = setup.exit and 'Aim and move the exit' or 'Aim and set the exit', icon = 'Door', variant = 'primary' },
                { id = 'shell:leave', label = 'Leave the shell', icon = 'X' },
            },
        }
        blocks[#blocks + 1] = {
            type = 'form', id = 'prop-place', title = 'Place props',
            fields = {
                { id = 'model', label = 'Prop model', type = 'text', required = true },
                { id = 'list', label = 'Item list it gives', type = 'select', options = listOptions(), default = 'none' },
                { id = 'label', label = 'Target label', type = 'text', description = 'Optional. e.g. Search the fridge.' },
            },
            action = { id = 'prop:place', label = 'Aim and place props' },
        }
    elseif editing then
        blocks[#blocks + 1] = { type = 'empty', title = 'You are inside another shell. Leave it first.' }
    else
        blocks[#blocks + 1] = {
            type = 'actions',
            actions = { { id = 'shell:enter', label = 'Enter the shell to edit', icon = 'Door', variant = 'primary' } },
        }
    end

    local props = propCards(setup.props)
    blocks[#blocks + 1] = { type = 'list', id = 'shell-props', layout = 'cards', columns = 3, title = ('Props (%d)'):format(#props), items = props, empty = 'No props yet. Enter the shell to place some.' }
    if data.setups[def.key] then
        blocks[#blocks + 1] = {
            type = 'actions', title = 'Danger zone',
            actions = { { id = 'shell:clear', label = 'Clear this shell\'s setup', variant = 'destructive' } },
        }
    end

    return {
        id = 'shell', label = def.label, icon = 'Door',
        content = {
            title = def.label,
            description = ('Exit %s. Enter the shell, aim where the exit should be, then place your props.'):format(setup.exit and 'is set' or 'is not set yet'),
            blocks = blocks,
        },
    }
end

local function housesView()
    local shellOptions = {}
    for _, shell in ipairs(HouseShells) do
        shellOptions[#shellOptions + 1] = { value = shell.key, label = data.setups[shell.key] and shell.label or (shell.label .. ' (not set up)') }
    end

    local items = {}
    for _, house in ipairs(data.houses) do
        items[#items + 1] = {
            id = house.id, label = house.label, icon = 'Home',
            description = ('%s · %s'):format(HouseShellByKey[house.shell] and HouseShellByKey[house.shell].label or house.shell, coordsLabel(house.coords)),
            action = 'house:select:' .. house.id,
        }
    end

    return {
        id = 'houses', label = 'Houses', icon = 'Home',
        content = {
            title = 'Houses',
            description = 'Pick a shell, then aim at each door. Keep placing to make a bunch of houses; cancel when you are done.',
            blocks = {
                {
                    type = 'form', id = 'house-create', title = 'New houses',
                    fields = {
                        { id = 'shell', label = 'Shell', type = 'select', options = shellOptions, default = shellOptions[1] and shellOptions[1].value },
                    },
                    action = { id = 'house:create', label = 'Aim and place houses' },
                },
                { type = 'list', id = 'house-list', layout = 'cards', columns = 3, items = items, empty = 'No houses yet.' },
            },
        },
    }
end

local function houseView()
    local house = find(data.houses, selectedHouse)
    if not house then
        return {
            id = 'house', label = 'House', icon = 'Home',
            content = { title = 'House', blocks = { { type = 'empty', title = 'Pick a house first.' } } },
        }
    end

    local hours = house.hours or { from = 0, to = 23 }
    local def = HouseShellByKey[house.shell]

    return {
        id = 'house', label = house.label, icon = 'Home',
        content = {
            title = house.label,
            description = ('Shell: %s%s. Entrance: %s.'):format(def and def.label or house.shell, data.setups[house.shell] and '' or ' (not set up yet)', coordsLabel(house.coords)),
            blocks = {
                {
                    type = 'form', id = 'house-data', title = 'Settings',
                    fields = {
                        { id = 'label', label = 'Name', type = 'text', required = true, default = house.label },
                        { id = 'minPolice', label = 'Minimum police', type = 'number', min = 0, max = 100, default = house.minPolice },
                        { id = 'cooldown', label = 'Cooldown (minutes)', type = 'number', min = 0, max = 1440, default = house.cooldown },
                        { id = 'security', label = 'Security system', type = 'select', default = house.security and 'enabled' or 'disabled',
                            options = { { value = 'enabled', label = 'Enabled' }, { value = 'disabled', label = 'Disabled' } } },
                        { id = 'timeLimit', label = 'Robbery times', type = 'select', default = house.hours and 'limited' or 'any',
                            options = { { value = 'any', label = 'Any time' }, { value = 'limited', label = 'Only between the hours below' } } },
                        { id = 'timeFrom', label = 'From hour (0-23)', type = 'number', min = 0, max = 23, default = hours.from },
                        { id = 'timeTo', label = 'To hour (0-23)', type = 'number', min = 0, max = 23, default = hours.to },
                    },
                    action = { id = 'house:save', label = 'Save' },
                },
                { type = 'actions', actions = { { id = 'house:coords', label = 'Aim and move the entrance', icon = 'MapPin', variant = 'primary' } } },
                { type = 'actions', title = 'Danger zone', actions = { { id = 'house:delete', label = 'Delete house', variant = 'destructive' } } },
            },
        },
    }
end

local function buildNavigation()
    local navigation = { listsView() }
    if selectedList and find(data.lists, selectedList) then navigation[#navigation + 1] = listView() end
    navigation[#navigation + 1] = shellsView()
    if selectedShell then navigation[#navigation + 1] = shellView() end
    navigation[#navigation + 1] = housesView()
    if selectedHouse and find(data.houses, selectedHouse) then navigation[#navigation + 1] = houseView() end
    return navigation
end

local function refresh(message)
    local navigation = buildNavigation()
    QB.nui.updateApp(APP_ID, { navigation = navigation })
    return { update = { navigation = navigation }, notice = message }
end

local function fail(message)
    return refresh(notice(message, 'destructive'))
end

-- ----------------------------------------------------------------------------
-- Actions
-- ----------------------------------------------------------------------------

local function askAmount(label, title, current)
    local result = QB.nui.openInputDialog({
        { id = 'amount', label = 'Amount', type = 'number', min = 1, max = Limits.itemAmount, default = current or 1, required = true },
    }, title, label)
    if not result or result.cancelled then return nil end

    local amount = tonumber(result.values and result.values.amount)
    return amount and math.floor(amount) or nil
end

-- Item list actions
local function copyItems(list)
    local items = {}
    for index, entry in ipairs(list.items) do items[index] = { item = entry.item, amount = entry.amount } end
    return items
end

local function saveItems(list, items, message)
    local result, err = call('lists:items', list.id, items)
    if not result then return fail(err) end

    -- keep the search marks right: an item added or removed changes its "already in the list" note
    local inList = {}
    for _, entry in ipairs(items) do inList[entry.item] = true end
    for _, found in ipairs(search.results) do found.added = inList[found.name] == true end
    return refresh(notice(message))
end

local function listAction(actionId, values)
    if actionId == 'list:create' then
        local result, err = call('lists:create', text(values.name))
        if not result then return fail(err) end
        selectedList, currentView = result.id, 'list'
        search = { query = nil, results = {}, total = 0 }
        return refresh(notice('List created. Add some items.'))
    end

    local selectId = actionId:match('^list:select:(.+)$')
    if selectId then
        if not find(data.lists, selectId) then return fail('Unknown list.') end
        selectedList, currentView = selectId, 'list'
        search = { query = nil, results = {}, total = 0 }
        return refresh()
    end

    local list = find(data.lists, selectedList)
    if not list then return fail('Pick a list first.') end

    if actionId == 'list:search' then
        local query = text(values.query)
        if query == '' then
            search = { query = nil, results = {}, total = 0 }
            return refresh()
        end
        local result, err = call('lists:search', query, list.id)
        if not result then return fail(err or 'The search failed.') end
        search = { query = query, results = result.results or {}, total = result.total or #(result.results or {}) }
        return refresh()
    end

    local addName = actionId:match('^list:add:(.+)$')
    if addName then
        local found
        for _, result in ipairs(search.results) do
            if result.name == addName then found = result break end
        end
        if not found then return fail('Search for that item again first.') end

        local amount = askAmount(found.label, 'Add to list')
        if not amount then return refresh() end

        data.items[addName] = { label = found.label, image = found.image }
        local items = copyItems(list)
        items[#items + 1] = { item = addName, amount = amount }
        return saveItems(list, items, ('%dx %s added.'):format(amount, found.label))
    end

    local editName = actionId:match('^list:edit:(.+)$')
    if editName then
        local items = copyItems(list)
        for _, entry in ipairs(items) do
            if entry.item == editName then
                local amount = askAmount(itemLabel(editName), 'Edit item', entry.amount)
                if not amount then return refresh() end
                entry.amount = amount
                return saveItems(list, items, ('%s is now %dx.'):format(itemLabel(editName), amount))
            end
        end
        return refresh()
    end

    local removeName = actionId:match('^list:remove:(.+)$')
    if removeName then
        local items = {}
        for _, entry in ipairs(copyItems(list)) do
            if entry.item ~= removeName then items[#items + 1] = entry end
        end
        return saveItems(list, items, ('%s removed.'):format(itemLabel(removeName)))
    end

    if actionId == 'list:delete' then
        if not confirmed('Delete list?', ('This removes %s. Props that used it will give nothing.'):format(list.label)) then return refresh() end
        local result, err = call('lists:delete', list.id)
        if not result then return fail(err) end
        selectedList, currentView = nil, 'lists'
        return refresh(notice('List deleted.'))
    end

    return refresh()
end

-- Shell actions
local function setProps(props, message)
    local result, err = call('shells:props', selectedShell, props)
    if not result then return fail(err) end
    rebuildPreview()
    return refresh(notice(message))
end

local function shellAction(actionId, values)
    local selectKey = actionId:match('^shell:select:(.+)$')
    if selectKey then
        if not HouseShellByKey[selectKey] then return fail('Unknown shell.') end
        selectedShell, currentView = selectKey, 'shell'
        return refresh()
    end

    if not (selectedShell and HouseShellByKey[selectedShell]) then return fail('Pick a shell first.') end

    if actionId == 'shell:enter' then
        if editing then return fail('You are already inside a shell.') end
        pendingTool, currentView = { kind = 'enter', key = selectedShell }, 'shell'
        return { close = true }
    end

    if actionId == 'shell:leave' then
        pendingTool, currentView = { kind = 'leave' }, 'shell'
        return { close = true }
    end

    if actionId == 'shell:exit' then
        if not (editing and editing.key == selectedShell) then return fail('Enter the shell first.') end
        pendingTool, currentView = { kind = 'exit' }, 'shell'
        return { close = true }
    end

    if actionId == 'shell:clear' then
        if editing and editing.key == selectedShell then return fail('Leave the shell first.') end
        if not confirmed('Clear setup?', 'This removes the exit and every prop. Houses using this shell will have nothing to rob.') then return refresh() end
        local result, err = call('shells:clear', selectedShell)
        if not result then return fail(err) end
        return refresh(notice('Setup cleared.'))
    end

    if actionId == 'prop:place' then
        if not (editing and editing.key == selectedShell) then return fail('Enter the shell first.') end
        local model = text(values.model)
        if model == '' or not IsModelInCdimage(joaat(model)) then return fail('Unknown prop model.') end
        local listId = text(values.list)
        pendingTool = {
            kind = 'props', model = model,
            list = listId ~= '' and listId ~= 'none' and listId or nil,
            label = text(values.label) ~= '' and text(values.label) or nil,
        }
        currentView = 'shell'
        return { close = true }
    end

    local index = tonumber(actionId:match('^prop:remove:(%d+)$'))
    if index then
        local props = {}
        for position, prop in ipairs(copyProps(selectedShell)) do
            if position ~= index then props[#props + 1] = prop end
        end
        return setProps(props, 'Prop deleted.')
    end

    index = tonumber(actionId:match('^prop:list:(%d+)$'))
    if index then
        local props = copyProps(selectedShell)
        local prop = props[index]
        if not prop then return refresh() end

        local result = QB.nui.openInputDialog({
            { id = 'list', label = 'Item list it gives', type = 'select', options = listOptions(), default = prop.list or 'none' },
        }, 'Change list', prop.label or prop.model)
        if not result or result.cancelled then return refresh() end

        local chosen = result.values and result.values.list
        prop.list = chosen ~= 'none' and chosen or nil
        return setProps(props, 'List changed.')
    end

    return refresh()
end

-- House actions
local function houseAction(actionId, values)
    if actionId == 'house:create' then
        local key = text(values.shell)
        if not HouseShellByKey[key] then return fail('Pick a shell.') end
        if editing then return fail('Leave the shell first: houses go in the real world.') end
        pendingTool, currentView, selectedHouse = { kind = 'houses', key = key }, 'houses', nil
        return { close = true }
    end

    local selectId = actionId:match('^house:select:(.+)$')
    if selectId then
        if not find(data.houses, selectId) then return fail('Unknown house.') end
        selectedHouse, currentView = selectId, 'house'
        return refresh()
    end

    if not (selectedHouse and find(data.houses, selectedHouse)) then return fail('Pick a house first.') end

    if actionId == 'house:save' then
        local result, err = call('houses:details', selectedHouse, {
            label = text(values.label),
            minPolice = tonumber(values.minPolice),
            cooldown = tonumber(values.cooldown),
            security = values.security == 'enabled',
            timeLimit = values.timeLimit == 'limited',
            timeFrom = tonumber(values.timeFrom),
            timeTo = tonumber(values.timeTo),
        })
        if not result then return fail(err) end
        return refresh(notice('Saved.'))
    end

    if actionId == 'house:coords' then
        if editing then return fail('Leave the shell first: the entrance goes in the real world.') end
        pendingTool, currentView = { kind = 'moveHouse', id = selectedHouse }, 'house'
        return { close = true }
    end

    if actionId == 'house:delete' then
        local house = find(data.houses, selectedHouse)
        if not confirmed('Delete house?', ('This removes %s. The shell setup stays.'):format(house.label)) then return refresh() end
        local result, err = call('houses:delete', selectedHouse)
        if not result then return fail(err) end
        selectedHouse, currentView = nil, 'houses'
        return refresh(notice('House deleted.'))
    end

    return refresh()
end

local function onAction(actionId, context)
    local values = context and context.value or {}

    if actionId:match('^list:') then return listAction(actionId, values) end
    if actionId:match('^shell:') or actionId:match('^prop:') then return shellAction(actionId, values) end
    if actionId:match('^house:') then return houseAction(actionId, values) end
    return refresh()
end

QB.nui.registerApp({
    id = APP_ID,
    title = 'House Creator',
    icon = 'Home',
    layout = 'standard',
    width = 1100,
    height = 760,
    defaultView = 'lists',
    navigation = { { id = 'lists', label = 'Item lists', icon = 'Package', content = { title = 'Item lists', blocks = {} } } },
    onAction = onAction,
})

-- ----------------------------------------------------------------------------

local function open()
    local result, err = call('get')
    if not result then return toast(err or 'Admin permission required.') end

    while true do
        QB.nui.updateApp(APP_ID, { navigation = buildNavigation() })
        QB.nui.openApp(APP_ID, { viewId = currentView })
        if not pendingTool then break end
        runPendingTool()
    end
end

RegisterNetEvent('qbrobberies:creator:open', function()
    if source ~= 65535 then return end
    CreateThread(open)
end)

-- Closing the menu while inside a shell leaves you in it: open the creator again to leave, or stop the resource.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    leaveShell()
end)
