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
if QB and QB.config and QB.config.adopt then
    local config = QB.config
    Config.Robberies.command = config.string(Config.Robberies.command, {
        minLength = 1,
        label = 'Robbery editor command', advanced = true,
        description = 'Chat command name without a leading slash that opens the robbery creator. Restart qbrobberies to apply saved changes.',
    })
    Config.Robberies.adminPermission = config.string(Config.Robberies.adminPermission, {
        label = 'Robbery editor permission', advanced = true,
        description = 'qbcore permission identifier required for server-side robbery administration. Restart qbrobberies to apply saved changes.',
    })
    Config.Robberies.interactionDistance = config.number(Config.Robberies.interactionDistance, {
        label = 'Interaction distance (unused)', advanced = true,
        description = 'Legacy distance in metres. Current robbery interactions use each definition and step radius, so this setting has no gameplay effect. Restart qbrobberies to apply saved changes.',
    })
    Config.Robberies.definitionDistance = config.number(Config.Robberies.definitionDistance, {
        min = 0,
        label = 'Robbery scenery load distance (metres)', advanced = true,
        description = 'Radius around a robbery start point within which its local props are loaded; leaving the area removes them. Restart qbrobberies to apply saved changes.',
    })
    Config.Robberies.sessionTimeout = config.integer(Config.Robberies.sessionTimeout, {
        min = 0,
        label = 'Robbery time limit (milliseconds)', advanced = false,
        description = 'Maximum duration of an active robbery before it is stopped; also sets the police dispatch alert duration. 1800000 milliseconds equals 30 minutes. Restart qbrobberies to apply saved changes.',
    })
    Config.Robberies.policeJobType = config.string(Config.Robberies.policeJobType, {
        label = 'Police job type', advanced = true,
        description = 'qbcore job-type identifier used to count on-duty officers and select police dispatch recipients. Restart qbrobberies to apply saved changes.',
    })
    Config.Robberies.defaultMinPolice = config.integer(Config.Robberies.defaultMinPolice, {
        min = 0, max = 64,
        label = 'Default officers required', advanced = false,
        description = 'Default minimum on-duty officer count for new robberies and definitions missing a valid value; does not replace an existing valid per-robbery requirement. Restart qbrobberies to apply saved changes.',
    })
    Config.Robberies.defaultCooldown = config.integer(Config.Robberies.defaultCooldown, {
        min = 0, max = 604800,
        label = 'Default robbery cooldown (seconds)', advanced = false,
        description = 'Default wait after completing a robbery before it can be started again, for new definitions or those missing a valid cooldown. 1800 seconds equals 30 minutes; existing valid per-robbery cooldowns are retained. Restart qbrobberies to apply saved changes.',
    })
    Config.Robberies.maxDefinitions = config.integer(Config.Robberies.maxDefinitions, {
        min = 0,
        label = 'Maximum robbery definitions', advanced = false,
        description = 'Maximum total robbery definitions allowed when creating a robbery; lowering this does not delete existing definitions. Restart qbrobberies to apply saved changes.',
    })
    Config.Robberies.maxSteps = config.integer(Config.Robberies.maxSteps, {
        min = 0,
        label = 'Maximum steps per robbery', advanced = true,
        description = 'Maximum steps accepted when normalizing or editing a robbery. Lowering this can prevent oversized existing definitions from loading or being saved. Restart qbrobberies to apply saved changes.',
    })
    Config.Robberies.maxProps = config.integer(Config.Robberies.maxProps, {
        min = 0,
        label = 'Maximum props per robbery', advanced = true,
        description = 'Maximum local scenery props accepted when normalizing or editing a robbery. Lowering this can prevent oversized existing definitions from loading or being saved. Restart qbrobberies to apply saved changes.',
    })
    Config.Robberies.debug = config.boolean(Config.Robberies.debug, {
        label = 'Show robbery zone guides', advanced = true,
        description = 'Draws diagnostic zone boundaries for robbery load areas, start areas, and steps. Restart qbrobberies to apply saved changes.',
    })
    Config = config.adopt(Config)
end
