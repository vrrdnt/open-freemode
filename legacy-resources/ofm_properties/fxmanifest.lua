fx_version 'cerulean'
game 'gta5'
description 'Open Freemode purchasable property garage access'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_script 'client.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/rules.lua',
    'server/main.lua',
}

dependencies { 'qbx_core', 'ox_lib', 'oxmysql', 'ofm_activities' }
