-- Optional FFT development hooks (server). Listed last in fxmanifest.lua and
-- inert unless `setr fft_kora_hooks true`.
--
-- Uses the RobberyFFT seam at the end of server/robbery.lua (the approved house
-- state reset seam) so house scenarios are repeatable: without it a break-in
-- leaves the house open for 15 minutes and then on cooldown.
if GetConvar('fft_kora_hooks', 'false') ~= 'true' then return end

local RUNNER = 'fft'
local VERSION = 1
local seam = RobberyFFT
if type(seam) ~= 'table' then return end

local claimed = {} -- house id -> tester source that may reset it

local function tester(src)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return nil end
    return type(Player(src).state.fftSession) == 'string' and src or nil
end

local function point(coords)
    if type(coords) ~= 'table' and type(coords) ~= 'vector3' and type(coords) ~= 'vector4' then return nil end
    return { x = tonumber(coords.x), y = tonumber(coords.y), z = tonumber(coords.z) }
end

local function houseOf(id)
    if not DataLoaded then return nil, 'Robbery data is not loaded yet', 'blocked' end
    local house = type(id) == 'string' and validId(id) and Houses[id]
    if not house then return nil, 'Unknown house: ' .. tostring(id), 'invalid' end
    return house
end

local function others(id, src)
    local session, count = seam.Sessions[id], 0
    for player in pairs(session and session.players or {}) do
        if player ~= src then count = count + 1 end
    end
    return count
end

local function reset(src, id)
    if claimed[id] ~= src then return false, 'This tester did not claim the house', 'rejected' end
    if others(id, src) > 0 then return false, 'Another player is inside the house', 'blocked' end
    claimed[id] = nil
    local session = seam.Sessions[id]
    seam.Sessions[id] = nil
    if session and session.players[src] and GetPlayerName(src) then
        TriggerClientEvent('kora_robberies:client:closed', src, id)
    end
    if seam.States[id] then seam.setState(id, nil) end
    return true
end

local actions = {}

-- Read-only summary of one house as the server currently holds it.
function actions.house(src, id)
    local house, err, code = houseOf(id)
    if not house then return false, err, code end
    local setup = Setups[house.shell]
    local entry, session = seam.States[id], seam.Sessions[id]
    local defaults = Config.Robberies.House.defaults
    return {
        id = id, coords = point(house.coords), minPolice = house.minPolice, security = house.security == true,
        timeLimited = house.hours ~= nil, cooldownMinutes = house.cooldown, hasExit = setup ~= nil and setup.exit ~= nil,
        breakItem = house.breakItem or (setup and setup.breakItem) or defaults.breakItem,
        consumeBreakItem = defaults.consumeBreakItem == true, breakTime = defaults.breakTime,
        state = entry and entry.state or 'available',
        testerInside = session ~= nil and session.players[src] == true, otherPlayers = others(id, src),
        claimed = claimed[id] == src, police = PoliceOnDuty(),
    }
end

-- Read-only summary of one store.
function actions.store(_, id)
    if not DataLoaded then return false, 'Robbery data is not loaded yet', 'blocked' end
    local store = type(id) == 'string' and validId(id) and Stores[id]
    if not store then return false, 'Unknown store: ' .. tostring(id), 'invalid' end
    local registers, safes = {}, {}
    for index, register in ipairs(store.registers or {}) do
        if index > 20 then break end
        local at = point(register.coords) or {}
        registers[index] = { x = at.x, y = at.y, z = at.z, label = register.label or 'Rob Register' }
    end
    for index, safe in ipairs(store.safes or {}) do
        if index > 20 then break end
        safes[index] = point(safe.coords) or {}
    end
    return { id = id, minPolice = store.minPolice, registers = registers, safes = safes, police = PoliceOnDuty() }
end

-- Marks an untouched house as this tester's, so only state the test creates is
-- ever reset. A house that is open or on cooldown from real play is refused.
function actions.claim(src, id)
    local house, err, code = houseOf(id)
    if not house then return false, err, code end
    if claimed[id] and claimed[id] ~= src then return false, 'Another tester holds this house', 'blocked' end
    if seam.States[id] or others(id, src) > 0 then return false, 'The house is in use (open or on cooldown)', 'blocked' end
    claimed[id] = src
    return true
end

-- Puts a claimed, untouched house on a short cooldown (the state a finished
-- robbery leaves behind), through the resource's own setState broadcast.
function actions.cooldown(src, id, seconds)
    local house, err, code = houseOf(id)
    if not house then return false, err, code end
    if claimed[id] ~= src then return false, 'This tester did not claim the house', 'rejected' end
    if seam.States[id] then return false, 'The house already has a state', 'blocked' end
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds < 30 or seconds > 300 then return false, 'Cooldown must be 30-300 seconds', 'invalid' end
    seam.setState(id, 'cooldown', seconds)
    return true
end

-- Returns a claimed house to "available" and sends the tester out if inside.
function actions.reset(src, id)
    if type(id) ~= 'string' or not validId(id) then return false, 'Invalid house id', 'invalid' end
    return reset(src, id)
end

AddEventHandler('playerDropped', function()
    local src = source
    for id, holder in pairs(claimed) do
        if holder == src then reset(src, id) end
    end
end)

exports('fftVersion', function() return VERSION end)
exports('fftAction', function(action, src, ...)
    if GetInvokingResource() ~= RUNNER then return false, 'FFT hooks are disabled or session is not authorised' end
    src = tester(src)
    if not src then return false, 'FFT hooks are disabled or session is not authorised' end
    local handler = actions[action]
    if not handler then return false, 'Unsupported FFT action: ' .. tostring(action) end
    return handler(src, ...)
end)
