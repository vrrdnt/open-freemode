local config = require 'config'.pursuit

local queued = false
local queueToken
local pursuit
local promptVisible = false
local promptText
local checkpointBlip
local targetBlip
local submitting = false
local copGroup = joaat('OFM_PURSUIT_COPS')
local robberGroup = joaat('OFM_PURSUIT_ROBBER')
local playerGroup = joaat('PLAYER')

AddRelationshipGroup('OFM_PURSUIT_COPS')
AddRelationshipGroup('OFM_PURSUIT_ROBBER')
SetRelationshipBetweenGroups(0, copGroup, copGroup)
SetRelationshipBetweenGroups(0, robberGroup, robberGroup)
SetRelationshipBetweenGroups(5, copGroup, robberGroup)
SetRelationshipBetweenGroups(5, robberGroup, copGroup)

local function notify(description, kind)
    lib.notify({ title = config.name, description = description, type = kind or 'inform' })
end

local function showPrompt(text)
    if promptVisible and promptText == text then return end
    if promptVisible then lib.hideTextUI() end
    lib.showTextUI(text)
    promptVisible = true
    promptText = text
end

local function hidePrompt()
    if not promptVisible then return end
    lib.hideTextUI()
    promptVisible = false
    promptText = nil
end

local function teamGroup(team)
    return team == 'cops' and copGroup or robberGroup
end

local function removeBlips()
    if checkpointBlip then RemoveBlip(checkpointBlip) checkpointBlip = nil end
    if targetBlip then RemoveBlip(targetBlip) targetBlip = nil end
end

local function addTargetBlip()
    if targetBlip or not pursuit or pursuit.team ~= 'cops' then return false end
    local robberPlayer = GetPlayerFromServerId(pursuit.robber)
    if robberPlayer == -1 then return false end
    targetBlip = AddBlipForEntity(GetPlayerPed(robberPlayer))
    SetBlipSprite(targetBlip, 225)
    SetBlipColour(targetBlip, 1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Getaway vehicle')
    EndTextCommandSetBlipName(targetBlip)
    return true
end

local function applyLoadout(data)
    local ped = PlayerPedId()
    RemoveAllPedWeapons(ped, true)
    for _, item in ipairs(data.loadout) do
        GiveWeaponToPed(ped, joaat(item.weapon), item.ammo, false, false)
    end
    SetPedArmour(ped, data.armor)
end

local function waitForVehicle(netId)
    local deadline = GetGameTimer() + 8000
    while GetGameTimer() < deadline do
        if NetworkDoesEntityExistWithNetworkId(netId) then
            local vehicle = NetworkGetEntityFromNetworkId(netId)
            if vehicle ~= 0 and DoesEntityExist(vehicle) then return vehicle end
        end
        Wait(50)
    end
end

local function placeInVehicle(data, frozen)
    local spawn = data.vehicleSpawn or data.spawn
    DoScreenFadeOut(150)
    Wait(200)
    RequestCollisionAtCoord(spawn.x, spawn.y, spawn.z)
    NetworkResurrectLocalPlayer(spawn.x, spawn.y, spawn.z, spawn.w, true, false)
    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    SetEntityCoordsNoOffset(ped, spawn.x, spawn.y, spawn.z, false, false, false)
    SetEntityHeading(ped, spawn.w)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))

    local vehicle = waitForVehicle(data.vehicleNetId)
    if not vehicle then
        DoScreenFadeIn(250)
        return false
    end
    SetEntityCoordsNoOffset(vehicle, spawn.x, spawn.y, spawn.z, false, false, false)
    SetEntityHeading(vehicle, spawn.w)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleDoorsLocked(vehicle, 1)
    SetPedIntoVehicle(ped, vehicle, -1)
    SetEntityInvincible(vehicle, frozen)
    FreezeEntityPosition(vehicle, frozen)
    SetPlayerInvincible(PlayerId(), frozen)
    FreezeEntityPosition(ped, frozen)
    SetPlayerControl(PlayerId(), true, 0)
    pursuit.vehicle = vehicle
    applyLoadout(data)
    DoScreenFadeIn(250)
    return true
