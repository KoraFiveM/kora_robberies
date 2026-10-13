local shells, exit, spawnCoords = nil, nil, nil

RegisterCommand('testShell', function()
    local shell = Config.Robberies.House.shells[math.random(1, #Config.Robberies.House.shells)]
    local coords = GetEntityCoords(PlayerPedId())

    spawnCoords = vector3(coords.x, coords.y, coords.z + Config.Robberies.House.defaults.lowerZ)
    local shellObjects = shell.spawn(spawnCoords)
    shells = shellObjects.id
    exit = shellObjects.id[2]

    QB.print.debug(shells)
end)

RegisterCommand('shellExit', function()
    if not shells or not shells[1] then return end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local offset = GetOffsetFromEntityGivenWorldCoords(
        shells[1],
        playerCoords.x,
        playerCoords.y,
        playerCoords.z
    )

    QB.print.debug('Player world coords:', playerCoords)
    QB.print.debug('Shell world coords:', GetEntityCoords(shells[1]))
    QB.print.debug('Local X offset:', offset.x)
    QB.print.debug('Local Y offset:', offset.y)
    QB.print.debug('Local Z offset:', offset.z)
end)