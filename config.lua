Config = Config or {}

Config.Robberies = {
    command = 'robberies',
    adminPermission = 'admin',
    interactionDistance = 1.8,
    definitionDistance = 250.0,
    sessionTimeout = 30 * 60 * 1000,
    policeJobType = 'leo',
    defaultMinPolice = 0,
    defaultCooldown = 30 * 60,
    maxDefinitions = 200,
    maxSteps = 20,
    maxProps = 30,
    debug = false,
}

-- Registers this resource-owned configuration with qblib without changing its public Config table.
if QB and QB.config and QB.config.adopt then Config = QB.config.adopt(Config) end
