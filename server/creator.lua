local function fail(message)
    return false, message
end

local function adminCallback(name, handler)
    QB.callback.register(name, function(src, ...)
        if not isAdmin(src) then return fail('Admin permission required.') end
        if not DataLoaded then return fail('The data is still loading. Try again in a moment.') end
        return handler(src, ...)
    end)
end

local function byLabel(a, b)
    local la, lb = a.label:lower(), b.label:lower()
    if la ~= lb then return la < lb end
    return a.id < b.id
end

local function payload()
    local shared, items = allItems(), {}
    local function track(name)
        if name and items[name] == nil then items[name] = itemEntry(shared, name) or false end
    end

    local lists = {}
    for id, list in pairs(Lists) do
        for _, entry in ipairs(list.items) do track(entry.item) end
        lists[#lists + 1] = { id = id, label = list.label, items = list.items }
    end
    table.sort(lists, byLabel)

    local houses = {}
    for id, house in pairs(Houses) do
        local entry = copyTable(house)
        entry.id = id
        houses[#houses + 1] = entry
    end
    table.sort(houses, byLabel)

    local stores = {}
    for id, store in pairs(Stores) do
        local entry = copyTable(store)
        entry.id = id
        stores[#stores + 1] = entry
    end
    table.sort(stores, byLabel)

    return { lists = lists, setups = Setups, houses = houses, stores = stores, items = items }
end

adminCallback('qbrobberies:creator:get', function()
    return payload()
end)


adminCallback('qbrobberies:creator:lists:create', function(_, label)
    label = trim(label, 48)
    if not label then return fail('Enter a name for the list.') end

    local count = 0
    for _ in pairs(Lists) do count = count + 1 end
    if count >= Limits.lists then return fail(('You can have %d lists at most.'):format(Limits.lists)) end

    local id = makeId(label, function(candidate) return Lists[candidate] ~= nil end)
    local ok, err = SaveList(id, { label = label, items = {} })
    if not ok then return fail(err or 'Failed to save.') end

    local result = payload()
    result.id = id
    return result
end)

adminCallback('qbrobberies:creator:lists:items', function(_, id, items)
    local list = validId(id) and Lists[id]
    if not list then return fail('Unknown list.') end

    local clean, err = cleanItems(items, list.items)
    if not clean then return fail(err) end

    local ok, saveErr = SaveList(id, { label = list.label, items = clean })
    if not ok then return fail(saveErr or 'Failed to save.') end
    return payload()
end)

adminCallback('qbrobberies:creator:lists:search', function(_, query, id)
    local list = validId(id) and Lists[id]
    if not list then return fail('Unknown list.') end

    local inList = {}
    for _, entry in ipairs(list.items) do inList[entry.item] = true end
    return searchItems(query, function(name) return inList[name] == true end)
end)

adminCallback('qbrobberies:creator:lists:delete', function(_, id)
    if not (validId(id) and Lists[id]) then return fail('Unknown list.') end
    local ok, err = DeleteList(id)
    if not ok then return fail(err or 'Failed to delete the list.') end
    return payload()
end)


local function updateSetup(key, change)
    if not HouseShellByKey[key] then return fail('Unknown shell.') end

    local setup = copyTable(Setups[key] or { props = {} })
    local err = change(setup)
    if err then return fail(err) end

    local ok, saveErr = SaveSetup(key, setup)
    if not ok then return fail(saveErr or 'Failed to save.') end
    return payload()
end

adminCallback('qbrobberies:creator:shells:exit', function(_, key, offset)
    return updateSetup(key, function(setup)
        local clean, err = cleanExit(offset)
        if not clean then return err end
        setup.exit = clean
    end)
end)

adminCallback('qbrobberies:creator:shells:props', function(_, key, props)
    return updateSetup(key, function(setup)
        local clean, err = cleanProps(props)
        if not clean then return err end
        setup.props = clean
    end)
end)

adminCallback('qbrobberies:creator:shells:breakItem', function(_, key, item)
    return updateSetup(key, function(setup)
        local clean, err = cleanBreakItem(item)
        if err then return err end
        setup.breakItem = clean
    end)
end)

adminCallback('qbrobberies:creator:shells:clear', function(_, key)
    if not (HouseShellByKey[key] and Setups[key]) then return fail('That shell has no setup.') end
    local ok, err = DeleteSetup(key)
    if not ok then return fail(err or 'Failed to clear the setup.') end
    return payload()
end)

local function updateHouse(id, change)
    local house = validId(id) and Houses[id]
    if not house then return fail('Unknown house.') end

    local updated, err = change(copyTable(house))
    if not updated then return fail(err) end

    local ok, saveErr = SaveHouse(id, updated)
    if not ok then return fail(saveErr or 'Failed to save.') end
    return payload()
end

local function defaultHouseLabel(shellKey)
    local count = 1
    for _, house in pairs(Houses) do
        if house.shell == shellKey then count = count + 1 end
    end
    return ('%s %d'):format(HouseShellByKey[shellKey].label, count):sub(1, 48)
end

adminCallback('qbrobberies:creator:houses:create', function(_, shellKey, coords, label)
    if not HouseShellByKey[shellKey] then return fail('Pick a shell.') end
    local entrance, err = cleanEntrance(coords)
    if not entrance then return fail(err) end
    label = trim(label, 48) or defaultHouseLabel(shellKey)

    local id = makeId(label, function(candidate) return Houses[candidate] ~= nil end)
    local ok, saveErr = SaveHouse(id, newHouse(label, shellKey, entrance))
    if not ok then return fail(saveErr or 'Failed to save.') end

    local result = payload()
    result.id = id
    return result
end)

adminCallback('qbrobberies:creator:houses:details', function(_, id, input)
    return updateHouse(id, function(house)
        return cleanHouseDetails(input, house)
    end)
end)

adminCallback('qbrobberies:creator:houses:coords', function(_, id, coords)
    return updateHouse(id, function(house)
        local entrance, err = cleanEntrance(coords)
        if not entrance then return nil, err end
        house.coords = entrance
        return house
    end)
end)

adminCallback('qbrobberies:creator:houses:delete', function(_, id)
    if not (validId(id) and Houses[id]) then return fail('Unknown house.') end
    local ok, err = DeleteHouse(id)
    if not ok then return fail(err or 'Failed to delete the house.') end
    return payload()
end)


-- ----------------------------------------------------------------------------
-- Stores
-- ----------------------------------------------------------------------------

local function updateStore(id, change)
    local store = validId(id) and Stores[id]
    if not store then return fail('Unknown store.') end

    local updated, err = change(copyTable(store))
    if not updated then return fail(err) end

    local ok, saveErr = SaveStore(id, updated)
    if not ok then return fail(saveErr or 'Failed to save.') end
    return payload()
end

adminCallback('qbrobberies:creator:stores:create', function(_, label)
    label = trim(label, 48)
    if not label then return fail('Enter a name for the store.') end

    local id = makeId(label, function(candidate) return Stores[candidate] ~= nil end)
    local ok, err = SaveStore(id, newStore(label))
    if not ok then return fail(err or 'Failed to save.') end

    local result = payload()
    result.id = id
    return result
end)

adminCallback('qbrobberies:creator:stores:details', function(_, id, input)
    return updateStore(id, function(store)
        return cleanStoreDetails(input, store)
    end)
end)

adminCallback('qbrobberies:creator:stores:registers', function(_, id, list)
    return updateStore(id, function(store)
        local clean, err = cleanRegisters(list)
        if not clean then return nil, err end
        store.registers = clean
        return store
    end)
end)

adminCallback('qbrobberies:creator:stores:safes', function(_, id, list)
    return updateStore(id, function(store)
        local clean, err = cleanSafes(list)
        if not clean then return nil, err end
        store.safes = clean
        return store
    end)
end)

adminCallback('qbrobberies:creator:stores:delete', function(_, id)
    if not (validId(id) and Stores[id]) then return fail('Unknown store.') end
    local ok, err = DeleteStore(id)
    if not ok then return fail(err or 'Failed to delete the store.') end
    return payload()
end)

QB.commands.add(Config.Creator.command, 'Open the robbery creator', nil, false, function(source)
    TriggerClientEvent('qbrobberies:creator:open', source)
end, {
    checkPermission = function(source)
        return isAdmin(source)
    end,
    notify = function(source, message, type_)
        if source == 0 then
            print(('[qbrobberies] %s'):format(message))
            return
        end
        QB.notify.send(source, { title = 'House Creator', message = message, type = type_ })
    end,
    resource = GetCurrentResourceName(),
})
