local APP_ID = 'qbrobberies:creator'

local data = { lists = {}, setups = {}, houses = {}, stores = {}, items = {} } -- what the server last sent
local currentView = 'lists'
local selectedList, selectedShell, selectedHouse, selectedStore = nil, nil, nil, nil
local search = { query = nil, results = {}, total = 0 } -- item search on the list page
local editing = nil     -- while inside a shell: { key, spawned, origin, heading, preview }
local pendingTool = nil -- something to do with the menu closed: enter, leave or place props

local function notice(message, tone)
    return { tone = tone or 'success', message = message }
end

local function text(value)
    return type(value) == 'string' and value:match('^%s*(.-)%s*$') or ''
end

local function toast(message, kind)
    QB.notify.send({ title = 'House Creator', message = message, type = kind or 'error' })
end

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

local function propSearch(prop)
    local anim = DefaultSearch.anim
    if prop and prop.anim ~= nil then anim = prop.anim end -- false means no animation
    return {
        label = prop and prop.label or nil,
        progressLabel = prop and prop.progressLabel or DefaultSearch.progressLabel,
        time = prop and prop.time or DefaultSearch.time,
        anim = anim,
        disable = prop and prop.disable or DefaultSearch.disable,
    }
end

local function searchFields(search)
    local anim = search.anim or {}
    local fields = {
        { id = 'label', label = 'Target label', type = 'text', default = search.label or '', description = 'Optional. What the target says, e.g. Search the fridge.' },
        { id = 'progressLabel', label = 'Progress text', type = 'text', default = search.progressLabel, description = 'Shown on the progress bar while searching.' },
        { id = 'time', label = 'Search time (ms)', type = 'number', min = 500, max = 300000, required = true, default = search.time },
        { id = 'animDict', label = 'Animation dictionary', type = 'text', default = anim.dict or '',
            description = 'e.g. mp_arresting. Leave the dictionary and the clip empty for no animation.' },
        { id = 'animClip', label = 'Animation clip', type = 'text', default = anim.clip or '', description = 'The clip inside that dictionary, e.g. a_uncuff.' },
        { id = 'animFlag', label = 'Animation flag', type = 'number', min = 0, max = 65535, default = anim.flag or DefaultSearch.anim.flag,
            description = 'GTA animation flags. 49 keeps the upper body animating while allowing movement.' },
    }
    local blocked = {}
    for _, option in ipairs(ProgressDisableOptions) do
        if search.disable[option.value] == true then blocked[#blocked + 1] = option.value end
    end
    fields[#fields + 1] = { id = 'disable', label = 'Block while searching', type = 'multiselect', options = ProgressDisableOptions,
        default = blocked, description = 'Controls that are blocked while the progress bar runs.' }
    return fields
end

local function searchFromValues(values)
    local time = tonumber(values.time)
    if not time then return nil, 'Enter the search time in milliseconds.' end

    local dict, clip = text(values.animDict), text(values.animClip)
    local anim = false
    if dict ~= '' or clip ~= '' then
        if dict == '' or clip == '' then return nil, 'An animation needs both a dictionary and a clip.' end
        if not DoesAnimDictExist(dict) then return nil, 'Unknown animation dictionary.' end
        anim = { dict = dict, clip = clip, flag = math.floor(tonumber(values.animFlag) or DefaultSearch.anim.flag) }
    end

    local disable = {}
    for _, key in ipairs(type(values.disable) == 'table' and values.disable or {}) do disable[key] = true end
    local label, progressLabel = text(values.label), text(values.progressLabel)
    return {
        label = label ~= '' and label or nil,
        progressLabel = progressLabel ~= '' and progressLabel or DefaultSearch.progressLabel,
        time = math.floor(time), anim = anim, disable = disable,
    }
end

local function searchSummary(search)
    local blocked = {}
    for _, option in ipairs(ProgressDisableOptions) do
        if search.disable[option.value] then blocked[#blocked + 1] = option.label end
    end
    return {
        { label = 'Progress text', value = search.progressLabel },
        { label = 'Search time', value = ('%.1f s'):format(search.time / 1000) },
        { label = 'Animation', value = search.anim and ('%s / %s'):format(search.anim.dict, search.anim.clip) or 'None' },
        { label = 'Blocks', value = #blocked > 0 and table.concat(blocked, ', ') or 'Nothing' },
    }
end

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

local function clearPreview()
    if not editing then return end
    for _, entity in ipairs(editing.preview) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
    editing.preview = {}
end

local function rebuildPreview()
    if not editing then return end
    clearPreview()
    for _, prop in ipairs(setupFor(editing.key).props) do
        if prop.model then -- a box target has nothing to show
            local world, heading = FromShellOffset(editing.spawned, prop.offset, prop.heading)
            local entity = SpawnProp(prop.model, world, heading)
            if entity then editing.preview[#editing.preview + 1] = entity end
        end
    end
end

local function enterShell(key)
    local ped = PlayerPedId()
    local origin, heading = GetEntityCoords(ped), GetEntityHeading(ped)
    local lower = Config.Robberies.House.defaults.lowerZ or -20

    local spawned, err = SpawnShell(HouseShellByKey[key], vector3(origin.x, origin.y, origin.z + lower))
    if not spawned then
        QB.print.warn(('[qbrobberies] could not enter the %s shell: %s'):format(key, tostring(err)))
        return toast(err)
    end

    editing = { key = key, spawned = spawned, origin = origin, heading = heading, preview = {} }

    local entry = ShellEntryCoords(spawned)
    RequestCollisionAtCoord(entry.x, entry.y, entry.z)
    SetEntityCoords(ped, entry.x, entry.y, entry.z)
    Wait(500)
    rebuildPreview()
    toast(('You are inside the %s shell. Aim the exit and place props from the creator.'):format(HouseShellByKey[key].label), 'success')
end

local function notInsideReason(key)
    if not editing then return 'You are not inside a shell yet. Press Enter the shell to edit.' end
    if editing.key ~= key then
        return ('You are inside the %s shell. Leave it first, or open that shell\'s page.'):format(HouseShellByKey[editing.key].label)
    end
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

local function placeProps(tool)
    while editing do
        local aimed = QB.raycast.getCoords(tool.model and { type = 'object', object = tool.model } or {})
        local c = aimed and aimed.coords
        if not c then return end

        local offset, heading = ToShellOffset(editing.spawned, vector3(c.x, c.y, c.z), c.w or aimed.heading or 0.0)
        local props = copyProps(editing.key)
        props[#props + 1] = {
            model = tool.model, offset = offset, heading = heading, list = tool.list, label = tool.search.label,
            progressLabel = tool.search.progressLabel, time = tool.search.time, anim = tool.search.anim, disable = tool.search.disable,
        }

        local result, err = call('shells:props', editing.key, props)
        if not result then return toast(err) end
        rebuildPreview()
    end
end

local function aim()
    local aimed = QB.raycast.getCoords({})
    local c = aimed and aimed.coords
    if not c then return nil end
    return { x = c.x, y = c.y, z = c.z, w = c.w or aimed.heading or 0.0 }
end

local function placeExit()
    if not editing then return end
    local c = aim()
    if not c then return end

    local offset = ToShellOffset(editing.spawned, vector3(c.x, c.y, c.z), c.w)
    local result, err = call('shells:exit', editing.key, offset)
    if not result then return toast(err) end
    toast('Exit saved.', 'success')
end

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

local function copyList(list)
    local copy = {}
    for index, entry in ipairs(list) do copy[index] = entry end
    return copy
end

-- Aims and saves one register or safe at a time, until the admin cancels. tool.field is 'registers' or 'safes'.
local function placeStoreSpots(tool)
    while true do
        local c = aim()
        if not c then return end

        local store = find(data.stores, tool.id)
        if not store then return end

        local list = copyList(store[tool.field])
        list[#list + 1] = tool.build(c)

        local result, err = call('stores:' .. tool.field, tool.id, list)
        if not result then return toast(err) end
        toast(tool.field == 'registers' and 'Register placed.' or 'Safe placed.', 'success')
    end
end

local function runPendingTool()
    local tool = pendingTool
    pendingTool = nil

    if tool.kind == 'enter' then enterShell(tool.key)
    elseif tool.kind == 'leave' then leaveShell()
    elseif tool.kind == 'props' then placeProps(tool)
    elseif tool.kind == 'exit' then placeExit()
    elseif tool.kind == 'houses' then placeHouses(tool.key)
    elseif tool.kind == 'moveHouse' then moveHouse(tool.id)
    elseif tool.kind == 'stores' then placeStoreSpots(tool) end
end

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
        content = { title = list.label, description = 'A prop gives one of these items, picked at random, with the amount set here. Used by every prop that has this list.', blocks = blocks },
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
            label = prop.label or prop.model or 'Search spot',
            icon = prop.model and 'MapPin' or 'Square',
            description = ('%s · %s'):format(prop.model or 'Box target', coordsLabel(prop.offset)),
            metadata = (function()
                local metadata = { { label = 'Gives', value = listLabel(prop.list) } }
                for _, entry in ipairs(searchSummary(propSearch(prop))) do metadata[#metadata + 1] = entry end
                return metadata
            end)(),
            actions = {
                { id = 'prop:list:' .. index, label = 'Change list', icon = 'Pencil', variant = 'primary' },
                { id = 'prop:search:' .. index, label = 'Search settings', icon = 'Timer', variant = 'primary' },
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
            type = 'form', id = 'prop-place', title = 'Place props or box targets',
            fields = (function()
                local fields = {
                    { id = 'model', label = 'Prop model', type = 'text',
                        description = 'Leave empty for no prop: a box target is placed where you aim instead.' },
                    { id = 'list', label = 'Item list it gives', type = 'select', options = listOptions(), default = 'none' },
                }
                for _, field in ipairs(searchFields(propSearch(nil))) do fields[#fields + 1] = field end
                return fields
            end)(),
            action = { id = 'prop:place', label = 'Aim and place' },
        }
    elseif editing then
        blocks[#blocks + 1] = { type = 'empty', title = 'You are inside another shell. Leave it first.' }
    else
        blocks[#blocks + 1] = {
            type = 'actions',
            actions = { { id = 'shell:enter', label = 'Enter the shell to edit', icon = 'Door', variant = 'primary' } },
        }
    end

    blocks[#blocks + 1] = {
        type = 'form', id = 'shell-break', title = 'Break-in item',
        fields = { { id = 'breakItem', label = 'Item needed to break in', type = 'text',
            default = setup.breakItem or Config.Robberies.House.defaults.breakItem,
            description = 'The default for every house using this shell. A house can use a different one.' } },
        action = { id = 'shell:breakItem', label = 'Save' },
    }

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
                        { id = 'breakItem', label = 'Break-in item', type = 'text', default = house.breakItem or '',
                            description = ('Empty uses the shell\'s item (%s).'):format((data.setups[house.shell] and data.setups[house.shell].breakItem) or Config.Robberies.House.defaults.breakItem) },
                        { id = 'securityItem', label = 'Security item', type = 'text', default = house.securityItem or '',
                            description = ('Also needed when the security system is on, and it alerts the police. Empty uses %s.'):format(Config.Robberies.House.defaults.securityItem) },
                        { id = 'lowerZ', label = 'Shell depth', type = 'number', min = -300, max = 0, default = house.lowerZ or Config.Robberies.House.defaults.lowerZ,
                            description = 'How far below the entrance the shell is spawned. Change it if the shell clips into something.' },
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

-- A register searches like a prop, with its own words for the target and the progress bar.
local function registerSearch(register)
    local search = propSearch(register)
    if not (register and register.label) then search.label = 'Rob Register' end
    if not (register and register.progressLabel) then search.progressLabel = 'Robbing Register...' end
    return search
end

local function registerFields(register)
    local fields = {
        { id = 'stickyChance', label = 'Sticky note chance (%)', type = 'number', min = 0, max = 100,
            default = register and register.stickyChance or Config.Robberies.Store.defaults.stickyNoteChance,
            description = 'The chance this register gives a sticky note with the safe code.' },
    }
    for _, field in ipairs(searchFields(registerSearch(register))) do
        if field.id == 'time' then field.label = 'Robbery time (ms)' end
        if field.id == 'disable' then field.label = 'Block while robbing' end
        if field.id == 'progressLabel' then field.description = 'Shown on the progress bar while robbing.' end
        if field.id == 'label' then field.description = 'What the target says.' end
        fields[#fields + 1] = field
    end
    return fields
end

-- The form values of a register: its search settings and its sticky note chance.
local function registerFromValues(values)
    local search, err = searchFromValues(values)
    if not search then return nil, err end

    local chance = tonumber(values.stickyChance)
    if not chance or chance < 0 or chance > 100 then return nil, 'Sticky note chance must be between 0 and 100.' end
    if text(values.progressLabel) == '' then search.progressLabel = 'Robbing Register...' end
    search.stickyChance = math.floor(chance)
    return search
end

local function storesView()
    local items = {}
    for _, store in ipairs(data.stores) do
        items[#items + 1] = {
            id = store.id, label = store.label, icon = 'ShoppingBag',
            description = ('%d registers · %d safes · %d police'):format(#store.registers, #store.safes, store.minPolice),
            action = 'store:select:' .. store.id,
        }
    end

    return {
        id = 'stores', label = 'Stores', icon = 'ShoppingBag',
        content = {
            title = 'Stores',
            description = 'A store has registers and safes. Each store sets its own minimum police.',
            blocks = {
                {
                    type = 'form', id = 'store-create', title = 'New store',
                    fields = { { id = 'name', label = 'Name', type = 'text', required = true } },
                    action = { id = 'store:create', label = 'Create store' },
                },
                { type = 'list', id = 'store-list', layout = 'cards', columns = 3, items = items, empty = 'No stores yet.' },
            },
        },
    }
end

local function storeView()
    local store = find(data.stores, selectedStore)
    if not store then
        return {
            id = 'store', label = 'Store', icon = 'ShoppingBag',
            content = { title = 'Store', blocks = { { type = 'empty', title = 'Pick a store first.' } } },
        }
    end

    local registers = {}
    for index, register in ipairs(store.registers) do
        local metadata = { { label = 'Sticky note', value = ('%d%%'):format(register.stickyChance or 0) } }
        for _, entry in ipairs(searchSummary(registerSearch(register))) do metadata[#metadata + 1] = entry end
        registers[#registers + 1] = {
            id = tostring(index), label = register.label or ('Register %d'):format(index), icon = 'MapPin',
            description = coordsLabel(register.coords), metadata = metadata,
            actions = {
                { id = 'register:edit:' .. index, label = 'Settings', icon = 'Pencil', variant = 'primary' },
                { id = 'register:remove:' .. index, label = 'Delete', icon = 'Trash2', variant = 'destructive' },
            },
        }
    end

    local safes = {}
    for index, safe in ipairs(store.safes) do
        safes[#safes + 1] = {
            id = tostring(index), label = ('Safe %d'):format(index), icon = 'MapPin', description = coordsLabel(safe.coords),
            actions = { { id = 'safe:remove:' .. index, label = 'Delete', icon = 'Trash2', variant = 'destructive' } },
        }
    end

    return {
        id = 'store', label = store.label, icon = 'ShoppingBag',
        content = {
            title = store.label,
            description = 'Place the registers and safes by aiming at them. A sticky note from any register gives the store\'s safe code.',
            blocks = {
                {
                    type = 'form', id = 'store-data', title = 'Settings',
                    fields = {
                        { id = 'label', label = 'Name', type = 'text', required = true, default = store.label },
                        { id = 'minPolice', label = 'Minimum police', type = 'number', min = 0, max = 100, default = store.minPolice },
                    },
                    action = { id = 'store:save', label = 'Save' },
                },
                {
                    type = 'form', id = 'register-place', title = 'Place registers',
                    fields = registerFields(nil),
                    action = { id = 'store:placeRegisters', label = 'Aim and place registers' },
                },
                { type = 'list', id = 'store-registers', layout = 'cards', columns = 3, title = ('Registers (%d)'):format(#registers), items = registers, empty = 'No registers yet.' },
                { type = 'actions', actions = { { id = 'store:placeSafes', label = 'Aim and place safes', icon = 'Lock', variant = 'primary' } } },
                { type = 'list', id = 'store-safes', layout = 'cards', columns = 3, title = ('Safes (%d)'):format(#safes), items = safes, empty = 'No safes yet.' },
                { type = 'actions', title = 'Danger zone', actions = { { id = 'store:delete', label = 'Delete store', variant = 'destructive' } } },
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
    navigation[#navigation + 1] = storesView()
    if selectedStore and find(data.stores, selectedStore) then navigation[#navigation + 1] = storeView() end
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

local function askAmount(label, title, current)
    local result = QB.nui.openInputDialog({
        { id = 'amount', label = 'Amount', type = 'number', min = 1, max = Limits.itemAmount, default = current or 1, required = true },
    }, title, label)
    if not result or result.cancelled then return nil end

    local amount = tonumber(result.values and result.values.amount)
    return amount and math.floor(amount) or nil
end

local function copyItems(list)
    local items = {}
    for index, entry in ipairs(list.items) do items[index] = { item = entry.item, amount = entry.amount } end
    return items
end

local function saveItems(list, items, message)
    local result, err = call('lists:items', list.id, items)
    if not result then return fail(err) end
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
        local reason = notInsideReason(selectedShell)
        if reason then return fail(reason) end
        pendingTool, currentView = { kind = 'exit' }, 'shell'
        return { close = true }
    end

    if actionId == 'shell:breakItem' then
        local result, err = call('shells:breakItem', selectedShell, text(values.breakItem))
        if not result then return fail(err) end
        return refresh(notice('Saved.'))
    end

    if actionId == 'shell:clear' then
        if editing and editing.key == selectedShell then return fail('Leave the shell first.') end
        if not confirmed('Clear setup?', 'This removes the exit and every prop. Houses using this shell will have nothing to rob.') then return refresh() end
        local result, err = call('shells:clear', selectedShell)
        if not result then return fail(err) end
        return refresh(notice('Setup cleared.'))
    end

    if actionId == 'prop:place' then
        local reason = notInsideReason(selectedShell)
        if reason then return fail(reason) end
        local model = text(values.model)
        if model == '' then
            model = nil -- no prop: a box target
        elseif not IsModelInCdimage(joaat(model)) then
            return fail('Unknown prop model.')
        end
        local listId = text(values.list)
        local search, searchErr = searchFromValues(values)
        if not search then return fail(searchErr) end
        pendingTool = {
            kind = 'props', model = model, search = search,
            list = listId ~= '' and listId ~= 'none' and listId or nil,
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

    index = tonumber(actionId:match('^prop:search:(%d+)$'))
    if index then
        local props = copyProps(selectedShell)
        local prop = props[index]
        if not prop then return refresh() end

        local result = QB.nui.openInputDialog(searchFields(propSearch(prop)), 'Search settings', prop.label or prop.model or 'Search spot')
        if not result or result.cancelled then return refresh() end

        local search, err = searchFromValues(result.values or {})
        if not search then return fail(err) end
        prop.label, prop.progressLabel = search.label, search.progressLabel
        prop.time, prop.anim, prop.disable = search.time, search.anim, search.disable
        return setProps(props, 'Search settings saved.')
    end

    index = tonumber(actionId:match('^prop:list:(%d+)$'))
    if index then
        local props = copyProps(selectedShell)
        local prop = props[index]
        if not prop then return refresh() end

        local result = QB.nui.openInputDialog({
            { id = 'list', label = 'Item list it gives', type = 'select', options = listOptions(), default = prop.list or 'none' },
        }, 'Change list', prop.label or prop.model or 'Search spot')
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
            breakItem = text(values.breakItem),
            securityItem = text(values.securityItem),
            lowerZ = (tonumber(values.lowerZ) ~= Config.Robberies.House.defaults.lowerZ) and tonumber(values.lowerZ) or nil,
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

-- Store actions
local function removeAt(list, index)
    local kept = {}
    for position, entry in ipairs(list) do
        if position ~= index then kept[#kept + 1] = entry end
    end
    return kept
end

local function storeAction(actionId, values)
    if actionId == 'store:create' then
        local result, err = call('stores:create', text(values.name))
        if not result then return fail(err) end
        selectedStore, currentView = result.id, 'store'
        return refresh(notice('Store created. Place its registers and safes below.'))
    end

    local selectId = actionId:match('^store:select:(.+)$')
    if selectId then
        if not find(data.stores, selectId) then return fail('Unknown store.') end
        selectedStore, currentView = selectId, 'store'
        return refresh()
    end

    local store = find(data.stores, selectedStore)
    if not store then return fail('Pick a store first.') end

    if actionId == 'store:save' then
        local result, err = call('stores:details', store.id, { label = text(values.label), minPolice = tonumber(values.minPolice) })
        if not result then return fail(err) end
        return refresh(notice('Saved.'))
    end

    if actionId == 'store:placeRegisters' then
        local register, err = registerFromValues(values)
        if not register then return fail(err) end
        pendingTool, currentView = {
            kind = 'stores', id = store.id, field = 'registers',
            build = function(c)
                return {
                    coords = { x = c.x, y = c.y, z = c.z }, stickyChance = register.stickyChance, label = register.label,
                    progressLabel = register.progressLabel, time = register.time, anim = register.anim, disable = register.disable,
                }
            end,
        }, 'store'
        return { close = true }
    end

    if actionId == 'store:placeSafes' then
        pendingTool, currentView = {
            kind = 'stores', id = store.id, field = 'safes',
            build = function(c) return { coords = { x = c.x, y = c.y, z = c.z, w = c.w } } end,
        }, 'store'
        return { close = true }
    end

    local index = tonumber(actionId:match('^register:remove:(%d+)$'))
    if index then
        local result, err = call('stores:registers', store.id, removeAt(store.registers, index))
        if not result then return fail(err) end
        return refresh(notice('Register deleted.'))
    end

    index = tonumber(actionId:match('^safe:remove:(%d+)$'))
    if index then
        local result, err = call('stores:safes', store.id, removeAt(store.safes, index))
        if not result then return fail(err) end
        return refresh(notice('Safe deleted.'))
    end

    index = tonumber(actionId:match('^register:edit:(%d+)$'))
    if index then
        local registers = copyList(store.registers)
        local register = registers[index]
        if not register then return refresh() end

        local result = QB.nui.openInputDialog(registerFields(register), 'Register settings', register.label or ('Register %d'):format(index))
        if not result or result.cancelled then return refresh() end

        local edited, err = registerFromValues(result.values or {})
        if not edited then return fail(err) end
        registers[index] = {
            coords = register.coords, stickyChance = edited.stickyChance, label = edited.label,
            progressLabel = edited.progressLabel, time = edited.time, anim = edited.anim, disable = edited.disable,
        }
        local saved, saveErr = call('stores:registers', store.id, registers)
        if not saved then return fail(saveErr) end
        return refresh(notice('Register saved.'))
    end

    if actionId == 'store:delete' then
        if not confirmed('Delete store?', ('This removes %s, its registers and its safes.'):format(store.label)) then return refresh() end
        local result, err = call('stores:delete', store.id)
        if not result then return fail(err) end
        selectedStore, currentView = nil, 'stores'
        return refresh(notice('Store deleted.'))
    end

    return refresh()
end

local function onAction(actionId, context)
    local values = context and context.value or {}

    if actionId:match('^list:') then return listAction(actionId, values) end
    if actionId:match('^shell:') or actionId:match('^prop:') then return shellAction(actionId, values) end
    if actionId:match('^house:') then return houseAction(actionId, values) end
    if actionId:match('^store:') or actionId:match('^register:') or actionId:match('^safe:') then return storeAction(actionId, values) end
    return refresh()
end

QB.nui.registerApp({
    id = APP_ID,
    title = 'Robbery Creator',
    icon = 'Home',
    layout = 'standard',
    width = 1100,
    height = 760,
    defaultView = 'lists',
    navigation = { { id = 'lists', label = 'Item lists', icon = 'Package', content = { title = 'Item lists', blocks = {} } } },
    onAction = onAction,
})

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

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    leaveShell()
end)