end

local function setPursuitState(enabled)
    LocalPlayer.state:set('ofmActivity', enabled and 'pursuit' or nil, true)
    LocalPlayer.state:set('invBusy', enabled, true)
    exports.ox_inventory:weaponWheel(true)
    if enabled then
        local group = teamGroup(pursuit.team)
        SetPedRelationshipGroupHash(PlayerPedId(), group)
        SetEntityCanBeDamagedByRelationshipGroup(PlayerPedId(), false, group)
        SetCanAttackFriendly(PlayerPedId(), false, false)
    else
        local ped = PlayerPedId()
        SetPedRelationshipGroupHash(ped, playerGroup)
        SetEntityCanBeDamagedByRelationshipGroup(ped, true, copGroup)
        SetEntityCanBeDamagedByRelationshipGroup(ped, true, robberGroup)
        SetCanAttackFriendly(ped, true, false)
        for _, player in ipairs(GetActivePlayers()) do
            SetPedRelationshipGroupHash(GetPlayerPed(player), playerGroup)
        end
    end
end

local function setCheckpoint(index)
    if checkpointBlip then RemoveBlip(checkpointBlip) checkpointBlip = nil end
    if not pursuit or pursuit.team ~= 'robber' then return end
    local point = config.checkpoints[index]
    if not point then return end
    pursuit.nextCheckpoint = index
    checkpointBlip = AddBlipForCoord(point.x, point.y, point.z)
    SetBlipSprite(checkpointBlip, 1)
    SetBlipColour(checkpointBlip, 5)
    SetBlipRoute(checkpointBlip, true)
    SetBlipRouteColour(checkpointBlip, 5)
end

local function clearPursuit(position)
    hidePrompt()
    removeBlips()
    queued = false
    queueToken = nil
    submitting = false
    if pursuit then
        local ped = PlayerPedId()
        local returnHealth = math.max(1, pursuit.returnHealth or GetEntityMaxHealth(ped))
        local returnArmor = pursuit.returnArmor or 0
        local returnWantedLevel = pursuit.returnWantedLevel or 0
        RemoveAllPedWeapons(ped, true)
        SetPlayerInvincible(PlayerId(), false)
        FreezeEntityPosition(ped, false)
        if pursuit.vehicle and DoesEntityExist(pursuit.vehicle) then
            SetEntityInvincible(pursuit.vehicle, false)
            FreezeEntityPosition(pursuit.vehicle, false)
        end
        setPursuitState(false)
        pursuit = nil
        if position then
            RequestCollisionAtCoord(position.x, position.y, position.z)
            NetworkResurrectLocalPlayer(position.x, position.y, position.z, position.w, true, false)
            ped = PlayerPedId()
            SetEntityCoordsNoOffset(ped, position.x, position.y, position.z, false, false, false)
            SetEntityHeading(ped, position.w)
        end
        SetEntityHealth(ped, returnHealth)
        SetPedArmour(ped, returnArmor)
        SetPlayerWantedLevel(PlayerId(), returnWantedLevel, false)
        SetPlayerWantedLevelNow(PlayerId(), false)
    end
end

local function joinQueue()
    if queued or pursuit then return end
    local response = lib.callback.await('ofm_activities:pursuit:join', false)
    if not response or not response.ok then
        return notify(response and response.message or 'The City Escape queue could not be joined.', 'error')
    end
    queued = true
    queueToken = response.token
    notify(('Queue position %d. Stay on foot in the marker.'):format(response.position), 'success')
end

local function cancelPursuit()
    if not queued and not pursuit then return notify('You are not in City Escape.', 'error') end
    local response = lib.callback.await('ofm_activities:pursuit:cancel', false)
    if not response or not response.ok then
        return notify(response and response.message or 'City Escape could not be cancelled.', 'error')
    end
end

local function timeText(milliseconds)
    local total = math.max(0, math.ceil(milliseconds / 1000))
    return ('%d:%02d'):format(math.floor(total / 60), total % 60)
end

