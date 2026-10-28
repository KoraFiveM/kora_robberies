fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_robberies'
-- Keep the legacy resource name resolvable for exports['qbrobberies'] callers.
provide 'qbrobberies'
author 'qbcore2'
version '1.0.0'
description 'In-game robbery creator with server-authoritative sessions'

dependency 'kora_lib'
dependency 'kora_sql'
dependency 'kora_core'
dependency 'kora_doorlock'

shared_scripts {
    '@kora_lib/init.lua',
    '@kora_sql/init.lua',
    '@kora_core/init.lua',
    'config.lua',
    'shared/schema.lua',
}

client_scripts {
    'client/world.lua',
    'client/creator.lua',
    'client/main.lua',
}

server_scripts {
    'server/state.lua',
    'server/main.lua',
}

files {
    'sql/001_robberies.sql',
}
