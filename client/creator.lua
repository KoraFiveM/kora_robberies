local APP_ID = 'kora_robberies:creator'

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
    Kora.notify.send({ title = Kora.lang('house_creator'), message = message, type = kind or 'error' })
end

local function confirmed(title, message)
    local answer = Kora.nui.openAlert({ title = title, message = message, confirmLabel = Kora.lang('delete') })
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
        { id = 'label', label = Kora.lang('target_label'), type = 'text', default = search.label or '', description = Kora.lang('target_label_help') },
        { id = 'progressLabel', label = Kora.lang('progress_text'), type = 'text', default = search.progressLabel, description = Kora.lang('search_progress_help') },
        { id = 'time', label = Kora.lang('search_time_ms'), type = 'number', min = 500, max = 300000, required = true, default = search.time },
        { id = 'animDict', label = Kora.lang('animation_dictionary'), type = 'text', default = anim.dict or '',
            description = Kora.lang('anim_dict_help') },
        { id = 'animClip', label = Kora.lang('animation_clip'), type = 'text', default = anim.clip or '', description = Kora.lang('anim_clip_help') },
        { id = 'animFlag', label = Kora.lang('animation_flag'), type = 'number', min = 0, max = 65535, default = anim.flag or DefaultSearch.anim.flag,
            description = Kora.lang('anim_flag_help') },
    }
    local blocked = {}
    for _, option in ipairs(ProgressDisableOptions) do
        if search.disable[option.value] == true then blocked[#blocked + 1] = option.value end
    end
    fields[#fields + 1] = { id = 'disable', label = Kora.lang('block_while_searching'), type = 'multiselect', options = ProgressDisableOptions,
        default = blocked, description = Kora.lang('search_controls_help') }
    return fields
end

local function searchFromValues(values)
    local time = tonumber(values.time)
    if not time then
        return nil, Kora.lang('search_time_required')
    end

    local dict, clip = text(values.animDict), text(values.animClip)
    local anim = false
    if dict ~= '' or clip ~= '' then
        if dict == '' or clip == '' then
            return nil, Kora.lang('anim_dict_clip_required')
        end
        if not DoesAnimDictExist(dict) then
            return nil, Kora.lang('unknown_anim_dict')
        end
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
        { label = Kora.lang('progress_text'), value = search.progressLabel },
        { label = Kora.lang('search_time'), value = ('%.1f s'):format(search.time / 1000) },
        { label = Kora.lang('animation'), value = search.anim and ('%s / %s'):format(search.anim.dict, search.anim.clip) or 'None' },
        { label = Kora.lang('blocks'), value = #blocked > 0 and table.concat(blocked, ', ') or 'Nothing' },
    }
end

local function call(name, ...)
    local result, err = Kora.callback.trigger('kora_robberies:creator:' .. name, ...)
    if not result then
        return nil, err or Kora.lang('request_failed')
    end
    if result.lists then data = result end
    return result
end

local function copyList(list)
    local copy = {}
    for index, entry in ipairs(list) do copy[index] = entry end
    return copy
end

local function removeAt(list, index)
    local kept = {}
    for position, entry in ipairs(list) do
        if position ~= index then kept[#kept + 1] = entry end
    end
    return kept
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
        Kora.print.warn(('[kora_robberies] could not enter the %s shell: %s'):format(key, tostring(err)))
        return toast(err)
    end

    editing = { key = key, spawned = spawned, origin = origin, heading = heading, preview = {} }

    local entry = ShellEntryCoords(spawned)
    RequestCollisionAtCoord(entry.x, entry.y, entry.z)
    SetEntityCoords(ped, entry.x, entry.y, entry.z)
    Wait(500)
    rebuildPreview()
    toast(Kora.lang('inside_shell_place_props', HouseShellByKey[key].label), 'success')
end

local function notInsideReason(key)
    if not editing then return 'You are not inside a shell yet. Press Enter the shell to edit.' end
    if editing.key ~= key then
        return Kora.lang('inside_shell_leave_first', HouseShellByKey[editing.key].label)
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
        local aimed = Kora.raycast.getCoords(tool.model and { type = 'object', object = tool.model } or {})
        local c = aimed and aimed.coords
        if not c then return end

        local offset, heading = ToShellOffset(editing.spawned, vector3(c.x, c.y, c.z), c.w or aimed.heading or 0.0)
        local props = copyList(setupFor(editing.key).props)
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
    local aimed = Kora.raycast.getCoords({})
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
    toast(Kora.lang('exit_saved'), 'success')
end

local function placeHouses(key)
    local placed = 0
    while true do
        local c = aim()
        if not c then break end

        local result, err = call('houses:create', key, c)
        if not result then return toast(err) end
        placed = placed + 1
        toast(Kora.lang('house_placed', placed), 'success')
    end
end

local function moveHouse(id)
    local c = aim()
    if not c then return end

    local result, err = call('houses:coords', id, c)
    if not result then return toast(err) end
    toast(Kora.lang('entrance_moved'), 'success')
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
        id = 'lists', label = Kora.lang('item_lists'), icon = 'Package',
        content = {
            title = Kora.lang('item_lists'),
            description = Kora.lang('item_list_help'),
            blocks = {
                {
                    type = 'form', id = 'list-create', title = Kora.lang('new_list'),
                    fields = { { id = 'name', label = Kora.lang('name'), type = 'text', required = true } },
                    action = { id = 'list:create', label = Kora.lang('create_list') },
                },
                { type = 'list', id = 'list-list', layout = 'cards', columns = 3, items = items, empty = Kora.lang('no_lists_yet') },
            },
        },
    }
end

local function foundCards(results)
    local cards = {}
    for _, result in ipairs(results) do
        cards[#cards + 1] = {
            id = result.name, label = result.label, description = result.name, image = result.image,
            metadata = result.added and { { label = Kora.lang('status'), value = 'Already in the list' } } or nil,
            actions = result.added and {} or { { id = 'list:add:' .. result.name, label = Kora.lang('add'), icon = 'Plus', variant = 'primary' } },
        }
    end
    return cards
end

local function listView()
    local list = find(data.lists, selectedList)
    if not list then
        return {
            id = 'list', label = Kora.lang('list'), icon = 'Package',
            content = { title = Kora.lang('list'), blocks = { { type = 'empty', title = Kora.lang('pick_a_list_first') } } },
        }
    end

    local items = {}
    for _, entry in ipairs(list.items) do
        items[#items + 1] = {
            id = entry.item, label = itemLabel(entry.item), description = entry.item, image = itemImage(entry.item),
            metadata = { { label = Kora.lang('amount'), value = ('%dx'):format(entry.amount) } },
            actions = {
                { id = 'list:edit:' .. entry.item, label = Kora.lang('edit'), icon = 'Pencil', variant = 'primary' },
                { id = 'list:remove:' .. entry.item, label = Kora.lang('remove'), icon = 'Trash2', variant = 'destructive' },
            },
        }
    end

    local found = foundCards(search.results)
    local blocks = {
        { type = 'list', id = 'list-items', layout = 'cards', columns = 3, title = ('Items (%d)'):format(#items), items = items, empty = Kora.lang('list_empty_help') },
        {
            type = 'form', id = 'list-search', title = Kora.lang('add_items'),
            fields = { { id = 'query', label = Kora.lang('search_all_items'), type = 'text', default = search.query or '',
                description = Kora.lang('search_hint') } },
            action = { id = 'list:search', label = Kora.lang('search') },
        },
    }
    if search.query then
        local more = search.total > #found and (' of ' .. search.total) or ''
        blocks[#blocks + 1] = {
            type = 'list', id = 'list-results', layout = 'cards', columns = 3,
            title = ('Results for "%s" (%d%s)'):format(search.query, #found, more),
            items = found, empty = Kora.lang('no_items_match_that_search'),
        }
    end
    blocks[#blocks + 1] = {
        type = 'actions', title = Kora.lang('danger_zone'),
        actions = { { id = 'list:delete', label = Kora.lang('delete_list'), variant = 'destructive' } },
    }

    return {
        id = 'list', label = list.label, icon = 'Package',
        content = { title = list.label, description = Kora.lang('item_list_details'), blocks = blocks },
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
        id = 'shells', label = Kora.lang('shells'), icon = 'Door',
        content = {
            title = Kora.lang('shells'),
            description = Kora.lang('shell_setup_help'),
            blocks = { { type = 'list', id = 'shell-list', layout = 'cards', columns = 3, items = items, empty = Kora.lang('no_shells_in_the_config') } },
        },
    }
end

local function propCards(props)
    local cards = {}
    for index, prop in ipairs(props) do
        local metadata = { { label = Kora.lang('gives'), value = listLabel(prop.list) } }
        for _, entry in ipairs(searchSummary(propSearch(prop))) do metadata[#metadata + 1] = entry end
        cards[#cards + 1] = {
            id = tostring(index),
            label = prop.label or prop.model or Kora.lang('search_spot'),
            icon = prop.model and 'MapPin' or 'Square',
            description = ('%s · %s'):format(prop.model or 'Box target', coordsLabel(prop.offset)),
            metadata = metadata,
            actions = {
                { id = 'prop:list:' .. index, label = Kora.lang('change_list'), icon = 'Pencil', variant = 'primary' },
                { id = 'prop:search:' .. index, label = Kora.lang('search_settings'), icon = 'Timer', variant = 'primary' },
                { id = 'prop:remove:' .. index, label = Kora.lang('delete'), icon = 'Trash2', variant = 'destructive' },
            },
        }
    end
    return cards
end

local function listOptions()
    local options = { { value = 'none', label = Kora.lang('no_list') } }
    for _, list in ipairs(data.lists) do options[#options + 1] = { value = list.id, label = list.label } end
    return options
end

local function shellView()
    local def = HouseShellByKey[selectedShell]
    if not def then
        return {
            id = 'shell', label = Kora.lang('shell'), icon = 'Door',
            content = { title = Kora.lang('shell'), blocks = { { type = 'empty', title = Kora.lang('pick_a_shell_first') } } },
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
                { id = 'shell:leave', label = Kora.lang('leave_the_shell'), icon = 'X' },
            },
        }
        local fields = {
            { id = 'model', label = Kora.lang('prop_model'), type = 'text',
                description = Kora.lang('prop_model_help') },
            { id = 'list', label = Kora.lang('item_list_it_gives'), type = 'select', options = listOptions(), default = 'none' },
        }
        for _, field in ipairs(searchFields(propSearch(nil))) do fields[#fields + 1] = field end
        blocks[#blocks + 1] = {
            type = 'form', id = 'prop-place', title = Kora.lang('place_props_or_box_targets'),
            fields = fields,
            action = { id = 'prop:place', label = Kora.lang('aim_and_place') },
        }
    elseif editing then
        blocks[#blocks + 1] = { type = 'empty', title = Kora.lang('other_shell_active') }
    else
        blocks[#blocks + 1] = {
            type = 'actions',
            actions = { { id = 'shell:enter', label = Kora.lang('enter_the_shell_to_edit'), icon = 'Door', variant = 'primary' } },
        }
    end

    blocks[#blocks + 1] = {
        type = 'form', id = 'shell-break', title = Kora.lang('break_in_item'),
        fields = { { id = 'breakItem', label = Kora.lang('item_needed_to_break_in'), type = 'text',
            default = setup.breakItem or Config.Robberies.House.defaults.breakItem,
            description = Kora.lang('break_item_help') } },
        action = { id = 'shell:breakItem', label = Kora.lang('save') },
    }

    local props = propCards(setup.props)
    blocks[#blocks + 1] = { type = 'list', id = 'shell-props', layout = 'cards', columns = 3, title = ('Props (%d)'):format(#props), items = props, empty = Kora.lang('props_empty_help') }
    if data.setups[def.key] then
        blocks[#blocks + 1] = {
            type = 'actions', title = Kora.lang('danger_zone'),
            actions = { { id = 'shell:clear', label = Kora.lang('clear_this_shell_s_setup'), variant = 'destructive' } },
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
        id = 'houses', label = Kora.lang('houses'), icon = 'Home',
        content = {
            title = Kora.lang('houses'),
            description = Kora.lang('house_placement_help'),
            blocks = {
                {
                    type = 'form', id = 'house-create', title = Kora.lang('new_houses'),
                    fields = {
                        { id = 'shell', label = Kora.lang('shell'), type = 'select', options = shellOptions, default = shellOptions[1] and shellOptions[1].value },
                    },
                    action = { id = 'house:create', label = Kora.lang('aim_and_place_houses') },
                },
                { type = 'list', id = 'house-list', layout = 'cards', columns = 3, items = items, empty = Kora.lang('no_houses_yet') },
            },
        },
    }
end

local function houseView()
    local house = find(data.houses, selectedHouse)
    if not house then
        return {
            id = 'house', label = Kora.lang('house'), icon = 'Home',
            content = { title = Kora.lang('house'), blocks = { { type = 'empty', title = Kora.lang('pick_a_house_first') } } },
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
                    type = 'form', id = 'house-data', title = Kora.lang('settings'),
                    fields = {
                        { id = 'label', label = Kora.lang('name'), type = 'text', required = true, default = house.label },
                        { id = 'minPolice', label = Kora.lang('minimum_police'), type = 'number', min = 0, max = 100, default = house.minPolice },
                        { id = 'cooldown', label = Kora.lang('cooldown_minutes'), type = 'number', min = 0, max = 1440, default = house.cooldown },
                        { id = 'security', label = Kora.lang('security_system'), type = 'select', default = house.security and 'enabled' or 'disabled',
                            options = { { value = 'enabled', label = Kora.lang('enabled') }, { value = 'disabled', label = Kora.lang('disabled') } } },
                        { id = 'breakItem', label = Kora.lang('break_in_item'), type = 'text', default = house.breakItem or '',
                            description = ('Empty uses the shell\'s item (%s).'):format((data.setups[house.shell] and data.setups[house.shell].breakItem) or Config.Robberies.House.defaults.breakItem) },
                        { id = 'securityItem', label = Kora.lang('security_item'), type = 'text', default = house.securityItem or '',
                            description = ('Also needed when the security system is on, and it alerts the police. Empty uses %s.'):format(Config.Robberies.House.defaults.securityItem) },
                        { id = 'lowerZ', label = Kora.lang('shell_depth'), type = 'number', min = -300, max = 0, default = house.lowerZ or Config.Robberies.House.defaults.lowerZ,
                            description = Kora.lang('shell_depth_help') },
                        { id = 'timeLimit', label = Kora.lang('robbery_times'), type = 'select', default = house.hours and 'limited' or 'any',
                            options = { { value = 'any', label = Kora.lang('any_time') }, { value = 'limited', label = Kora.lang('hours_limited') } } },
                        { id = 'timeFrom', label = Kora.lang('from_hour_0_23'), type = 'number', min = 0, max = 23, default = hours.from },
                        { id = 'timeTo', label = Kora.lang('to_hour_0_23'), type = 'number', min = 0, max = 23, default = hours.to },
                    },
                    action = { id = 'house:save', label = Kora.lang('save') },
                },
                { type = 'actions', actions = { { id = 'house:coords', label = Kora.lang('aim_and_move_the_entrance'), icon = 'MapPin', variant = 'primary' } } },
                { type = 'actions', title = Kora.lang('danger_zone'), actions = { { id = 'house:delete', label = Kora.lang('delete_house'), variant = 'destructive' } } },
            },
        },
    }
end

local function registerSearch(register)
    local search = propSearch(register)
    if not (register and register.label) then search.label = Kora.lang('rob_register') end
    if not (register and register.progressLabel) then search.progressLabel = 'Robbing Register...' end
    return search
end

local function registerFields(register)
    local fields = {
        { id = 'stickyChance', label = Kora.lang('sticky_note_chance'), type = 'number', min = 0, max = 100,
            default = register and register.stickyChance or Config.Robberies.Store.defaults.stickyNoteChance,
            description = Kora.lang('sticky_note_help') },
    }
    for _, field in ipairs(searchFields(registerSearch(register))) do
        if field.id == 'time' then field.label = Kora.lang('robbery_time_ms') end
        if field.id == 'disable' then field.label = Kora.lang('block_while_robbing') end
        if field.id == 'progressLabel' then field.description = Kora.lang('robbery_progress_help') end
        if field.id == 'label' then field.description = Kora.lang('what_the_target_says') end
        fields[#fields + 1] = field
    end
    return fields
end

local function registerFromValues(values)
    local search, err = searchFromValues(values)
    if not search then return nil, err end

    local chance = tonumber(values.stickyChance)
    if not chance or chance < 0 or chance > 100 then
        return nil, Kora.lang('sticky_chance_range')
    end
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
        id = 'stores', label = Kora.lang('stores'), icon = 'ShoppingBag',
        content = {
            title = Kora.lang('stores'),
            description = Kora.lang('store_setup_help'),
            blocks = {
                {
                    type = 'form', id = 'store-create', title = Kora.lang('new_store'),
                    fields = { { id = 'name', label = Kora.lang('name'), type = 'text', required = true } },
                    action = { id = 'store:create', label = Kora.lang('create_store') },
                },
                { type = 'list', id = 'store-list', layout = 'cards', columns = 3, items = items, empty = Kora.lang('no_stores_yet') },
            },
        },
    }
end

local function storeView()
    local store = find(data.stores, selectedStore)
    if not store then
        return {
            id = 'store', label = Kora.lang('store'), icon = 'ShoppingBag',
            content = { title = Kora.lang('store'), blocks = { { type = 'empty', title = Kora.lang('pick_a_store_first') } } },
        }
    end

    local registers = {}
    for index, register in ipairs(store.registers) do
        local metadata = { { label = Kora.lang('sticky_note'), value = ('%d%%'):format(register.stickyChance or 0) } }
        for _, entry in ipairs(searchSummary(registerSearch(register))) do metadata[#metadata + 1] = entry end
        registers[#registers + 1] = {
            id = tostring(index), label = register.label or ('Register %d'):format(index), icon = 'MapPin',
            description = coordsLabel(register.coords), metadata = metadata,
            actions = {
                { id = 'register:edit:' .. index, label = Kora.lang('settings'), icon = 'Pencil', variant = 'primary' },
                { id = 'register:remove:' .. index, label = Kora.lang('delete'), icon = 'Trash2', variant = 'destructive' },
            },
        }
    end

    local safes = {}
    for index, safe in ipairs(store.safes) do
        safes[#safes + 1] = {
            id = tostring(index), label = ('Safe %d'):format(index), icon = 'MapPin', description = coordsLabel(safe.coords),
            actions = { { id = 'safe:remove:' .. index, label = Kora.lang('delete'), icon = 'Trash2', variant = 'destructive' } },
        }
    end

    return {
        id = 'store', label = store.label, icon = 'ShoppingBag',
        content = {
            title = store.label,
            description = Kora.lang('store_objects_help'),
            blocks = {
                {
                    type = 'form', id = 'store-data', title = Kora.lang('settings'),
                    fields = {
                        { id = 'label', label = Kora.lang('name'), type = 'text', required = true, default = store.label },
                        { id = 'minPolice', label = Kora.lang('minimum_police'), type = 'number', min = 0, max = 100, default = store.minPolice },
                    },
                    action = { id = 'store:save', label = Kora.lang('save') },
                },
                {
                    type = 'form', id = 'register-place', title = Kora.lang('place_registers'),
                    fields = registerFields(nil),
                    action = { id = 'store:placeRegisters', label = Kora.lang('aim_and_place_registers') },
                },
                { type = 'list', id = 'store-registers', layout = 'cards', columns = 3, title = ('Registers (%d)'):format(#registers), items = registers, empty = Kora.lang('no_registers_yet') },
                { type = 'actions', actions = { { id = 'store:placeSafes', label = Kora.lang('aim_and_place_safes'), icon = 'Lock', variant = 'primary' } } },
                { type = 'list', id = 'store-safes', layout = 'cards', columns = 3, title = ('Safes (%d)'):format(#safes), items = safes, empty = Kora.lang('no_safes_yet') },
                { type = 'actions', title = Kora.lang('danger_zone'), actions = { { id = 'store:delete', label = Kora.lang('delete_store'), variant = 'destructive' } } },
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
    Kora.nui.updateApp(APP_ID, { navigation = navigation })
    return { update = { navigation = navigation }, notice = message }
end

local function fail(message)
    return refresh(notice(message, 'destructive'))
end

local function askAmount(label, title, current)
    local result = Kora.nui.openInputDialog({
        { id = 'amount', label = Kora.lang('amount'), type = 'number', min = 1, max = Limits.itemAmount, default = current or 1, required = true },
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
        return refresh(notice(Kora.lang('list_created_add_some_items')))
    end

    local selectId = actionId:match('^list:select:(.+)$')
    if selectId then
        if not find(data.lists, selectId) then
            return fail(Kora.lang('unknown_list'))
        end
        selectedList, currentView = selectId, 'list'
        search = { query = nil, results = {}, total = 0 }
        return refresh()
    end

    local list = find(data.lists, selectedList)
    if not list then
        return fail(Kora.lang('pick_a_list_first'))
    end

    if actionId == 'list:search' then
        local query = text(values.query)
        if query == '' then
            search = { query = nil, results = {}, total = 0 }
            return refresh()
        end
        local result, err = call('lists:search', query, list.id)
        if not result then
            return fail(err or Kora.lang('item_search_failed'))
        end
        search = { query = query, results = result.results or {}, total = result.total or #(result.results or {}) }
        return refresh()
    end

    local addName = actionId:match('^list:add:(.+)$')
    if addName then
        local found
        for _, result in ipairs(search.results) do
            if result.name == addName then found = result break end
        end
        if not found then
            return fail(Kora.lang('item_search_again'))
        end

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
        if not confirmed(Kora.lang('delete_list_question'), Kora.lang('delete_list_message', list.label)) then return refresh() end
        local result, err = call('lists:delete', list.id)
        if not result then return fail(err) end
        selectedList, currentView = nil, 'lists'
        return refresh(notice(Kora.lang('list_deleted')))
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
        if not HouseShellByKey[selectKey] then
            return fail(Kora.lang('unknown_shell'))
        end
        selectedShell, currentView = selectKey, 'shell'
        return refresh()
    end

    if not (selectedShell and HouseShellByKey[selectedShell]) then

        return fail(Kora.lang('pick_a_shell_first'))

    end

    if actionId == 'shell:enter' then
        if editing then
            return fail(Kora.lang('shell_already_inside'))
        end
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
        return refresh(notice(Kora.lang('saved')))
    end

    if actionId == 'shell:clear' then
        if editing and editing.key == selectedShell then
            return fail(Kora.lang('leave_the_shell_first'))
        end
        if not confirmed(Kora.lang('clear_setup'), Kora.lang('clear_shell_confirm')) then return refresh() end
        local result, err = call('shells:clear', selectedShell)
        if not result then return fail(err) end
        return refresh(notice(Kora.lang('setup_cleared')))
    end

    if actionId == 'prop:place' then
        local reason = notInsideReason(selectedShell)
        if reason then return fail(reason) end
        local model = text(values.model)
        if model == '' then
            model = nil -- no prop: a box target
        elseif not IsModelInCdimage(joaat(model)) then
            return fail(Kora.lang('unknown_prop_model'))
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
        return setProps(removeAt(setupFor(selectedShell).props, index), 'Prop deleted.')
    end

    index = tonumber(actionId:match('^prop:search:(%d+)$'))
    if index then
        local props = copyList(setupFor(selectedShell).props)
        local prop = props[index]
        if not prop then return refresh() end

        local result = Kora.nui.openInputDialog(searchFields(propSearch(prop)), Kora.lang('search_settings'), prop.label or prop.model or Kora.lang('search_spot'))
        if not result or result.cancelled then return refresh() end

        local search, err = searchFromValues(result.values or {})
        if not search then return fail(err) end
        prop.label, prop.progressLabel = search.label, search.progressLabel
        prop.time, prop.anim, prop.disable = search.time, search.anim, search.disable
        return setProps(props, 'Search settings saved.')
    end

    index = tonumber(actionId:match('^prop:list:(%d+)$'))
    if index then
        local props = copyList(setupFor(selectedShell).props)
        local prop = props[index]
        if not prop then return refresh() end

        local result = Kora.nui.openInputDialog({
            { id = 'list', label = Kora.lang('item_list_it_gives'), type = 'select', options = listOptions(), default = prop.list or 'none' },
        }, Kora.lang('change_list'), prop.label or prop.model or Kora.lang('search_spot'))
        if not result or result.cancelled then return refresh() end

        local chosen = result.values and result.values.list
        prop.list = chosen ~= 'none' and chosen or nil
        return setProps(props, 'List changed.')
    end

    return refresh()
end

local function houseAction(actionId, values)
    if actionId == 'house:create' then
        local key = text(values.shell)
        if not HouseShellByKey[key] then
            return fail(Kora.lang('pick_a_shell'))
        end
        if editing then
            return fail(Kora.lang('leave_shell_for_house'))
        end
        pendingTool, currentView, selectedHouse = { kind = 'houses', key = key }, 'houses', nil
        return { close = true }
    end

    local selectId = actionId:match('^house:select:(.+)$')
    if selectId then
        if not find(data.houses, selectId) then
            return fail(Kora.lang('unknown_house'))
        end
        selectedHouse, currentView = selectId, 'house'
        return refresh()
    end

    if not (selectedHouse and find(data.houses, selectedHouse)) then

        return fail(Kora.lang('pick_a_house_first'))

    end

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
        return refresh(notice(Kora.lang('saved')))
    end

    if actionId == 'house:coords' then
        if editing then
            return fail(Kora.lang('leave_shell_for_entrance'))
        end
        pendingTool, currentView = { kind = 'moveHouse', id = selectedHouse }, 'house'
        return { close = true }
    end

    if actionId == 'house:delete' then
        local house = find(data.houses, selectedHouse)
        if not confirmed(Kora.lang('delete_house_question'), Kora.lang('delete_house_message', house.label)) then return refresh() end
        local result, err = call('houses:delete', selectedHouse)
        if not result then return fail(err) end
        selectedHouse, currentView = nil, 'houses'
        return refresh(notice(Kora.lang('house_deleted')))
    end

    return refresh()
end

local function storeAction(actionId, values)
    if actionId == 'store:create' then
        local result, err = call('stores:create', text(values.name))
        if not result then return fail(err) end
        selectedStore, currentView = result.id, 'store'
        return refresh(notice(Kora.lang('store_created_help')))
    end

    local selectId = actionId:match('^store:select:(.+)$')
    if selectId then
        if not find(data.stores, selectId) then
            return fail(Kora.lang('unknown_store'))
        end
        selectedStore, currentView = selectId, 'store'
        return refresh()
    end

    local store = find(data.stores, selectedStore)
    if not store then
        return fail(Kora.lang('pick_a_store_first'))
    end

    if actionId == 'store:save' then
        local result, err = call('stores:details', store.id, { label = text(values.label), minPolice = tonumber(values.minPolice) })
        if not result then return fail(err) end
        return refresh(notice(Kora.lang('saved')))
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
        return refresh(notice(Kora.lang('register_deleted')))
    end

    index = tonumber(actionId:match('^safe:remove:(%d+)$'))
    if index then
        local result, err = call('stores:safes', store.id, removeAt(store.safes, index))
        if not result then return fail(err) end
        return refresh(notice(Kora.lang('safe_deleted')))
    end

    index = tonumber(actionId:match('^register:edit:(%d+)$'))
    if index then
        local registers = copyList(store.registers)
        local register = registers[index]
        if not register then return refresh() end

        local result = Kora.nui.openInputDialog(registerFields(register), Kora.lang('register_settings'), register.label or Kora.lang('register_number', index))
        if not result or result.cancelled then return refresh() end

        local edited, err = registerFromValues(result.values or {})
        if not edited then return fail(err) end
        registers[index] = {
            coords = register.coords, stickyChance = edited.stickyChance, label = edited.label,
            progressLabel = edited.progressLabel, time = edited.time, anim = edited.anim, disable = edited.disable,
        }
        local saved, saveErr = call('stores:registers', store.id, registers)
        if not saved then return fail(saveErr) end
        return refresh(notice(Kora.lang('register_saved')))
    end

    if actionId == 'store:delete' then
        if not confirmed(Kora.lang('delete_store_question'), Kora.lang('delete_store_message', store.label)) then return refresh() end
        local result, err = call('stores:delete', store.id)
        if not result then return fail(err) end
        selectedStore, currentView = nil, 'stores'
        return refresh(notice(Kora.lang('store_deleted')))
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

Kora.nui.registerApp({
    id = APP_ID,
    title = Kora.lang('robbery_creator'),
    icon = 'Home',
    layout = 'standard',
    width = 1100,
    height = 760,
    defaultView = 'lists',
    navigation = { { id = 'lists', label = Kora.lang('item_lists'), icon = 'Package', content = { title = Kora.lang('item_lists'), blocks = {} } } },
    onAction = onAction,
})

local function open()
    local result, err = call('get')
    if not result then return toast(err or Kora.lang('admin_permission_required')) end

    while true do
        Kora.nui.updateApp(APP_ID, { navigation = buildNavigation() })
        Kora.nui.openApp(APP_ID, { viewId = currentView })
        if not pendingTool then break end
        runPendingTool()
    end
end

RegisterNetEvent('kora_robberies:creator:open', function()
    if source ~= 65535 then return end
    CreateThread(open)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    leaveShell()
end)
