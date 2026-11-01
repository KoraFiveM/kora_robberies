function decodeJson(raw, fallback)
    if type(raw) ~= 'string' or raw == '' then return fallback end
    local ok, decoded = pcall(json.decode, raw)
    return ok and type(decoded) == 'table' and decoded or fallback
end

function trim(value, max)
    if type(value) ~= 'string' or not value:match('%S') then return nil end
    return value:match('^%s*(.-)%s*$'):sub(1, max)
end

function inRange(value, min, max, whole)
    local n = tonumber(value)
    if not n or n ~= n or n < min or n > max then return nil end
    return whole and math.floor(n) or n
end

function cleanName(value, max, pattern)
    local text = trim(value, max)
    if not text then return nil end
    return text:match(pattern) and text or false
end

function cleanVec(value, limit)
    if type(value) ~= 'table' then return nil end
    limit = limit or 10000.0
    local x, y, z = inRange(value.x, -limit, limit), inRange(value.y, -limit, limit), inRange(value.z, -limit, limit)
    if x and y and z then return { x = x, y = y, z = z } end
end

function copyTable(value)
    if type(value) ~= 'table' then return value end
    local copy = {}
    for key, inner in pairs(value) do copy[key] = copyTable(inner) end
    return copy
end

function isAdmin(src)
    src = tonumber(src)
    return src ~= nil and src > 0 and IsPlayerAceAllowed(src, Config.Creator.ace)
end

function validId(id)
    return type(id) == 'string' and #id <= 48 and id:match('^[%w_]+$') ~= nil
end

function makeId(label, isTaken)
    local base = label:lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
    base = base:sub(1, 36)
    if base == '' then base = 'new' end

    local id, n = base, 1
    while isTaken(id) do
        n = n + 1
        id = ('%s_%d'):format(base, n)
    end
    return id
end

function allItems()
    local ok, items = pcall(function() return exports['qb-core']:GetShared('Items') end)
    if ok and type(items) == 'table' then return items end
    items = exports.kora_core:getShared('items')
    return type(items) == 'table' and items or {}
end

function itemExists(item)
    return type(allItems()[item]) == 'table'
end

function itemEntry(shared, name)
    local info = shared[name]
    if type(info) ~= 'table' then return nil end
    local image = type(info.image) == 'string' and info.image ~= '' and ('nui://qbinventory/images/' .. info.image) or nil
    return { label = tostring(info.label or name), image = image }
end

function searchItems(query, isAdded)
    local text = trim(query, 64)
    if not text then return false, 'Type part of an item name or label to search.' end
    local needle = text:lower()

    local shared, results = allItems(), {}
    for name in pairs(shared) do
        local entry = type(name) == 'string' and itemEntry(shared, name)
        if entry and (name:lower():find(needle, 1, true) or entry.label:lower():find(needle, 1, true)) then
            results[#results + 1] = { name = name, label = entry.label, image = entry.image, added = isAdded(name) == true }
        end
    end

    table.sort(results, function(a, b)
        local la, lb = a.label:lower(), b.label:lower()
        if la ~= lb then return la < lb end
        return a.name < b.name
    end)
    local total = #results
    while #results > Limits.searchResults do results[#results] = nil end
    return { results = results, total = total }
end

local tables = { lists = 'qbrobberies_lists', shells = 'qbrobberies_shells', houses = 'qbrobberies_houses', stores = 'qbrobberies_stores' }
function dbSave(kind, id, data)
    local name = tables[kind]
    if not name then return false, 'Unknown table.' end

    local rows = QB.sql.query(('SELECT `id` FROM `%s` WHERE `id` = ? LIMIT 1'):format(name), { id })
    if rows and rows[1] then
        return QB.sql.update(('UPDATE `%s` SET `data` = ? WHERE `id` = ?'):format(name), { json.encode(data), id })
    end
    return QB.sql.update(('INSERT INTO `%s` (`id`, `data`) VALUES (?, ?)'):format(name), { id, json.encode(data) })
end

function dbDelete(kind, id)
    local name = tables[kind]
    if not name then return false, 'Unknown table.' end
    return QB.sql.update(('DELETE FROM `%s` WHERE `id` = ?'):format(name), { id })
end

function dbRows(kind)
    return QB.sql.query(('SELECT * FROM `%s`'):format(tables[kind])) or {}
end

function isNear(src, coords, radius)
    if not coords then return false end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not (x and y and z) then return false end
    return QB.distance.player(src, vec3(x, y, z), radius or 5.0)
end

local cooldowns = {}
function onCooldown(src, key)
    return cooldowns[key] ~= nil and cooldowns[key][src] == true
end

function startCooldown(src, key, duration)
    cooldowns[key] = cooldowns[key] or {}
    cooldowns[key][src] = true
    SetTimeout(duration, function() cooldowns[key][src] = nil end)
end

AddEventHandler('playerDropped', function()
    local src = source
    for _, timers in pairs(cooldowns) do timers[src] = nil end
end)

local warned = false
function playerJob(src)
    local player = exports.kora_core:getPlayer(src)
    local data = type(player) == 'table' and (player.PlayerData or player.playerData or player.data or player) or nil
    local job = type(data) == 'table' and data.job
    if type(job) ~= 'table' then
        if not warned then
            warned = true
            QB.print.warn('[qbrobberies] could not read a player\'s job, so no police are counted. Fix playerJob() in server/_functions.lua.')
        end
        return nil, false
    end
    return job.name, job.onduty ~= false
end

function PoliceOnDuty()
    local count = 0
    for _, id in ipairs(GetPlayers()) do
        local name, onDuty = playerJob(tonumber(id))
        if name == Config.Robberies.House.defaults.policeJob and onDuty then count = count + 1 end
    end
    return count
end
