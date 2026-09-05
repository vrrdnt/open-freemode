local spawning = false

RegisterNetEvent('ofm:spawnTestPlayer', function(accountId)
    if spawning then return end
    spawning = true
    local model = joaat('mp_m_freemode_01')
    RequestModel(model)
    local deadline = GetGameTimer() + 15000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then
        print('Test spawn failed; please reconnect.')
        return
    end
    SetPlayerModel(PlayerId(), model)
    SetPedDefaultComponentVariation(PlayerPedId())
    NetworkResurrectLocalPlayer(-1037.7, -2737.8, 20.17, 330.0, true, false)
    SetPlayerControl(PlayerId(), true, 0)
    SetModelAsNoLongerNeeded(model)
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    DoScreenFadeIn(500)
    print(('Open Freemode test profile %s loaded. Test progress will reset.'):format(accountId))
end)

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(100) end
    while not spawning do
        TriggerServerEvent('ofm:requestSpawn')
        Wait(2000)
    end
end)