local function pursuitText()
    if pursuit.dead then return ('POLICE DOWN · Respawning in %d seconds'):format(pursuit.respawnSeconds or 0) end
    local remaining = pursuit.deadline and timeText(pursuit.deadline - GetGameTimer()) or '5:00'
    if pursuit.team == 'robber' then
        return ('ROBBER · Escape checkpoint %d/%d · %s'):format(
            pursuit.nextCheckpoint or 1, pursuit.totalCheckpoints, remaining)
    end
    return ('POLICE · Stop the getaway · %d/%d checkpoints · %s'):format(
        pursuit.completedCheckpoints or 0, pursuit.totalCheckpoints, remaining)
end

RegisterCommand('pursuit_cancel', cancelPursuit, false)

RegisterNetEvent('ofm_activities:pursuit:queueStatus', function(size, message)
    if queued then notify(message or ('%d/%d players waiting.'):format(size, config.maximumPlayers)) end
end)

RegisterNetEvent('ofm_activities:pursuit:prepare', function(data)
    if not queued or queueToken ~= data.token then return end
    queued = false
    queueToken = nil
    pursuit = data
    pursuit.phase = 'countdown'
    pursuit.nextCheckpoint = 1
    pursuit.completedCheckpoints = 0
    pursuit.returnHealth = GetEntityHealth(PlayerPedId())
    pursuit.returnArmor = GetPedArmour(PlayerPedId())
    pursuit.returnWantedLevel = GetPlayerWantedLevel(PlayerId())
    ClearPlayerWantedLevel(PlayerId())
    exports.ox_inventory:closeInventory()
    setPursuitState(true)
    if not placeInVehicle(data, true) then
        notify('The activity vehicle did not stream in. City Escape was cancelled.', 'error')
        lib.callback.await('ofm_activities:pursuit:cancel', false)
        return
    end

    local token = data.token
    CreateThread(function()
        for count = data.countdownSeconds, 1, -1 do
            if not pursuit or pursuit.token ~= token or pursuit.phase ~= 'countdown' then return end
            showPrompt(('%s · Pursuit starts in %d'):format(data.teamLabel, count))
            Wait(1000)
        end
    end)
end)

RegisterNetEvent('ofm_activities:pursuit:start', function(durationSeconds)
    if not pursuit or pursuit.phase ~= 'countdown' then return end
    pursuit.phase = 'running'
    pursuit.deadline = GetGameTimer() + durationSeconds * 1000
    SetPlayerInvincible(PlayerId(), false)
    FreezeEntityPosition(PlayerPedId(), false)
    if pursuit.vehicle and DoesEntityExist(pursuit.vehicle) then
        SetEntityInvincible(pursuit.vehicle, false)
        FreezeEntityPosition(pursuit.vehicle, false)
    end
    if pursuit.team == 'robber' then
        SetPlayerWantedLevel(PlayerId(), 5, false)
        SetPlayerWantedLevelNow(PlayerId(), false)
        setCheckpoint(1)
        notify('Reach every yellow checkpoint before police stop you.', 'success')
    else
        addTargetBlip()
        local token = pursuit.token
        CreateThread(function()
            for _ = 1, 20 do
                if not pursuit or pursuit.token ~= token or targetBlip then return end
                Wait(500)
                addTargetBlip()
            end
        end)
        notify('Stop the robber before the route is complete.', 'success')
    end
end)

RegisterNetEvent('ofm_activities:pursuit:progress', function(completed, total)
    if not pursuit then return end
    pursuit.completedCheckpoints = completed
    pursuit.totalCheckpoints = total
end)

RegisterNetEvent('ofm_activities:pursuit:copDown', function(seconds)
    if not pursuit or pursuit.team ~= 'cops' then return end
    pursuit.dead = true
    pursuit.respawnSeconds = seconds
    notify(('Police respawn in %d seconds.'):format(seconds))
end)

RegisterNetEvent('ofm_activities:pursuit:respawn', function(data)
    if not pursuit or pursuit.team ~= 'cops' or pursuit.phase ~= 'running' then return end
    pursuit.dead = false
    pursuit.vehicleNetId = data.vehicleNetId
    pursuit.vehicleSpawn = data.spawn
    pursuit.loadout = data.loadout
    pursuit.armor = data.armor
    if not placeInVehicle(data, false) then
        notify('The replacement police vehicle did not stream in.', 'error')
        lib.callback.await('ofm_activities:pursuit:cancel', false)
    end
end)

