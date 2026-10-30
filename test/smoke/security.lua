local H = dofile('test/harness.lua')

local function read(path)
    local file = assert(io.open(path, 'r'), 'missing ' .. path)
    local value = file:read('*a'); file:close()
    return value
end

local server = read('server/main.lua')
local state = read('server/state.lua')
local client = read('client/world.lua')
local manifest = read('fxmanifest.lua')

H.ok(manifest:find("dependency 'kora_doorlock'", 1, true), 'qbdoorlock is mandatory')
H.ok(manifest:find("dependency 'kora_sql'", 1, true), 'definitions are durable')
H.ok(server:find('State.isAdmin(source)', 1, true), 'creator mutations require an admin')
H.ok(server:find('State.at(source, step.coords', 1, true), 'step completion is distance checked server-side')
H.ok(server:find('QB.minigames.consumeProof', 1, true), 'minigame proof is consumed on the server')
H.ok(state:find('State.restoreDoors(session)', 1, true), 'door state is restored when a session stops')
H.ok(state:find('exports.kora_doorlock:setDoorState', 1, true), 'doors are changed through qbdoorlock')
H.ok(client:find('QB.entities.create', 1, true), 'decorative props use kora_lib entities')
H.ok(client:find('non-networked', 1, true), 'strict-lockdown local entity rule is documented at the spawn')
H.ok(not client:find('CreateObject', 1, true) and not client:find('CreatePed', 1, true), 'client never directly creates entities')

local declared = select(2, server:gsub("QB%.callback%.register%('qbrobberies:server:", ''))
local limited = select(2, server:gsub('rateLimit = {', ''))
H.equal(limited, declared, 'every client callback is rate limited')
H.finish('security')
