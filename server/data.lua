-- Everything the creator saves, kept in memory and in the database. Server only: players never receive it.
--   Lists  [id]       = { label, items = { { item, amount } } }
--   Setups [shellKey] = { exit = offset, props = { { model, offset, heading, list, label } } }
--   Houses [id]       = { label, shell, coords, minPolice, cooldown, hours, security }
--   Stores [id]       = { label, minPolice, registers = { { coords, stickyChance, ...search settings } }, safes = { { coords } } }

Lists = {}
Setups = {}
Houses = {}
Stores = {}
DataLoaded = false

function SaveList(id, list)
    local ok, err = dbSave('lists', id, list)
    if not ok then return false, err end
    Lists[id] = list
    return true
end

function SaveSetup(key, setup)
    local ok, err = dbSave('shells', key, setup)
    if not ok then return false, err end
    Setups[key] = setup
    return true
end

function SaveHouse(id, house)
    local ok, err = dbSave('houses', id, house)
    if not ok then return false, err end
    Houses[id] = house
    TriggerClientEvent('kora_robberies:client:reload', -1) -- players re-read where the houses are
    return true
end

function SaveStore(id, store)
    local ok, err = dbSave('stores', id, store)
    if not ok then return false, err end
    Stores[id] = store
    ResetStoreState(id) -- the registers and safes may have moved
    TriggerClientEvent('kora_robberies:client:reloadStores', -1)
    return true
end

function DeleteStore(id)
    local ok, err = dbDelete('stores', id)
    if not ok then return false, err end
    Stores[id] = nil
    ResetStoreState(id)
    TriggerClientEvent('kora_robberies:client:reloadStores', -1)
    return true
end

function DeleteSetup(key)
    local ok, err = dbDelete('shells', key)
    if not ok then return false, err end
    Setups[key] = nil
    return true
end

function DeleteHouse(id)
    local ok, err = dbDelete('houses', id)
    if not ok then return false, err end
    Houses[id] = nil
    TriggerClientEvent('kora_robberies:client:reload', -1)
    return true
end

-- Deleting a list also takes it off every prop that used it.
function DeleteList(id)
    local ok, err = dbDelete('lists', id)
    if not ok then return false, err end
    Lists[id] = nil

    for key, setup in pairs(Setups) do
        local changed = false
        for _, prop in ipairs(setup.props) do
            if prop.list == id then prop.list, changed = nil, true end
        end
        if changed then SaveSetup(key, setup) end
    end
    return true
end

CreateThread(function()
    Wait(1000)
    if not Kora.sql.ready(60000) then
        Kora.logging.warn('data.sql_unavailable', 'kora_sql was unavailable; robbery data is not loaded until restart')
        return
    end
    for _, spec in ipairs(KoraRobberiesSchema) do
        if spec.seed then spec.seed.once = true end
    end
    local reports, schemaErr = Kora.sql.ensureTables(KoraRobberiesSchema)
    if schemaErr then
        Kora.logging.error('schema.setup_failed', 'Robbery schema setup failed', { error = tostring(schemaErr) })
        return
    end
    for _, report in ipairs(reports or {}) do
        for _, warning in ipairs(report.warnings or {}) do
            Kora.logging.warn('schema.table_warning', 'Schema reported a warning for a table', { table = tostring(report.table), warning = tostring(warning) })
        end
    end

    local ok, err = pcall(function()
        -- Lists first: props and setups check that their list exists.
        for _, row in ipairs(dbRows('lists')) do
            if validId(row.id) then Lists[row.id] = readList(row.id, row.data) end
        end
        for _, row in ipairs(dbRows('shells')) do
            if HouseShellByKey[row.id] then Setups[row.id] = readSetup(row.data) end
        end
        for _, row in ipairs(dbRows('houses')) do
            local house = validId(row.id) and readHouse(row.id, row.data)
            if house then Houses[row.id] = house end
        end
        for _, row in ipairs(dbRows('stores')) do
            local store = validId(row.id) and readStore(row.id, row.data)
            if store then Stores[row.id] = store end
        end
    end)
    if not ok then
        Kora.logging.error('data.load_failed', 'Could not read robbery data from the database', { error = tostring(err) })
        return
    end

    DataLoaded = true

    -- A house whose shell has no exit cannot be robbed. Say so once, so it is not a silent mystery.
    for id, house in pairs(Houses) do
        local setup = Setups[house.shell]
        if not (setup and setup.exit) then
            Kora.logging.warn('data.house_shell_no_exit', 'A house uses a shell with no exit set, so players cannot get in until it is set in the creator', {
                houseId = id, shell = house.shell, command = Config.Creator.command,
            })
        end
    end
end)
