fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbrobberies'
author 'qbcore2'
version '1.0.0'
description 'In-game robbery creator with server-authoritative sessions'

dependency 'qblib'
dependency 'qbsql'
dependency 'qbcore'
dependency 'qbdoorlock'

shared_scripts {
    '@qblib/init.lua',
    '@qbsql/init.lua',
    '@qbcore/init.lua',
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
