
local patterns = {
    name = '^[%w_%-%.]+$', -- items and props
    anim = '^[%w_@%-%.]+$', -- animation dictionaries and clips
}

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

function cleanSearch(entry)
    local time = DefaultSearch.time
    if entry.time ~= nil then
        time = inRange(entry.time, 500, 300000, true)
        if not time then return nil, 'Search time must be between 500 and 300000 ms.' end
    end

    local anim
    if entry.anim == nil then
        anim = copyTable(DefaultSearch.anim)
    elseif type(entry.anim) == 'table' then
        local dict = cleanName(entry.anim.dict, 64, patterns.anim)
        local clip = cleanName(entry.anim.clip, 64, patterns.anim)
        if dict == false then return nil, 'Enter a valid animation dictionary.' end
        if clip == false then return nil, 'Enter a valid animation clip.' end
        if (dict == nil) ~= (clip == nil) then return nil, 'An animation needs both a dictionary and a clip.' end
        if dict then
            anim = { dict = dict, clip = clip, flag = inRange(entry.anim.flag, 0, 65535, true) or DefaultSearch.anim.flag }
        else
            anim = false
        end
    elseif entry.anim == false then
        anim = false
    else
        return nil, 'Invalid animation.'
    end

    local disable
    if entry.disable == nil then
        disable = copyTable(DefaultSearch.disable)
    elseif type(entry.disable) == 'table' then
        disable = {}
        for _, option in ipairs(ProgressDisableOptions) do
            local on = entry.disable[option.value] == true
            if not on then for _, key in ipairs(entry.disable) do if key == option.value then on = true end end end
            if on then disable[option.value] = true end
        end
    else
        return nil, 'Invalid list of disabled controls.'
    end
    return time, anim, disable
end

function cleanProps(list)
    if type(list) ~= 'table' then return nil, 'Invalid prop list.' end

    local clean = {}
    for _, entry in ipairs(list) do
        if #clean >= Limits.props then return nil, ('A shell can have %d props at most.'):format(Limits.props) end
        if type(entry) ~= 'table' then return nil, 'Invalid prop.' end

        -- No model means a box target at that spot instead of a prop.
        local model = cleanName(entry.model, 64, patterns.name)
        if model == false then return nil, 'Enter a valid prop model, or leave it empty for a box target.' end
        local offset = cleanVec(entry.offset, 500.0)
        if not offset then return nil, 'Every prop needs an offset.' end
        local heading = entry.heading == nil and 0.0 or inRange(entry.heading, -720.0, 720.0)
        if not heading then return nil, 'Invalid prop heading.' end

        local listId = nil
        if entry.list ~= nil then
            if not (validId(entry.list) and Lists[entry.list]) then return nil, 'Unknown item list.' end
            listId = entry.list
        end

        local time, anim, disable = cleanSearch(entry)
        if not time then return nil, anim end

        clean[#clean + 1] = {
            model = model, offset = offset, heading = heading, list = listId, label = trim(entry.label, 48),
            time = time, anim = anim, disable = disable,
            progressLabel = trim(entry.progressLabel, 48) or DefaultSearch.progressLabel,
        }
    end
    return clean
end

function cleanExit(value)
    local offset = cleanVec(value, 500.0)
    if not offset then return nil, 'The exit needs a position.' end
    return offset
end

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

    for _, key in ipairs({ 'breakItem', 'securityItem' }) do
        local item = cleanName(input[key], 64, patterns.name)
        if item == false then return nil, 'Invalid item name.' end
        if item and not itemExists(item) then return nil, ('%s does not exist.'):format(item) end
        house[key] = item
    end

    if input.lowerZ == nil then
        house.lowerZ = nil
    else
        house.lowerZ = inRange(input.lowerZ, -300.0, 0.0)
        if not house.lowerZ then return nil, 'Shell depth must be between -300 and 0.' end
    end

    if input.timeLimit == true then
        local from, to = inRange(input.timeFrom, 0, 23, true), inRange(input.timeTo, 0, 23, true)
        if not (from and to) then return nil, 'Hours must be between 0 and 23.' end
        house.hours = { from = from, to = to }
    else
        house.hours = nil
    end
    return house
end

function readList(id, raw)
    local stored = decodeJson(raw, {})
    local items = cleanItems(type(stored.items) == 'table' and stored.items or {}, stored.items)
    return { label = trim(stored.label, 48) or id, items = items or {} }
end

function cleanBreakItem(value)
    local item = cleanName(value, 64, patterns.name)
    if item == false then return nil, 'Invalid item name.' end
    if item and not itemExists(item) then return nil, ('%s does not exist.'):format(item) end
    return item
