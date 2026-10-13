-- The only file that knows what a spawned shell looks like. config.lua's spawn(coords) returns
-- { id = shell, exit = exit }: id[1] is the shell entity (client/main.lua's /shellExit relies on that too).
-- If your interior resource returns something else, adjust these four functions and nothing else.

-- Anything that is an entity handle, a vector or { x, y, z } becomes a vector3, or nil.
local function toCoords(value)
    if type(value) == 'number' then
        return DoesEntityExist(value) and GetEntityCoords(value) or nil
    end
    if value == nil then return nil end
    local ok, x, y, z = pcall(function() return value.x, value.y, value.z end)
    if ok and tonumber(x) and tonumber(y) and tonumber(z) then return vector3(x + 0.0, y + 0.0, z + 0.0) end
end

-- Spawns the shell below `coords`. Returns { ids, shell, exit } or nil and a message.
function SpawnShell(def, coords)
    local ok, result = pcall(def.spawn, coords)
    if not ok or type(result) ~= 'table' or not result.id then
        return nil, 'The shell could not be spawned.'
    end

    local ids = result.id
    local shell = type(ids) == 'table' and ids[1] or ids
    if type(shell) ~= 'number' or not DoesEntityExist(shell) then
        return nil, 'The shell did not spawn.'
    end
    return { ids = ids, shell = shell, exit = result.exit }
end

-- Where to put a player who is entering the shell: its exit if it gave one, else the shell itself.
function ShellEntryCoords(spawned)
    return toCoords(spawned.exit)
        or (type(spawned.ids) == 'table' and toCoords(spawned.ids[2]))
        or GetEntityCoords(spawned.shell)
end

function RemoveShell(spawned)
    local ids = type(spawned.ids) == 'table' and spawned.ids or { spawned.ids }
    for _, entity in pairs(ids) do
        if type(entity) == 'number' and DoesEntityExist(entity) then DeleteEntity(entity) end
    end
end

-- A world position and heading as an offset and heading relative to the shell, and back.
function ToShellOffset(spawned, coords, heading)
    local offset = GetOffsetFromEntityGivenWorldCoords(spawned.shell, coords.x, coords.y, coords.z)
    return { x = offset.x, y = offset.y, z = offset.z }, (heading - GetEntityHeading(spawned.shell)) % 360.0
end

function FromShellOffset(spawned, offset, heading)
    local world = GetOffsetFromEntityInWorldCoords(spawned.shell, offset.x, offset.y, offset.z)
    return world, (GetEntityHeading(spawned.shell) + (heading or 0.0)) % 360.0
end
