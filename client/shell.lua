local function toCoords(value)
    if type(value) == 'number' then
        return DoesEntityExist(value) and GetEntityCoords(value) or nil
    end
    if value == nil then return nil end
    local ok, x, y, z = pcall(function() return value.x, value.y, value.z end)
    if ok and tonumber(x) and tonumber(y) and tonumber(z) then return vector3(x + 0.0, y + 0.0, z + 0.0) end
end

function SpawnShell(def, coords)
    local ok, result = pcall(def.spawn, coords)
    if not ok or type(result) ~= 'table' or not result.id then
        return nil, 'The shell could not be spawned.'
    end

    local ids = result.id

    while type(handle) == 'table' do handle = handle[1] end
    if type(handle) ~= 'number' then
        QB.print.warn(('[qbrobberies] %s returned no shell handle: %s'):format(tostring(def.label), json.encode(ids)))
        return nil, 'The shell did not spawn.'
    end

    local shell, waited = nil, 0
    while waited <= 1500 do
        if DoesEntityExist(handle) then shell = handle break end
        Wait(100)
        waited = waited + 100
    end

    if shell then
        waited = 0
        while #(GetEntityCoords(shell) - coords) > 100.0 and waited < 5000 do
            Wait(100)
            waited = waited + 100
        end
        if #(GetEntityCoords(shell) - coords) > 100.0 then
            QB.print.warn(('[qbrobberies] the shell is %.0f units from where it was spawned; props will be placed wrong. Check client/shell.lua.'):format(#(GetEntityCoords(shell) - coords)))
        end
    else
        QB.print.warn(('[qbrobberies] %s: handle %s is not an entity on this client, so the spawn coordinates are used as the shell origin.'):format(
            tostring(def.label), tostring(handle)))
    end

    local poi = type(ids) == 'table' and type(ids[2]) == 'table' and ids[2] or nil
    local exitOffset = poi and (type(poi.exit) == 'table' and poi.exit or nil) or nil

    return {
        ids = ids, shell = shell, exit = result.exit, exitOffset = exitOffset,
        origin = { x = coords.x, y = coords.y, z = coords.z },
    }
end

function SpawnProp(model, world, heading)
    local ok, entity = pcall(QB.entities.create, model, vector4(world.x, world.y, world.z, heading), { freeze = true, invincible = true })
    if not (ok and type(entity) == 'number' and DoesEntityExist(entity)) then
        local hash = joaat(model)
        if not IsModelInCdimage(hash) then return nil end
        RequestModel(hash)
        local waited = 0
        while not HasModelLoaded(hash) and waited < 3000 do Wait(50) waited = waited + 50 end
        if not HasModelLoaded(hash) then return nil end
        entity = CreateObjectNoOffset(hash, world.x, world.y, world.z, false, false, false)
        SetModelAsNoLongerNeeded(hash)
        if not DoesEntityExist(entity) then return nil end
        FreezeEntityPosition(entity, true)
    end
    SetEntityHeading(entity, heading)
    return entity
end

function ShellEntryCoords(spawned)
    local world = toCoords(spawned.exit)
    if world then return world end
    if spawned.exitOffset then
        local fromOffset = FromShellOffset(spawned, spawned.exitOffset, 0.0)
        return vector3(fromOffset.x, fromOffset.y, fromOffset.z)
    end
    if spawned.shell then return GetEntityCoords(spawned.shell) end
    return vector3(spawned.origin.x, spawned.origin.y, spawned.origin.z)
end

function RemoveShell(spawned)
    local function remove(value, depth)
        if type(value) == 'number' then
            if value ~= 0 and DoesEntityExist(value) then DeleteEntity(value) end
        elseif type(value) == 'table' and depth < 3 then
            for _, entry in ipairs(value) do remove(entry, depth + 1) end
        end
    end
    remove(spawned.ids, 0)
end

function ToShellOffset(spawned, coords, heading)
    if not spawned.shell then
        return { x = coords.x - spawned.origin.x, y = coords.y - spawned.origin.y, z = coords.z - spawned.origin.z }, heading % 360.0
    end
    local offset = GetOffsetFromEntityGivenWorldCoords(spawned.shell, coords.x, coords.y, coords.z)
    return { x = offset.x, y = offset.y, z = offset.z }, (heading - GetEntityHeading(spawned.shell)) % 360.0
end

function FromShellOffset(spawned, offset, heading)
    if not spawned.shell then
        local origin = spawned.origin
        return vector3(origin.x + offset.x, origin.y + offset.y, origin.z + offset.z), (heading or 0.0) % 360.0
    end
    local world = GetOffsetFromEntityInWorldCoords(spawned.shell, offset.x, offset.y, offset.z)
    return world, (GetEntityHeading(spawned.shell) + (heading or 0.0)) % 360.0
end
