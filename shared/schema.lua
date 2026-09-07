-- One JSON-safe schema is used for database rows, AppShell mutations and client
-- world construction. Definitions never contain vectors, native handles, or
-- callable values, so they can safely be replicated to every client.
QbRobberies = QbRobberies or {}
local S = {}
QbRobberies.schema = S

local function text(value, limit)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    return value ~= '' and value:sub(1, limit or 128) or nil
end

local function number(value, low, high)
    local result = tonumber(value)
    if not result or result ~= result or result == math.huge or result == -math.huge then return nil end
    if low and result < low then return nil end
    if high and result > high then return nil end
    return result + 0.0
end

local function integer(value, low, high)
    local result = number(value, low, high)
    return result and math.floor(result) or nil
end

local function coords(value)
    if type(value) ~= 'table' then return nil end
    local x = number(value.x or value[1], -10000, 10000)
    local y = number(value.y or value[2], -10000, 10000)
    local z = number(value.z or value[3], -2000, 3000)
    if not x or not y or not z then return nil end
    return { x = x, y = y, z = z, w = number(value.w or value.heading or value[4]) or 0.0 }
end

local function slug(value)
    value = text(value, 64)
    if not value then return nil end
    value = value:lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
    return value ~= '' and value:sub(1, 64) or nil
end

local games = { lockpick = true, skillbar = true, circuit = true, hacking = true }
local stepKinds = { hack = true, search = true, drill = true }

S.text, S.number, S.integer, S.coords, S.slug = text, number, integer, coords, slug

function S.normaliseReward(raw)
    if type(raw) ~= 'table' then return nil, 'Invalid reward.' end
    local kind = raw.kind == 'money' and 'money' or raw.kind == 'item' and 'item' or nil
    if not kind then return nil, 'A reward must be an item or money.' end
    local name
    if kind == 'money' then
        name = raw.name == 'cash' and 'cash' or raw.name == 'bank' and 'bank' or nil
    else
        name = text(raw.name, 64)
    end
    local min = integer(raw.min, 1, 1000000)
    local max = integer(raw.max, min, 1000000)
    local chance = number(raw.chance, 0.01, 100)
    if not name or not min or not max or not chance then return nil, 'Reward values are out of range.' end
    return { kind = kind, name = name, min = min, max = max, chance = chance }
end

local function normaliseGame(raw, kind)
    if raw == nil and kind == 'search' then return nil end
    raw = type(raw) == 'table' and raw or {}
    local gameType = games[raw.type] and raw.type or (kind == 'drill' and 'skillbar' or 'hacking')
    local source = type(raw.opts) == 'table' and raw.opts or {}
    local opts

    if gameType == 'hacking' then
        opts = {
            solutionsize = integer(source.solutionsize, 2, 10) or 5,
            timeout = number(source.timeout, 5, 120) or 30,
        }
    elseif gameType == 'lockpick' then
        opts = {
            attempts = integer(source.attempts, 1, 8) or 2,
            pinCount = integer(source.pinCount, 1, 12) or 4,
            tolerance = number(source.tolerance, 0.03, 0.35) or 0.16,
            speed = number(source.speed, 0.3, 4.0) or 1.0,
            timeLimit = integer(source.timeLimit, 2000, 60000) or 15000,
        }
    elseif gameType == 'skillbar' then
        opts = {
            attempts = integer(source.attempts, 1, 8) or 2,
            zoneSize = number(source.zoneSize, 0.05, 0.6) or 0.18,
            speed = number(source.speed, 0.3, 4.0) or 1.2,
            timeLimit = integer(source.timeLimit, 1500, 30000) or 10000,
        }
    else
        opts = {
            attempts = integer(source.attempts, 1, 8) or 2,
            nodeCount = integer(source.nodeCount, 2, 8) or 4,
            timeLimit = integer(source.timeLimit, 3000, 60000) or 20000,
        }
    end
    return { type = gameType, opts = opts }
end

function S.normaliseStep(raw)
    if type(raw) ~= 'table' then return nil, 'Invalid robbery step.' end
    local kind = stepKinds[raw.kind] and raw.kind or nil
    local label = text(raw.label, 80)
    local position = coords(raw.coords)
    local radius = number(raw.radius, 0.4, 8.0) or 1.2
    local duration = integer(raw.duration, 1000, 120000) or 7000
    if not kind or not label or not position then return nil, 'Every step needs a type, label, and position.' end
    local out = { kind = kind, label = label, coords = position, radius = radius, duration = duration, rewards = {}, unlockDoors = {} }
    out.game = normaliseGame(raw.game, kind)
    for index, reward in ipairs(type(raw.rewards) == 'table' and raw.rewards or {}) do
        if index > 12 then return nil, 'A step can have at most 12 rewards.' end
        local normalised, err = S.normaliseReward(reward)
        if not normalised then return nil, err end
        out.rewards[#out.rewards + 1] = normalised
    end
    for index, doorId in ipairs(type(raw.unlockDoors) == 'table' and raw.unlockDoors or {}) do
        if index > 12 then return nil, 'A step can unlock at most 12 doors.' end
        doorId = text(doorId, 96)
        if not doorId then return nil, 'Door IDs must be text.' end
        out.unlockDoors[#out.unlockDoors + 1] = doorId
    end
    return out
end

function S.normalise(raw)
    if type(raw) ~= 'table' then return nil, 'Invalid robbery.' end
    local id = slug(raw.id)
    local label = text(raw.label, 128)
    local start = coords(raw.start)
    if not id or not label or not start then return nil, 'A robbery needs an id, label, and start location.' end
    local out = {
        id = id, label = label, enabled = raw.enabled ~= false, startSet = raw.startSet ~= false, start = start,
        startRadius = number(raw.startRadius, 0.5, 15.0) or 2.0,
        cooldown = integer(raw.cooldown, 0, 7 * 24 * 60 * 60) or Config.Robberies.defaultCooldown,
        minPolice = integer(raw.minPolice, 0, 64) or Config.Robberies.defaultMinPolice,
        steps = {}, props = {}, startDoors = {},
    }
    for index, step in ipairs(type(raw.steps) == 'table' and raw.steps or {}) do
        if index > Config.Robberies.maxSteps then return nil, 'Too many robbery steps.' end
        local normalised, err = S.normaliseStep(step)
        if not normalised then return nil, err end
        out.steps[#out.steps + 1] = normalised
    end
    for index, prop in ipairs(type(raw.props) == 'table' and raw.props or {}) do
        if index > Config.Robberies.maxProps then return nil, 'Too many local props.' end
        local model, position = text(prop.model, 96), coords(prop.coords)
        if not model or not position then return nil, 'Props need a model and position.' end
        out.props[#out.props + 1] = { model = model, coords = position }
    end
    for index, doorId in ipairs(type(raw.startDoors) == 'table' and raw.startDoors or {}) do
        if index > 12 then return nil, 'Too many start doors.' end
        doorId = text(doorId, 96)
        if not doorId then return nil, 'Door IDs must be text.' end
        out.startDoors[#out.startDoors + 1] = doorId
    end
    return out
end
