fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbrobberies'
author 'qbcore2'
version '1.0.0'
description 'House robbery creator: item lists, reusable shell setups and houses'

dependency 'qblib'
dependency 'qbsql'
dependency 'qbcore'
dependency 'qbinterior'

shared_scripts {
    '@qblib/init.lua',
    '@qbsql/init.lua',
    '@qbcore/init.lua',
    'config.lua',
    'shared/constants.lua',
    'shared/shells.lua',
}

client_scripts {
    'client/shell.lua',
    'client/creator.lua',
    'client/main.lua',
}

-- Order matters here: each file uses the ones before it.
server_scripts {
    'server/_functions.lua',
    'server/rules.lua',
    'server/data.lua',
    'server/creator.lua',
}
