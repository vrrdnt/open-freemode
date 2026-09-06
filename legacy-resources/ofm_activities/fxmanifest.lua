fx_version 'cerulean'
game 'gta5'
description 'Open Freemode shared activity lifecycle and gameplay'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/tdm.lua',
    'client/pursuit.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/state.lua',
    'server/matchmaking.lua',
    'server/combat_score.lua',
    'server/pursuit_state.lua',
    'server/main.lua',
    'server/tdm.lua',
    'server/pursuit.lua',
}

dependencies { 'baseevents', 'qbx_core', 'ox_lib', 'ox_inventory', 'oxmysql' }
