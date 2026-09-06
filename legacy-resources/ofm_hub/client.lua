local config = require 'config'
local open = false
local loadGeneration = 0

local function closeHub(markComplete)
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    TriggerScreenblurFadeOut(180)
    SendNUIMessage({ action = 'close' })
    if markComplete then
        CreateThread(function()
            lib.callback.await('ofm_hub:complete', false)
        end)
    end
end

local function openHub(page, onboarding)
    if open or not LocalPlayer.state.isLoggedIn then return end
    if LocalPlayer.state.ofmActivity then
        return lib.notify({ title = 'Open Freemode', description = 'Open the handbook after the current activity.', type = 'error' })
    end
    local data = exports.qbx_core:GetPlayerData()
    local charinfo = data and data.charinfo or {}
    open = true
    TriggerScreenblurFadeIn(180)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        page = page or 'handbook',
        onboarding = onboarding == true,
        playerName = charinfo.firstname or 'Player',
    })
end

RegisterNUICallback('close', function(data, callback)
    closeHub(data and data.complete == true)
    callback({ ok = true })
end)

RegisterNUICallback('waypoint', function(data, callback)
    local destination = data and type(data.id) == 'string' and config.destinations[data.id]
    if not destination then
        callback({ ok = false })
        return
    end
    SetNewWaypoint(destination.x, destination.y)
    closeHub(data.complete == true)
    lib.notify({
        title = 'Route set',
        description = ('GPS route set for %s. Enter its marker to begin.'):format(destination.label),
        type = 'success',
    })
    callback({ ok = true })
end)

RegisterCommand('guide', function() openHub('handbook', false) end, false)
RegisterCommand('activities', function() openHub('activities', false) end, false)
RegisterKeyMapping('guide', 'Open the Open Freemode handbook', 'keyboard', 'F7')

local function scheduleOnboarding()
    loadGeneration = loadGeneration + 1
    local generation = loadGeneration
    CreateThread(function()
        Wait(2500)
        for _ = 1, 45 do
            if generation ~= loadGeneration or not LocalPlayer.state.isLoggedIn then return end
            local status = lib.callback.await('ofm_hub:status', false)
            if status and status.ok and status.completed then return end
            if status and status.ok and status.appearanceReady and not LocalPlayer.state.ofmActivity then
                openHub('welcome', true)
                return
            end
            Wait(2000)
        end
    end)
end

AddEventHandler('QBCore:Client:OnPlayerLoaded', scheduleOnboarding)

AddEventHandler('QBCore:Client:OnPlayerUnload', function()
    loadGeneration = loadGeneration + 1
    closeHub(false)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then closeHub(false) end
end)

print('[ofm_hub] Handbook client ready. Use F7 or /guide.')
