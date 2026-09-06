fx_version 'cerulean'
game 'gta5'
description 'Open Freemode owned vehicle shop, garage and modification integration'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_script 'client.lua'

server_scripts {
    '@qbx_core/modules/lib.lua',
    '@oxmysql/lib/MySQL.lua',
    'server/rules.lua',
    'server/main.lua',
}

dependencies { 'qbx_core', 'qbx_vehicles', 'ox_lib', 'oxmysql', 'ofm_activities' }