end

function readSetup(raw)
    local stored = decodeJson(raw, {})
    local props = {}
    for _, entry in ipairs(type(stored.props) == 'table' and stored.props or {}) do
        if type(entry) == 'table' and not (validId(entry.list) and Lists[entry.list]) then entry.list = nil end -- its list was deleted
        local clean = cleanProps({ entry })
        if clean and clean[1] then props[#props + 1] = clean[1] end
    end
    return { exit = cleanVec(stored.exit, 500.0), props = props, breakItem = cleanName(stored.breakItem, 64, patterns.name) or nil }
end

function readHouse(id, raw)
    local stored = decodeJson(raw, {})
    local coords = cleanEntrance(stored.coords)
    if not (coords and type(stored.shell) == 'string') then return nil end

    local house = cleanHouseDetails({
        label = stored.label or id, minPolice = stored.minPolice or 0, cooldown = stored.cooldown or 0,
        security = stored.security, breakItem = stored.breakItem, securityItem = stored.securityItem, lowerZ = stored.lowerZ,
        timeLimit = type(stored.hours) == 'table',
        timeFrom = type(stored.hours) == 'table' and stored.hours.from, timeTo = type(stored.hours) == 'table' and stored.hours.to,
    }, { shell = stored.shell, coords = coords })
    return house
end

function newStore(label)
    return { label = label, minPolice = Config.Robberies.Store.defaults.minPolice or 0, registers = {}, safes = {} }
end

function cleanStoreDetails(input, current)
    if type(input) ~= 'table' then return nil, 'Invalid data.' end
    local store = copyTable(current)

    local label = trim(input.label, 48)
    if not label then return nil, 'Enter a name for the store.' end
    store.label = label

    store.minPolice = inRange(input.minPolice, 0, 100, true)
    if not store.minPolice then return nil, 'Minimum police must be between 0 and 100.' end
    return store
end

-- Registers: { coords, stickyChance, label, progressLabel, time, anim, disable }. Each has its own search settings
-- (same as a prop) and its own chance of giving the safe code.
function cleanRegisters(list)
    if type(list) ~= 'table' then return nil, 'Invalid register list.' end

    local clean = {}
    for _, entry in ipairs(list) do
        if #clean >= Limits.registers then return nil, ('A store can have %d registers at most.'):format(Limits.registers) end
        if type(entry) ~= 'table' then return nil, 'Invalid register.' end

        local coords = cleanVec(entry.coords)
        if not coords then return nil, 'Every register needs a position.' end

        local time, anim, disable = cleanSearch(entry)
        if not time then return nil, anim end

        local chance = entry.stickyChance == nil and Config.Robberies.Store.defaults.stickyNoteChance or inRange(entry.stickyChance, 0, 100, true)
        if not chance then return nil, 'Sticky note chance must be between 0 and 100.' end

        clean[#clean + 1] = {
            coords = coords, stickyChance = chance, label = trim(entry.label, 48),
            progressLabel = trim(entry.progressLabel, 48) or 'Robbing Register...',
            time = time, anim = anim, disable = disable,
        }
    end
    return clean
end

-- Safes: { coords } with a heading.
function cleanSafes(list)
    if type(list) ~= 'table' then return nil, 'Invalid safe list.' end

    local clean = {}
    for _, entry in ipairs(list) do
        if #clean >= Limits.safes then return nil, ('A store can have %d safes at most.'):format(Limits.safes) end
        local coords = type(entry) == 'table' and cleanVec(entry.coords)
        local heading = coords and (entry.coords.w == nil and 0.0 or inRange(entry.coords.w, -720.0, 720.0))
        if not (coords and heading) then return nil, 'Every safe needs a position.' end
        coords.w = heading
        clean[#clean + 1] = { coords = coords }
    end
    return clean
end

function readStore(id, raw)
    local stored = decodeJson(raw, {})
    local store = cleanStoreDetails({
        label = stored.label or id,
        minPolice = stored.minPolice or Config.Robberies.Store.defaults.minPolice or 0,
    }, { registers = {}, safes = {} })
    if not store then return nil end

    -- a bad entry is skipped, never trusted
    for _, entry in ipairs(type(stored.registers) == 'table' and stored.registers or {}) do
        local clean = cleanRegisters({ entry })
        if clean and clean[1] then store.registers[#store.registers + 1] = clean[1] end
    end
    for _, entry in ipairs(type(stored.safes) == 'table' and stored.safes or {}) do
        local clean = cleanSafes({ entry })
        if clean and clean[1] then store.safes[#store.safes + 1] = clean[1] end
    end
    return store
end