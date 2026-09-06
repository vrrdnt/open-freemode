-- Freemode respawn only. Activity-specific death rules will replace this path while in matches.
AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    exports.ox_inventory:weaponWheel(true)
end)

CreateThread(function()
    while true do
        Wait(500)
        if LocalPlayer.state.isLoggedIn and not LocalPlayer.state.ofmActivity and IsEntityDead(PlayerPedId()) then
            Wait(5000)
            if LocalPlayer.state.isLoggedIn and not LocalPlayer.state.ofmActivity and IsEntityDead(PlayerPedId()) then
                local ped = PlayerPedId()
                DoScreenFadeOut(250)
                Wait(300)
                RequestCollisionAtCoord(-1037.6, -2737.8, 20.17)
                NetworkResurrectLocalPlayer(-1037.6, -2737.8, 20.17, 330.0, true, false)
                ClearPedTasksImmediately(ped)
                SetEntityHealth(ped, GetEntityMaxHealth(ped))
                SetPlayerInvincible(PlayerId(), false)
                FreezeEntityPosition(ped, false)
                SetPlayerControl(PlayerId(), true, 0)
                DoScreenFadeIn(500)
            end
        end
    end
end)

RegisterCommand('guide', function()
    lib.alertDialog({header = 'Welcome to Open Freemode', content =
        'Press **M** for freemode vehicles and weapons. Use **F2** for inventory. Character appearance is saved by Qbox and Illenium Appearance.\n\nPizza delivery starts at Pizza This... in Vinewood. Airport Dash at LSIA offers solo and public racing. Terminal Clash TDM starts outside Maze Bank Arena. Use the matching **/pizza_cancel**, **/race_cancel**, or **/tdm_cancel** command to abandon an activity. Cops-and-robbers is in development. Temporary spawned cars are not owned vehicles.',
        centered = true})
end, false)
