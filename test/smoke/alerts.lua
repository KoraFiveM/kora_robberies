-- Dispatch alerts for house break-ins and store register/safe robberies (F#126).
-- Run from the resource directory: lua test/smoke/alerts.lua
local h = dofile('../kora_lib/test/harness.lua')
local mocks = dofile('../kora_lib/test/mocks.lua')
local net = mocks.install()

local calls, removed, adopted = {}, {}, 0
local dispatchResult = function(payload) return #calls, 1 end
local callbacks, warnings, player = {}, {}, 1

_G.vector3 = function(x, y, z) return { x = x, y = y, z = z } end
_G.vec3 = _G.vector3
_G.json = { encode = function() return '{}' end, decode = function() return {} end }
_G.GetPlayers = function() return { '1' } end
_G.GetResourceState = function() return 'started' end
_G.IsPlayerAceAllowed = function() return false end
-- The real kora_lib config bridge, so config.lua is validated the way the server will load it.
_G.IsDuplicityVersion = function() return true end
_G.LoadResourceFile = function() return nil end
_G.SaveResourceFile = function() return true end
local bridge = dofile('../kora_lib/modules/config/consumer.lua')({ config_register = function() return true end })
_G.Kora = { config = setmetatable({ adopt = function(config, options) adopted = adopted + 1; return bridge.adopt(config, options) end },
    { __index = bridge }) }
_G.QB = {
    callback = { register = function(name, fn) callbacks[name] = fn end },
    notify = { send = function() end },
    print = { warn = function(message) warnings[#warnings + 1] = message end },
    distance = { player = function() return true end },
    sql = { query = function() return {} end, update = function() return true end },
}
_G.exports = setmetatable({
    kora_core = { getPlayer = function() return { PlayerData = { job = { name = 'police', onduty = true } } } end, getShared = function() return {} end },
    kora_dispatch = { createCall = function(_, payload) return dispatchResult(payload) end },
    kora_interior = {},
    ['qb-inventory'] = {
        HasItem = function() return true end, RemoveItem = function(_, _, item) removed[#removed + 1] = item; return true end,
        AddItem = function() return true end,
    },
    ['qb-core'] = { GetShared = function() return {} end },
}, {})

dofile('config.lua')
dofile('shared/constants.lua')
dofile('shared/shells.lua')
dofile('server/_functions.lua')
dofile('server/rules.lua')
dofile('server/data.lua')
dofile('server/alerts.lua')
dofile('server/robbery.lua')
dofile('server/store.lua')

Setups.small = { exit = { x = 0, y = 0, z = 0 }, props = {} }
Houses.sec = { label = 'Secure Villa', shell = 'small', coords = { x = 10.0, y = 20.0, z = 30.0 }, minPolice = 0, cooldown = 1, security = true }
Houses.plain = { label = 'Plain House', shell = 'small', coords = { x = 11.0, y = 21.0, z = 31.0 }, minPolice = 0, cooldown = 1, security = false }
Stores.mart = {
    label = 'Mart', minPolice = 0,
    registers = {
        { coords = { x = 1.0, y = 2.0, z = 3.0 }, time = 5000, stickyChance = 0 },
        { coords = { x = 1.5, y = 2.5, z = 3.0 }, time = 5000, stickyChance = 0 },
    },
    safes = { { coords = { x = 4.0, y = 5.0, z = 6.0, w = 0.0 } } },
}
Stores.shop = { label = 'Shop', minPolice = 0, registers = { { coords = { x = 50.0, y = 60.0, z = 7.0 }, time = 5000, stickyChance = 0 } }, safes = {} }

local function reset()
    calls = {}
    dispatchResult = function(payload) calls[#calls + 1] = payload; return #calls, 1 end
    Config.alerts.dispatch.enabled = true
    Config.stores.enabled = true
end
local function advance(ms) for _ = 1, math.ceil(ms / 16) do Wait(16) end end
local function cb(name, ...) player = player + 1; return callbacks[name](player, ...) end

h.test('config is handed to Kora.config.adopt and shells keep their spawn functions', function()
    h.assertEqual(adopted, 1, 'adopt called once')
    h.assertTrue(type(Config.Robberies.House.shells[1].spawn) == 'function', 'spawn kept')
end)

h.test('defaults: alerts and stores on, codes set', function()
    h.assertEqual(Config.stores.enabled, true)
    h.assertEqual(Config.alerts.dispatch.enabled, true)
    h.assertTrue(type(Config.alerts.dispatch.storeCode) == 'string')
    h.assertTrue(type(Config.alerts.dispatch.houseCode) == 'string')
end)

h.test('a security-house break-in alerts police and still raises qbrobberies:houseAlert', function()
    reset()
    local seen
    AddEventHandler('qbrobberies:houseAlert', function(info) seen = info end)
    local info = cb('qbrobberies:breakin', 'sec')
    h.assertTrue(type(info) == 'table', 'break-in allowed')
    h.assertEqual(seen and seen.house, 'sec', 'legacy event kept')
    h.assertEqual(#calls, 1, 'one dispatch call')
    h.assertEqual(calls[1].jobTypes[1], 'leo')
    h.assertEqual(calls[1].code, Config.alerts.dispatch.houseCode)
    h.assertEqual(calls[1].coords.x, 10.0)
    h.assertTrue(calls[1].message:find('Secure Villa', 1, true) ~= nil, 'label in message')
end)

h.test('a house without security raises no alert', function()
    reset()
    cb('qbrobberies:breakin', 'plain')
    h.assertEqual(#calls, 0)
end)

h.test('joining an already open house does not alert again', function()
    reset()
    cb('qbrobberies:breakin', 'sec')
    h.assertEqual(#calls, 0)
end)

h.test('a register robbery alerts police at the register', function()
    reset()
    local started = cb('qbrobberies:register:begin', 'mart', 1)
    h.assertTrue(type(started) == 'table', 'register begins')
    h.assertEqual(#calls, 1)
    h.assertEqual(calls[1].code, Config.alerts.dispatch.storeCode)
    h.assertEqual(calls[1].coords.x, 1.0)
    h.assertTrue(calls[1].message:find('Mart', 1, true) ~= nil, 'store label in message')
end)

h.test('alerts are throttled per store but not across stores', function()
    reset()
    advance(500)
    cb('qbrobberies:register:begin', 'mart', 2)
    h.assertEqual(#calls, 0, 'second register of the same store inside the cooldown')
    cb('qbrobberies:register:begin', 'shop', 1)
    h.assertEqual(#calls, 1, 'other store alerts')
    advance(Config.alerts.dispatch.cooldown + 1000)
    cb('qbrobberies:safe:blow', 'mart', 1)
    h.assertEqual(#calls, 2, 'safe blow alerts after the cooldown')
    h.assertEqual(calls[2].coords.x, 4.0, 'safe position')
end)

h.test('a disabled dispatch alert setting stops alerts but not the robbery', function()
    reset()
    Config.alerts.dispatch.enabled = false
    advance(Config.alerts.dispatch.cooldown + 1000)
    local started = cb('qbrobberies:register:begin', 'shop', 1)
    h.assertEqual(#calls, 0)
    h.assertTrue(type(started) == 'table', 'the robbery itself still starts')
end)

h.test('a failing or missing dispatch never breaks the robbery', function()
    reset()
    advance(Config.alerts.dispatch.cooldown + 1000)
    dispatchResult = function() error('kora_dispatch is not running') end
    Houses.plain.security = true
    local ok, info = pcall(cb, 'qbrobberies:breakin', 'plain')
    h.assertTrue(ok and type(info) == 'table', 'house break-in still works')
    dispatchResult = function() return false, 'not allowed' end
    local ok2 = pcall(cb, 'qbrobberies:register:begin', 'shop', 1)
    h.assertTrue(ok2, 'store robbery still works')
end)

h.test('stores.enabled = false refuses register robberies and hides stores', function()
    reset()
    advance(Config.alerts.dispatch.cooldown + 1000)
    Config.stores.enabled = false
    DataLoaded = true
    local list = cb('qbrobberies:stores')
    h.assertEqual(#list, 0, 'no stores sent to clients')
    local started, err = cb('qbrobberies:register:begin', 'mart', 1)
    h.assertFalse(started, 'register refused')
    h.assertTrue(type(err) == 'string')
    h.assertEqual(#calls, 0)
end)

h.test('the store seed is idempotent and covers every store', function()
    local f = assert(io.open('sql/stores_seed.sql', 'r'))
    local sql = f:read('a'); f:close()
    h.assertTrue(sql:find('INSERT IGNORE INTO `qbrobberies_stores`', 1, true) ~= nil, 'INSERT IGNORE')
    h.assertTrue(sql:find('CREATE TABLE IF NOT EXISTS `qbrobberies_stores`', 1, true) ~= nil, 'table guard')
    local n = 0
    for _ in sql:gmatch("\n\t%('24_7[%w_]*', ") do n = n + 1 end
    h.assertEqual(n, 19, 'all 19 storerobbery stores')
    h.assertFalse(sql:find('ON DUPLICATE KEY UPDATE', 1, true), 'never overwrites creator edits')
end)

h.report('kora_robberies alerts')
