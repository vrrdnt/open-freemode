local config = require 'config'.tdm

local queued = false
local queueToken
local tdm
local promptVisible = false
local promptText
local redGroup = joaat('OFM_TDM_RED')
local blueGroup = joaat('OFM_TDM_BLUE')
local playerGroup = joaat('PLAYER')

AddRelationshipGroup('OFM_TDM_RED')
AddRelationshipGroup('OFM_TDM_BLUE')
SetRelationshipBetweenGroups(0, redGroup, redGroup)
SetRelationshipBetweenGroups(0, blueGroup, blueGroup)
SetRelationshipBetweenGroups(5, redGroup, blueGroup)
SetRelationshipBetweenGroups(5, blueGroup, redGroup)

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
    return team == 'red' and redGroup or blueGroup
end

local function applyLoadout()
    if not tdm then return end
    local ped = PlayerPedId()
    RemoveAllPedWeapons(ped, true)
    for _, item in ipairs(tdm.loadout) do
        GiveWeaponToPed(ped, joaat(item.weapon), item.ammo, false, false)
    end
    SetPedArmour(ped, tdm.armor)
end

local function placePlayer(spawn, frozen)
    local ped = PlayerPedId()
    DoScreenFadeOut(150)
    Wait(200)
    RequestCollisionAtCoord(spawn.x, spawn.y, spawn.z)
    NetworkResurrectLocalPlayer(spawn.x, spawn.y, spawn.z, spawn.w, true, false)
    ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    SetEntityCoordsNoOffset(ped, spawn.x, spawn.y, spawn.z, false, false, false)
    SetEntityHeading(ped, spawn.w)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetPlayerInvincible(PlayerId(), frozen)
    FreezeEntityPosition(ped, frozen)
    SetPlayerControl(PlayerId(), true, 0)
    applyLoadout()
    DoScreenFadeIn(250)
end

local function setCombatState(enabled)
    exports.ox_inventory:weaponWheel(true)
    if enabled then
        local group = teamGroup(tdm.team)
        SetPedRelationshipGroupHash(PlayerPedId(), group)
        SetEntityCanBeDamagedByRelationshipGroup(PlayerPedId(), false, group)
        SetCanAttackFriendly(PlayerPedId(), false, false)
    else
        local ped = PlayerPedId()
        SetPedRelationshipGroupHash(ped, playerGroup)
        SetEntityCanBeDamagedByRelationshipGroup(ped, true, redGroup)
        SetEntityCanBeDamagedByRelationshipGroup(ped, true, blueGroup)
        SetCanAttackFriendly(ped, true, false)
        for _, player in ipairs(GetActivePlayers()) do
            SetPedRelationshipGroupHash(GetPlayerPed(player), playerGroup)
        end
    end
end

local function scoreText(score)
    return ('RED %d  ·  %d BLUE  |  First to %d  |  /tdm_cancel to forfeit')
        :format(score.red, score.blue, score.limit)
end

local function clearTdm(position)
    hidePrompt()
    queued = false
    queueToken = nil
    if tdm then
        local ped = PlayerPedId()
        local returnHealth = math.max(1, tdm.returnHealth or GetEntityMaxHealth(ped))
        local returnArmor = tdm.returnArmor or 0
        RemoveAllPedWeapons(ped, true)
        SetPlayerInvincible(PlayerId(), false)
        FreezeEntityPosition(ped, false)
        setCombatState(false)
        tdm = nil
        if position then
            RequestCollisionAtCoord(position.x, position.y, position.z)
            NetworkResurrectLocalPlayer(position.x, position.y, position.z, position.w, true, false)
            ped = PlayerPedId()
            SetEntityCoordsNoOffset(ped, position.x, position.y, position.z, false, false, false)
            SetEntityHeading(ped, position.w)
        end
        SetEntityHealth(ped, returnHealth)
        SetPedArmour(ped, returnArmor)
    end
end

local function joinQueue()
    if queued or tdm then return end
    local response = lib.callback.await('ofm_activities:tdm:join', false)
    if not response or not response.ok then
        return notify(response and response.message or 'The TDM queue could not be joined.', 'error')
    end
    queued = true
    queueToken = response.token
    notify(('Queue position %d. Stay inside the marker.'):format(response.position), 'success')
