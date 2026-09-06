fx_version 'cerulean'
game 'gta5'
description 'Open Freemode shared activity lifecycle and gameplay'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_script 'client/main.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/state.lua',
    'server/matchmaking.lua',
    'server/main.lua',
}

dependencies { 'qbx_core', 'ox_lib', 'oxmysql' }
