-- Everything the creator saves, kept in memory and in the database. Server only: players never receive it.
--   Lists  [id]       = { label, items = { { item, amount } } }
--   Setups [shellKey] = { exit = offset, props = { { model, offset, heading, list, label } } }
--   Houses [id]       = { label, shell, coords, minPolice, cooldown, hours, security }

Lists = {}
Setups = {}
Houses = {}
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
    TriggerClientEvent('qbrobberies:client:reload', -1) -- players re-read where the houses are
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
    TriggerClientEvent('qbrobberies:client:reload', -1)
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
    while GetResourceState('qbsql') ~= 'started' do Wait(500) end

    -- The tables are also in sql/qbrobberies.sql. This only saves forgetting to run it.
    pcall(QB.sql.update, 'CREATE TABLE IF NOT EXISTS `qbrobberies_lists` (`id` varchar(48) NOT NULL, `data` longtext NOT NULL, PRIMARY KEY (`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4')
    pcall(QB.sql.update, 'CREATE TABLE IF NOT EXISTS `qbrobberies_shells` (`id` varchar(48) NOT NULL, `data` longtext NOT NULL, PRIMARY KEY (`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4')
    pcall(QB.sql.update, 'CREATE TABLE IF NOT EXISTS `qbrobberies_houses` (`id` varchar(48) NOT NULL, `data` longtext NOT NULL, PRIMARY KEY (`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4')

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
    end)
    if not ok then
        QB.print.warn(('[qbrobberies] could not read the database: %s'):format(tostring(err)))
        return
    end

    DataLoaded = true

    -- A house whose shell has no exit cannot be robbed. Say so once, so it is not a silent mystery.
    for id, house in pairs(Houses) do
        local setup = Setups[house.shell]
        if not (setup and setup.exit) then
            QB.print.warn(('[qbrobberies] house "%s" uses the shell "%s", which has no exit set yet. Players cannot get in until you set it in /%s.'):format(id, house.shell, Config.Creator.command))
        end
    end
end)
