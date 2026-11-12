-- Turns the shells in config.lua into an ordered list with a stable key each, made from its label:
-- 'Tier 1 House' -> 'tier_1_house'. Renaming a label in the config renames the key, so a saved setup
-- would no longer match it. Change the label's wording only on purpose.
HouseShells = {}      -- ordered: { key, label, spawn }
HouseShellByKey = {}  -- key -> the same entry

local function slug(label)
    local base = tostring(label):lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
    return base ~= '' and base:sub(1, 36) or 'shell'
end

for _, shell in ipairs(Config.Robberies.House.shells) do
    local key, n = slug(shell.label), 1
    local base = key
    while HouseShellByKey[key] do
        n = n + 1
        key = ('%s_%d'):format(base, n)
    end
    local entry = { key = key, label = shell.label, spawn = shell.spawn }
    HouseShells[#HouseShells + 1] = entry
    HouseShellByKey[key] = entry
end

-- Where a house's shell is spawned: below its entrance. Every player entering the same house spawns it
-- at the same place, so they end up in the same room. A house can set its own depth.
function HouseSpawnCoords(house)
    local lower = house.lowerZ or Config.Robberies.House.defaults.lowerZ
    return vector3(house.coords.x, house.coords.y, house.coords.z + lower)
end
