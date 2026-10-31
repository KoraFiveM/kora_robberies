fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbrobberies'
author 'qbcore2'
version '1.0.0'
description 'Robbery creator: house robberies (item lists, reusable shell setups, houses) and store robberies (registers, safes)'

dependency 'kora_lib'
dependency 'kora_sql'
dependency 'kora_core'
dependency 'kora_interior'

shared_scripts {
    '@kora_lib/init.lua',
    '@kora_sql/init.lua',
    '@kora_core/init.lua',
    'config.lua',
    'shared/constants.lua',
    'shared/shells.lua',
}

client_scripts {
    'client/shell.lua',
    'client/creator.lua',
    'client/robbery.lua',
    'client/store.lua',
    'client/main.lua',
}

-- Order matters here: each file uses the ones before it.
server_scripts {
    'server/_functions.lua',
    'server/rules.lua',
    'server/data.lua',
    'server/creator.lua',
    'server/robbery.lua',
    'server/store.lua',
}
