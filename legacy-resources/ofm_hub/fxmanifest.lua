fx_version 'cerulean'
game 'gta5'
description 'Open Freemode onboarding, activity browser and handbook'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/styles.css',
    'web/app.js',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_script 'client.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
}

dependencies { 'qbx_core', 'ox_lib', 'oxmysql', 'ofm_activities', 'ofm_vehicles' }
