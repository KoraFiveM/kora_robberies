-- Police alerts through kora_dispatch. A failing or missing dispatch never stops a robbery.
local lastStoreAlert = {} -- store id -> GetGameTimer() of its last alert
local warned = false

local function settings()
    local dispatch = Config.alerts and Config.alerts.dispatch
    return dispatch and dispatch.enabled and dispatch or nil
end

local function raise(code, title, message, coords)
    local ok, id, reason = pcall(function()
        return exports.kora_dispatch:createCall({
            jobTypes = { 'leo' }, code = code, title = title, message = message,
            priority = 2, coords = { x = coords.x, y = coords.y, z = coords.z },
        })
    end)
    if ok and id then return id end
    if not warned then
        warned = true
        QB.print.warn(('[qbrobberies] could not alert police through kora_dispatch: %s'):format(tostring(ok and reason or id)))
    end
    return false
end

-- Raised by server/robbery.lua when someone breaks into a house with its security system on.
AddEventHandler('qbrobberies:houseAlert', function(info)
    local dispatch = settings()
    if not (dispatch and type(info) == 'table' and type(info.coords) == 'table') then return end
    raise(dispatch.houseCode, 'House Break-in',
        ('%s: break-in at a house with an active security system.'):format(tostring(info.label or info.house)), info.coords)
end)

-- kind: 'register' | 'safe'. One alert per store inside the cooldown, so robbing every register does not page again.
function AlertStoreRobbery(storeId, store, coords, kind)
    local dispatch = settings()
    if not (dispatch and coords) then return end

    local now = GetGameTimer()
    local last = lastStoreAlert[storeId]
    if last and now - last < dispatch.cooldown then return end
    lastStoreAlert[storeId] = now

    raise(dispatch.storeCode, 'Store Robbery',
        ('%s: %s robbery in progress.'):format(store.label or storeId, kind), coords)
end
