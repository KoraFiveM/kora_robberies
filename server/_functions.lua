-- Helpers used by every server script. Anything that comes from the creator goes through these.

function decodeJson(raw, fallback)
    if type(raw) ~= 'string' or raw == '' then return fallback end
    local ok, decoded = pcall(json.decode, raw)
    return ok and type(decoded) == 'table' and decoded or fallback
end

-- A trimmed string of at most `max` characters, or nil when it is empty or not a string.
function trim(value, max)
    if type(value) ~= 'string' or not value:match('%S') then return nil end
    return value:match('^%s*(.-)%s*$'):sub(1, max)
end

-- A number inside [min, max] (rounded down when `whole`), or nil. Rejects NaN.
function inRange(value, min, max, whole)
    local n = tonumber(value)
    if not n or n ~= n or n < min or n > max then return nil end
    return whole and math.floor(n) or n
end

-- trim() plus a character check. nil = empty, false = it has characters the pattern does not allow.
function cleanName(value, max, pattern)
    local text = trim(value, max)
    if not text then return nil end
    return text:match(pattern) and text or false
end

-- { x, y, z } with every part a real number inside +-limit, or nil.
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

-- ----------------------------------------------------------------------------
-- Items
-- ----------------------------------------------------------------------------

function allItems()
    local ok, items = pcall(function() return exports['qb-core']:GetShared('Items') end)
    if ok and type(items) == 'table' then return items end
    ok, items = pcall(function() return exports.qbcore:getShared('items') end)
    return ok and type(items) == 'table' and items or {}
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

-- Items whose name or label contains the query. isAdded(name) marks the ones already in the list.
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

-- ----------------------------------------------------------------------------
-- Database. One table per kind, one row per id, the data as JSON.
-- ----------------------------------------------------------------------------

local tables = { lists = 'qbrobberies_lists', shells = 'qbrobberies_shells', houses = 'qbrobberies_houses' }

-- Inserts the row, or updates it when it already exists. Returns ok, err.
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
