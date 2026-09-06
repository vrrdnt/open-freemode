local config = require 'config'
local active
local routeBlip
local promptOwner
local submitting = false

local function notify(title, description, kind)
    lib.notify({ title = title, description = description, type = kind or 'inform' })
end

local function showPrompt(owner, text)
    if promptOwner == owner then return end
    if promptOwner then lib.hideTextUI() end
    lib.showTextUI(text)
    promptOwner = owner
end

local function hidePrompt(owner)
    if promptOwner == owner then
        lib.hideTextUI()
        promptOwner = nil
    end
end

local function clearActivity()
    if promptOwner then lib.hideTextUI() end
    promptOwner = nil
    if routeBlip then RemoveBlip(routeBlip) end
    routeBlip = nil
    active = nil
    submitting = false
end

local function updateRoute(session)
    active = session
    if routeBlip then RemoveBlip(routeBlip) end
    routeBlip = AddBlipForCoord(session.stop.x, session.stop.y, session.stop.z)
    SetBlipSprite(routeBlip, session.kind == 'race' and 38 or 1)
    SetBlipColour(routeBlip, session.kind == 'race' and 46 or 5)
    SetBlipRoute(routeBlip, true)
    SetBlipRouteColour(routeBlip, session.kind == 'race' and 46 or 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(session.kind == 'race'
        and ('%s checkpoint %d/%d'):format(session.name, session.nextIndex, session.totalStops)
        or ('Pizza delivery %d/%d'):format(session.nextIndex, session.totalStops))
    EndTextCommandSetBlipName(routeBlip)
end

local function waitForVehicle(netId)
    local deadline = GetGameTimer() + 10000
    while not NetworkDoesEntityExistWithNetworkId(netId) and GetGameTimer() < deadline do Wait(50) end
    if not NetworkDoesEntityExistWithNetworkId(netId) then return end
    local vehicle = NetToVeh(netId)
    SetEntityAsMissionEntity(vehicle, true, true)
    TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
    SetVehicleEngineOn(vehicle, true, true, false)
end

local function startPizza()
    if active or submitting then return end
    submitting = true
    local response = lib.callback.await('ofm_activities:pizza:start', false)
    submitting = false
    if not response or not response.ok then
        return notify('Pizza This...', response and response.message or 'The route could not be started.', 'error')
    end
    updateRoute(response.session)
    waitForVehicle(response.session.vehicleNetId)
    notify('Pizza This...', ('Deliver %d orders for $%d. Step off the scooter at each door.'):format(
        response.session.totalStops, response.payout), 'success')
end

local function completePizzaStop()
    if not active or active.kind ~= 'pizza' or submitting then return end
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        return notify('Pizza This...', 'Step off the scooter to deliver the pizza.', 'error')
    end
    if not lib.progressCircle({
        duration = 2500,
        label = 'Delivering pizza',
        position = 'bottom',
        canCancel = true,
        disable = { move = true, combat = true, car = true },
        anim = { dict = 'timetable@jimmy@doorknock@', clip = 'knockdoor_idle' },
    }) then return end

    submitting = true
    local response = lib.callback.await('ofm_activities:pizza:complete', false, active.token, active.nextIndex)
    submitting = false
    if not response or not response.ok then
        notify('Pizza This...', response and response.message or 'The delivery was rejected.', 'error')
        if response and response.cancelled then clearActivity() end
        return
    end
    if response.completed then
        clearActivity()
        notify('Pizza This...', ('$%d was deposited in your bank.'):format(response.payout), 'success')
    else
        updateRoute(response.session)
        notify('Pizza This...', ('Delivery complete. %d stop(s) remain.'):format(
            response.session.totalStops - response.session.nextIndex + 1), 'success')
    end
end

local function formatTime(milliseconds)
    local minutes = math.floor(milliseconds / 60000)
    local seconds = (milliseconds % 60000) / 1000
    return ('%d:%06.3f'):format(minutes, seconds)
end

local function startRace()
    if active or submitting then return end
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then
        return notify('Airport Dash', 'Enter the driver seat of a vehicle before starting.', 'error')
    end

    submitting = true
    local response = lib.callback.await('ofm_activities:race:start', false)
    if not response or not response.ok then
        submitting = false
        return notify('Airport Dash', response and response.message or 'The race could not be started.', 'error')
    end
    updateRoute(response.session)
    active.started = false
    local token = active.token
    for count = 3, 1, -1 do
        showPrompt('countdown', ('Airport Dash starts in %d'):format(count))
        Wait(1000)
        if not active or active.token ~= token then return end
    end
    hidePrompt('countdown')

    local begun = lib.callback.await('ofm_activities:race:begin', false, token)
    submitting = false
    if not begun or not begun.ok then
        notify('Airport Dash', begun and begun.message or 'The race start was cancelled.', 'error')
        return clearActivity()
    end
    active.started = true
    notify('Airport Dash', ('GO! Finish for $%d.'):format(response.payout), 'success')
end

local function completeRaceCheckpoint()
    if not active or active.kind ~= 'race' or not active.started or submitting then return end
    submitting = true
    local response = lib.callback.await('ofm_activities:race:checkpoint', false, active.token, active.nextIndex)
    submitting = false
    if not response or not response.ok then
        notify('Airport Dash', response and response.message or 'The checkpoint was rejected.', 'error')
        if response and response.cancelled then clearActivity() end
        return
    end
    if response.completed then
        clearActivity()
        notify('Airport Dash', ('Finished in %s · personal best %s · rank #%d · $%d banked.'):format(
            formatTime(response.elapsedMs), formatTime(response.personalBestMs), response.leaderboardRank, response.payout), 'success')
    else
        updateRoute(response.session)
    end
end

local function cancelCurrent(expectedKind)
    if not active or expectedKind and active.kind ~= expectedKind then
        return notify('Activities', 'No matching activity is active.', 'error')
    end
    lib.callback.await('ofm_activities:cancel', false)
    local kind = active.kind
    clearActivity()
    notify('Activities', kind == 'race' and 'Race cancelled.' or 'Pizza route cancelled.')
end

RegisterCommand('pizza_cancel', function() cancelCurrent('pizza') end, false)
RegisterCommand('race_cancel', function() cancelCurrent('race') end, false)

CreateThread(function()
    local blip = AddBlipForCoord(config.pizza.depot.x, config.pizza.depot.y, config.pizza.depot.z)
    SetBlipSprite(blip, 267)
    SetBlipColour(blip, 5)
    SetBlipScale(blip, 0.85)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Pizza Delivery')
    EndTextCommandSetBlipName(blip)

    while true do
        local sleep = 750
        if not active or active.kind == 'pizza' then
            local coords = GetEntityCoords(PlayerPedId())
            local target = active and active.stop or config.pizza.depot
            local range = #(coords - vec3(target.x, target.y, target.z))
            if range < 25.0 then
                sleep = 0
                DrawMarker(1, target.x, target.y, target.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    active and 1.5 or 1.2, active and 1.5 or 1.2, 0.35, 255, 176, 32, 165, false, false, 2, false)
            end
            if range < 2.0 and not submitting then
                sleep = 0
                showPrompt('pizza', active and '[E] Deliver pizza' or '[E] Start pizza delivery')
                if IsControlJustReleased(0, 38) then
                    hidePrompt('pizza')
                    if active then completePizzaStop() else startPizza() end
                end
            else
                hidePrompt('pizza')
            end
        else
            hidePrompt('pizza')
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    local start = config.race.start
    local blip = AddBlipForCoord(start.x, start.y, start.z)
    SetBlipSprite(blip, 315)
    SetBlipColour(blip, 46)
    SetBlipScale(blip, 0.9)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(config.race.name)
    EndTextCommandSetBlipName(blip)

    while true do
        local sleep = 500
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        if not active then
            local range = #(coords - vec3(start.x, start.y, start.z))
            if range < 35.0 then
                sleep = 0
                DrawMarker(1, start.x, start.y, start.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    3.0, 3.0, 0.5, 60, 180, 255, 180, false, false, 2, false)
            end
            if range < 3.0 and not submitting then
                showPrompt('race', '[E] Start Airport Dash in your current vehicle')
                if IsControlJustReleased(0, 38) then
                    hidePrompt('race')
                    startRace()
                end
            else
                hidePrompt('race')
            end
        elseif active.kind == 'race' then
            hidePrompt('race')
            local target = active.stop
            local range = #(coords - vec3(target.x, target.y, target.z))
            if range < 120.0 then
                sleep = 0
                DrawMarker(1, target.x, target.y, target.z - 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    config.race.checkpointRadius * 2.0, config.race.checkpointRadius * 2.0, 4.0,
                    60, 180, 255, 120, false, false, 2, false)
            end
            if active.started and range <= config.race.checkpointRadius then completeRaceCheckpoint() end
        else
            hidePrompt('race')
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        Wait(500)
        if active and IsEntityDead(PlayerPedId()) then
            local kind = active.kind
            lib.callback.await('ofm_activities:cancel', false)
            clearActivity()
            notify('Activities', kind == 'race' and 'Race cancelled because you died.'
                or 'Pizza route cancelled because you died.', 'error')
        end
    end
end)

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    local response = lib.callback.await('ofm_activities:status', false)
    if response and response.session then
        if response.session.kind == 'race' and not response.session.started then
            lib.callback.await('ofm_activities:cancel', false)
        else
            updateRoute(response.session)
            if active.kind == 'race' then active.started = true end
        end
    end
end)

AddEventHandler('QBCore:Client:OnPlayerUnload', clearActivity)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then clearActivity() end
end)
