Config = Config or {}
local int = exports.kora_interior
Config.Robberies = {
    House = {
        defaults = {
            minPolice = 0,
            cooldown = (1000 * 60) * 15, -- 15 minutes in milliseconds
            robberyTime = (1000 * 60) * 15, -- how long a house stays open to everyone once someone has broken in, in milliseconds
            maxSteps = 20,
            maxProps = 30,
            lowerZ = -20, -- this is to put the shell below the ground level initially, you can adjust this value as needed per house 
            debug = false,
            breakItem = 'lockpick',          -- needed to break in, unless the shell or the house says otherwise
            securityItem = 'electronickit',  -- also needed when a house has its security system on
            consumeBreakItem = true,         -- the break-in item is used up on a successful break-in
            breakTime = 8000,                -- ms
            searchTime = 5000,               -- ms to search one prop
            searchLabel = 'Searching...',    -- the progress bar text while searching. Each prop can change it
            policeJob = 'police',
            breakAnim = { dict = 'missheistfbisetup1', clip = 'hassle_intro_loop_f', flags = 49 },
            searchAnim = { dict = 'mp_arresting', clip = 'a_uncuff', flag = 49 },
            searchDisable = { vehicle = true, move = true, combat = true }, -- what is blocked while searching. Each prop can change it
        },
        shells = {
            {
                label = 'Apartment Shell',
                spawn = function(coords)
                    local shell, exit = int:CreateApartmentShell(coords)
                    return {id = shell, exit = exit}
                end
            },
            {
                label = 'Tier 1 House',
                spawn = function(coords)
                    local shell, exit = int:CreateTier1House(coords)
                    return {id = shell, exit = exit}
                end
            },
            {
                label = 'Trevor Shell',
                spawn = function(coords)
                    local shell, exit = int:CreateTrevorsShell(coords)
                    return {id = shell, exit = exit}
                end
            },
            {
                label = 'Caravan Shell',
                spawn = function(coords)
                    local shell, exit = int:CreateCaravanShell(coords)
                    return {id = shell, exit = exit}
                end
            },
            {
                label = 'Lester Shell',
                spawn = function(coords)
                    local shell, exit = int:CreateLesterShell(coords)
                    return {id = shell, exit = exit}
                end
            },
            {
                label = 'Ranch Shell',
                spawn = function(coords)
                    local shell, exit = int:CreateRanchShell(coords)
                    return {id = shell, exit = exit}
                end
            },
            {
                label = 'Container',
                spawn = function(coords)
                    local shell, exit = int:CreateContainer(coords)
                    return {id = shell, exit = exit}
                end
            },
            {
                label = 'Furnished Mid Apartment',
                spawn = function(coords)
                    local shell, exit = int:CreateFurniMid(coords)
                    return {id = shell, exit = exit}
                end
            },
            {
                label = 'Modern Motel',
                spawn = function(coords)
                    local shell, exit = int:CreateFurniMotelModern(coords)
                    return {id = shell, exit = exit}
                end
            },
            {
                label = 'Franklin Aunt Shell',
                spawn = function(coords)
                    local shell, exit = int:CreateFranklinAunt(coords)
                    return {id = shell, exit = exit}
                end
            },
            {
                label = 'Medium Garage',
                spawn = function(coords)
                    local shell, exit = int:CreateGarageMed(coords)
                    return {id = shell, exit = exit}
                end
            },
            {
                label = 'Michael Shell',
                spawn = function(coords)
                    local shell, exit = int:CreateMichael(coords)
                    return {id = shell, exit = exit}
                end
            },
            {
                label = 'Office 1',
                spawn = function(coords)
                    local shell, exit = int:CreateOffice1(coords)
                    return {id = shell, exit = exit}
                end
            },
            {
                label = 'Store 1',
                spawn = function(coords)
                    local shell, exit = int:CreateStore1(coords)
                    return {id = shell, exit = exit}
                end
            },
            {
                label = 'Warehouse 1',
                spawn = function(coords)
                    local shell, exit = int:CreateWarehouse1(coords)
                    return {id = shell, exit = exit}
                end
            }
        }
    }
}

-- The in-game creator. Players need this ace to open it.
Config.Creator = {
    command = 'robberyCreator',
    ace = 'command',
}

-- Stores: registers and safes. Each store can set its own minimum police; each register its own sticky note chance.
Config.Robberies.Store = {
    defaults = {
        minPolice = 2,
        resetTime = (1000 * 60) * 30,              -- how long a robbed register or safe stays empty, in milliseconds
        stickyNoteChance = 10,                     -- percent chance for a new register to give the safe code
        registerCash = { min = 50, max = 200 },
        safeCash = { min = 500, max = 1000 },
        blowTime = { min = 5000, max = 10000 },    -- how long the thermite burns, in milliseconds
        cashItem = 'cash',
        stickyNoteItem = 'stickynote',
        thermiteItem = 'thermite',
    },
}

Config.stores = {
    enabled = true, -- off: registers and safes are hidden and cannot be robbed (houses are not affected)
}

-- Police alerts through kora_dispatch. Today's test server alerted nobody (F#126).
Config.alerts = {
    dispatch = {
        enabled = true,
        houseCode = '10-68',     -- radio code on a break-in at a house with its security system on
        storeCode = '10-90',     -- radio code when a register is robbed or a safe is opened
        cooldown = 60000,        -- ms between two alerts for the same store, so each register does not page again
    },
}

-- Keep the shell spawners (functions) and the creator ace out of the editable settings:
-- the shell list is code, and the ace decides who can open the creator.
local shells, creator = Config.Robberies.House.shells, Config.Creator
Config.Robberies.House.shells, Config.Creator = nil, nil
if Kora and Kora.config and Kora.config.adopt then
    Config = Kora.config.adopt(Config, {
        descriptions = {
            ['stores.enabled'] = 'Turns store robberies (registers and safes) on or off. Restart the resource to apply.',
            ['alerts.dispatch.enabled'] = 'Alert police through kora_dispatch when a security house is broken into or a store register or safe is robbed.',
            ['alerts.dispatch.houseCode'] = 'Radio code shown on the dispatch call for a house break-in.',
            ['alerts.dispatch.storeCode'] = 'Radio code shown on the dispatch call for a store robbery.',
            ['alerts.dispatch.cooldown'] = 'Minimum milliseconds between two dispatch alerts for the same store.',
        },
    })
end
Config.Robberies.House.shells, Config.Creator = shells, creator