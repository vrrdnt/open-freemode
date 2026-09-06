local config = require 'config'
local active
local routeBlip
local promptVisible = false
local submitting = false

local function notify(description, kind)
    lib.notify({ title = 'Pizza This...', description = description, type = kind or 'inform' })
end

local function hidePrompt()
    if promptVisible then
        lib.hideTextUI()
        promptVisible = false
    end
end

local function clearRoute()
    hidePrompt()
    if routeBlip then RemoveBlip(routeBlip) end
    routeBlip = nil
    active = nil
    submitting = false
end

local function updateRoute(session)
    active = session
    if routeBlip then RemoveBlip(routeBlip) end
    routeBlip = AddBlipForCoord(session.stop.x, session.stop.y, session.stop.z)
    SetBlipSprite(routeBlip, 1)
    SetBlipColour(routeBlip, 5)
    SetBlipRoute(routeBlip, true)
    SetBlipRouteColour(routeBlip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(('Pizza delivery %d/%d'):format(session.nextIndex, session.totalStops))
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
        return notify(response and response.message or 'The route could not be started.', 'error')
    end
    updateRoute(response.session)
    waitForVehicle(response.session.vehicleNetId)
    notify(('Deliver %d orders for $%d. Step off the scooter at each door.'):format(
        response.session.totalStops, response.payout), 'success')
end

local function completeStop()
    if not active or submitting then return end
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        return notify('Step off the scooter to deliver the pizza.', 'error')
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
        notify(response and response.message or 'The delivery was rejected.', 'error')
        if response and response.cancelled then clearRoute() end
        return
    end
    if response.completed then
        clearRoute()
        notify(('Route complete. $%d was deposited in your bank.'):format(response.payout), 'success')
    else
        updateRoute(response.session)
        notify(('Delivery complete. %d stop(s) remain.'):format(
            response.session.totalStops - response.session.nextIndex + 1), 'success')
    end
end

RegisterCommand('pizza_cancel', function()
    if not active then return notify('No pizza route is active.', 'error') end
    lib.callback.await('ofm_activities:cancel', false)
    clearRoute()
    notify('Pizza route cancelled.')
end, false)

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
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local target = active and active.stop or config.pizza.depot
        local range = #(coords - vec3(target.x, target.y, target.z))

        if range < 25.0 then
            sleep = 0
            DrawMarker(1, target.x, target.y, target.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                active and 1.5 or 1.2, active and 1.5 or 1.2, 0.35, 255, 176, 32, 165, false, false, 2, false)
        end
        if range < 2.0 and not submitting then
            sleep = 0
            if not promptVisible then
                lib.showTextUI(active and '[E] Deliver pizza' or '[E] Start pizza delivery')
                promptVisible = true
            end
            if IsControlJustReleased(0, 38) then
                hidePrompt()
                if active then completeStop() else startPizza() end
            end
        else
            hidePrompt()
        end

        if active and IsEntityDead(ped) then
            lib.callback.await('ofm_activities:cancel', false)
            clearRoute()
            notify('Pizza route cancelled because you died.', 'error')
        end
        Wait(sleep)
    end
end)

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    local response = lib.callback.await('ofm_activities:status', false)
    if response and response.session then updateRoute(response.session) end
end)

AddEventHandler('QBCore:Client:OnPlayerUnload', clearRoute)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then clearRoute() end
end)
