fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_robberies'
author 'qbcore2'
version '0.1.0'
description 'Robbery creator: house robberies (item lists, reusable shell setups, houses) and store robberies (registers, safes)'

dependency 'kora_lib'
dependency 'kora_sql'
dependency 'kora_core'
dependency 'kora_interior'

shared_scripts {
    '@kora_lib/init.lua',
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
    '@kora_sql/init.lua',
    'server/schema.lua',
    'server/_functions.lua',
    'server/rules.lua',
    'server/data.lua',
    'server/creator.lua',
    'server/robbery.lua',
    'server/store.lua',
    -- Optional FFT hooks: returns immediately unless fft_kora_hooks is true.
    'fft_hooks_server.lua',
}

-- kora_qa: Gherkin test scenarios (converted legacy tests), see [kora]/kora_qa/README.md
qa_feature 'tests/*.feature'
