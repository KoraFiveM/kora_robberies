-- What the creator is allowed to save. Every cleaner returns the clean value, or nil and a message.

local patterns = {
    name = '^[%w_%-%.]+$', -- items and props
}

-- Item lists: { { item, amount } }. `current` is the list as it is now, so an item that
-- was already in it stays valid even if it was removed from the shared items since.
function cleanItems(list, current)
    if type(list) ~= 'table' then return nil, 'Invalid item list.' end

    local already = {}
    for _, entry in ipairs(current or {}) do already[entry.item] = true end

    local clean, seen = {}, {}
    for _, entry in ipairs(list) do
        if #clean >= Limits.listItems then return nil, 'Too many items in one list.' end
        local item = type(entry) == 'table' and cleanName(entry.item, 64, patterns.name)
        if not item then return nil, 'Invalid item name.' end
        if seen[item] then return nil, ('%s is in the list twice.'):format(item) end
        seen[item] = true
        if not already[item] and not itemExists(item) then return nil, ('%s does not exist.'):format(item) end

        local amount = inRange(entry.amount, 1, Limits.itemAmount, true)
        if not amount then
            return nil, ('The amount for %s must be between 1 and %d.'):format(item, Limits.itemAmount)
        end
        clean[#clean + 1] = { item = item, amount = amount }
    end
    return clean
end

-- Props placed in a shell: { model, offset, heading, list, label }. The offset and heading are
-- relative to the shell, so the same setup works wherever the shell is spawned.
function cleanProps(list)
    if type(list) ~= 'table' then return nil, 'Invalid prop list.' end

    local clean = {}
    for _, entry in ipairs(list) do
        if #clean >= Limits.props then return nil, ('A shell can have %d props at most.'):format(Limits.props) end
        if type(entry) ~= 'table' then return nil, 'Invalid prop.' end

        local model = cleanName(entry.model, 64, patterns.name)
        if not model then return nil, 'Enter a valid prop model.' end
        local offset = cleanVec(entry.offset, 500.0)
        if not offset then return nil, 'Every prop needs an offset.' end
        local heading = entry.heading == nil and 0.0 or inRange(entry.heading, -720.0, 720.0)
        if not heading then return nil, 'Invalid prop heading.' end

        local listId = nil
        if entry.list ~= nil then
            if not (validId(entry.list) and Lists[entry.list]) then return nil, 'Unknown item list.' end
            listId = entry.list
        end

        clean[#clean + 1] = { model = model, offset = offset, heading = heading, list = listId, label = trim(entry.label, 48) }
    end
    return clean
end

-- A shell's exit: where the exit target sits, relative to the shell.
function cleanExit(value)
    local offset = cleanVec(value, 500.0)
    if not offset then return nil, 'The exit needs a position.' end
    return offset
end

-- A world position with a heading, for a house entrance.
function cleanEntrance(value)
    local coords = cleanVec(value)
    if not coords then return nil, 'The house needs a position.' end
    coords.w = value.w == nil and 0.0 or inRange(value.w, -720.0, 720.0)
    if not coords.w then return nil, 'Invalid heading.' end
    return coords
end

function newHouse(label, shell, coords)
    local defaults = Config.Robberies.House.defaults
    return {
        label = label,
        shell = shell,
        coords = coords,
        minPolice = defaults.minPolice or 0,
        cooldown = math.floor((defaults.cooldown or 0) / 60000), -- minutes
        hours = nil, -- { from, to } or nil for any time
        security = false,
    }
end

-- The settings form of a house.
function cleanHouseDetails(input, current)
    if type(input) ~= 'table' then return nil, 'Invalid data.' end
    local house = copyTable(current)

    local label = trim(input.label, 48)
    if not label then return nil, 'Enter a name for the house.' end
    house.label = label

    house.minPolice = inRange(input.minPolice, 0, 100, true)
    if not house.minPolice then return nil, 'Minimum police must be between 0 and 100.' end
    house.cooldown = inRange(input.cooldown, 0, 1440, true)
    if not house.cooldown then return nil, 'Cooldown must be between 0 and 1440 minutes.' end
    house.security = input.security == true

    if input.timeLimit == true then
        local from, to = inRange(input.timeFrom, 0, 23, true), inRange(input.timeTo, 0, 23, true)
        if not (from and to) then return nil, 'Hours must be between 0 and 23.' end
        house.hours = { from = from, to = to }
    else
        house.hours = nil
    end
    return house
end

-- Readers for rows from the database: a bad row is repaired where it can be, never trusted.
function readList(id, raw)
    local stored = decodeJson(raw, {})
    local items = cleanItems(type(stored.items) == 'table' and stored.items or {}, stored.items)
    return { label = trim(stored.label, 48) or id, items = items or {} }
end

function readSetup(raw)
    local stored = decodeJson(raw, {})
    local props = {}
    for _, entry in ipairs(type(stored.props) == 'table' and stored.props or {}) do
        if type(entry) == 'table' and not (validId(entry.list) and Lists[entry.list]) then entry.list = nil end -- its list was deleted
        local clean = cleanProps({ entry })
        if clean and clean[1] then props[#props + 1] = clean[1] end
    end
    return { exit = cleanVec(stored.exit, 500.0), props = props }
end

function readHouse(id, raw)
    local stored = decodeJson(raw, {})
    local coords = cleanEntrance(stored.coords)
    if not (coords and type(stored.shell) == 'string') then return nil end

    local house = cleanHouseDetails({
        label = stored.label or id, minPolice = stored.minPolice or 0, cooldown = stored.cooldown or 0,
        security = stored.security, timeLimit = type(stored.hours) == 'table',
        timeFrom = type(stored.hours) == 'table' and stored.hours.from, timeTo = type(stored.hours) == 'table' and stored.hours.to,
    }, { shell = stored.shell, coords = coords })
    return house
end