end

local function cancelTdm()
    if not queued and not tdm then return notify('You are not in Terminal Clash.', 'error') end
    local response = lib.callback.await('ofm_activities:tdm:cancel', false)
    if not response or not response.ok then
        return notify(response and response.message or 'TDM could not be cancelled.', 'error')
    end
end

RegisterCommand('tdm_cancel', cancelTdm, false)

RegisterNetEvent('ofm_activities:tdm:queueStatus', function(size, message)
    if queued then notify(message or ('%d/%d players waiting.'):format(size, config.maximumPlayers)) end
end)

RegisterNetEvent('ofm_activities:tdm:prepare', function(data)
    if not queued or queueToken ~= data.token then return end
    queued = false
    queueToken = nil
    tdm = data
    tdm.phase = 'countdown'
    tdm.returnHealth = GetEntityHealth(PlayerPedId())
    tdm.returnArmor = GetPedArmour(PlayerPedId())
    exports.ox_inventory:closeInventory()
    setCombatState(true)
    placePlayer(data.spawn, true)

    local token = data.token
    CreateThread(function()
        for count = data.countdownSeconds, 1, -1 do
            if not tdm or tdm.token ~= token or tdm.phase ~= 'countdown' then return end
            showPrompt(('%s team · Match starts in %d'):format(data.teamLabel, count))
            Wait(1000)
        end
    end)
end)

RegisterNetEvent('ofm_activities:tdm:start', function(score)
    if not tdm or tdm.token == nil then return end
    tdm.phase = 'running'
    tdm.score = score
    SetPlayerInvincible(PlayerId(), false)
    FreezeEntityPosition(PlayerPedId(), false)
    showPrompt(scoreText(score))
    notify(('Fight for %s. First team to %d kills wins.'):format(tdm.teamLabel, score.limit), 'success')
end)

RegisterNetEvent('ofm_activities:tdm:score', function(score)
    if not tdm then return end
    tdm.score = score
    showPrompt(scoreText(score))
    if score.victim == GetPlayerServerId(PlayerId()) then
        notify(('Respawning in %d seconds.'):format(score.respawnSeconds))
    end
end)

RegisterNetEvent('ofm_activities:tdm:respawn', function(spawn, score)
    if not tdm or tdm.phase ~= 'running' then return end
    tdm.score = score or tdm.score
    placePlayer(spawn, false)
    showPrompt(scoreText(tdm.score))
end)

RegisterNetEvent('ofm_activities:tdm:restore', function(position, message, result)
    clearTdm(position)
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
    SetBlipSprite(blip, 84)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 0.9)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(config.name .. ' TDM')
    EndTextCommandSetBlipName(blip)

    while true do
        local sleep = 750
        if not tdm and not LocalPlayer.state.ofmActivity then
            local coords = GetEntityCoords(PlayerPedId())
            local range = #(coords - vec3(config.queue.x, config.queue.y, config.queue.z))
            if range < 30.0 then
                sleep = 0
                DrawMarker(1, config.queue.x, config.queue.y, config.queue.z - 1.0,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.5, 2.5, 0.5,
                    220, 50, 50, 170, false, false, 2, false)
            end
            if range < 2.5 then
                sleep = 0
                showPrompt(queued and '[E] Leave Terminal Clash queue' or '[E] Join Terminal Clash TDM')
                if IsControlJustReleased(0, 38) then
                    hidePrompt()
                    if queued then cancelTdm() else joinQueue() end
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
        if tdm then
            DisableControlAction(0, 244, true)
            DisableControlAction(0, 289, true)
            local ownGroup = teamGroup(tdm.team)
            for _, player in ipairs(GetActivePlayers()) do
                local serverId = GetPlayerServerId(player)
                local team = Player(serverId).state.ofmTdmTeam
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
    local response = lib.callback.await('ofm_activities:tdm:status', false)
    if response and response.queued then
        queued = true
        queueToken = response.token
    end
end)

AddEventHandler('QBCore:Client:OnPlayerUnload', function() clearTdm() end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then clearTdm() end
end)
