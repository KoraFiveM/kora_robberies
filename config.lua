Config = Config or {}
local int = exports.qbinterior
Config.Robberies = {
    House = {
        defaults = {
            minPolice = 0,
            cooldown = (1000 * 60) * 15, -- 15 minutes in milliseconds
            maxSteps = 20,
            maxProps = 30,
            lowerZ = -20, -- this is to put the shell below the ground level initially, you can adjust this value as needed per house 
            debug = false,
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
    command = 'houseCreator',
    ace = 'command',
}