RegisterNetEvent('ofm_activities:pursuit:restore', function(position, message, result)
    clearPursuit(position)
    if result then
        notify(('%s · %d kills / %d deaths · $%d banked.'):format(
            result.won and 'Victory' or 'Defeat', result.kills, result.deaths, result.payout),
            result.won and 'success' or 'inform')
    elseif message then
        notify(message, 'error')
    end
end)

CreateThread(function()
    local blip = AddBlipForCoord(config.queue.x, config.queue.y, config.queue.z)
    SetBlipSprite(blip, 60)
    SetBlipColour(blip, 29)
    SetBlipScale(blip, 0.9)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(config.name .. ' Cops & Robbers')
    EndTextCommandSetBlipName(blip)

    while true do
        local sleep = 750
        if not pursuit and not LocalPlayer.state.ofmActivity then
            local coords = GetEntityCoords(PlayerPedId())
            local range = #(coords - vec3(config.queue.x, config.queue.y, config.queue.z))
            if range < 30.0 then
                sleep = 0
                DrawMarker(1, config.queue.x, config.queue.y, config.queue.z - 1.0,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.5, 2.5, 0.5,
                    70, 130, 230, 170, false, false, 2, false)
            end
            if range < 2.5 then
                sleep = 0
                showPrompt(queued and '[E] Leave City Escape queue' or '[E] Join City Escape')
                if IsControlJustReleased(0, 38) then
                    hidePrompt()
                    if queued then cancelPursuit() else joinQueue() end
                end
            else
                hidePrompt()
            end
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        local sleep = 500
        if pursuit and pursuit.phase == 'running' then
            sleep = 0
            showPrompt(pursuitText())
            if pursuit.team == 'robber' and not pursuit.dead and not submitting then
                local point = config.checkpoints[pursuit.nextCheckpoint]
                if point then
                    DrawMarker(1, point.x, point.y, point.z - 1.0,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 9.0, 9.0, 2.0,
                        245, 190, 35, 170, false, false, 2, false)
                    if #(GetEntityCoords(PlayerPedId()) - vec3(point.x, point.y, point.z)) < config.checkpointRadius then
                        submitting = true
                        local index = pursuit.nextCheckpoint
                        local response = lib.callback.await('ofm_activities:pursuit:checkpoint', false,
                            pursuit.token, index)
                        submitting = false
                        if pursuit and response and response.ok and not response.completed then
                            pursuit.completedCheckpoints = index
                            setCheckpoint(response.nextCheckpoint)
                        elseif pursuit and response and not response.ok then
                            notify(response.message or 'The checkpoint was rejected.', 'error')
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        if pursuit then
            DisableControlAction(0, 244, true)
            DisableControlAction(0, 289, true)
            if pursuit.phase == 'running' and pursuit.team == 'robber'
                and GetPlayerWantedLevel(PlayerId()) < 5 then
                SetPlayerWantedLevel(PlayerId(), 5, false)
                SetPlayerWantedLevelNow(PlayerId(), false)
            end
            local ownGroup = teamGroup(pursuit.team)
            for _, player in ipairs(GetActivePlayers()) do
                local serverId = GetPlayerServerId(player)
                local team = Player(serverId).state.ofmPursuitTeam
                if team then SetPedRelationshipGroupHash(GetPlayerPed(player), teamGroup(team)) end
            end
            SetEntityCanBeDamagedByRelationshipGroup(PlayerPedId(), false, ownGroup)
            Wait(0)
        else
            Wait(500)
        end
    end
end)

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    local response = lib.callback.await('ofm_activities:pursuit:status', false)
    if response and response.queued then
        queued = true
        queueToken = response.token
    end
end)

AddEventHandler('QBCore:Client:OnPlayerUnload', function() clearPursuit() end)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then clearPursuit() end
end)
