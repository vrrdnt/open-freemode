local config = require 'config'

math.randomseed(os.time())

local manager = ActivityState.new({
    now = os.time,
    token = function(source, kind)
        return ('%s:%d:%d:%06d'):format(kind, source, os.time(), math.random(0, 999999))
    end,
})

local function distance(a, b)
    local x, y, z = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(x * x + y * y + z * z)
end

local function playerCoords(source)
    local ped = GetPlayerPed(source)
    if ped == 0 then return nil, nil end
    return GetEntityCoords(ped), ped
end

local function deleteVehicle(entity)
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
end

local function cleanup(session)
    if session then deleteVehicle(session.vehicle) end
end

local function selectStops(pool, count)
    local available = {}
    for index, stop in ipairs(pool) do available[index] = stop end
    for index = #available, 2, -1 do
        local swap = math.random(index)
        available[index], available[swap] = available[swap], available[index]
    end
    local selected = {}
    for index = 1, math.min(count, #available) do selected[index] = available[index] end
    return selected
end

local errors = {
    already_active = 'Finish or cancel your current activity first.',
    not_active = 'No pizza route is active.',
    invalid_token = 'This delivery route is no longer valid.',
    wrong_stop = 'Deliveries must be completed in route order.',
    too_far = 'Move closer to the delivery door.',
    too_fast = 'That delivery was submitted too quickly.',
    vehicle_missing = 'The delivery vehicle was lost, so the route was cancelled.',
    vehicle_too_far = 'Bring the delivery vehicle closer before completing this stop.',
    leave_vehicle = 'Step off the scooter to deliver the pizza.',
}

lib.callback.register('ofm_activities:pizza:start', function(source)
    if not exports.qbx_core:GetPlayer(source) then
        return { ok = false, message = 'Load a character before starting a route.' }
    end

    local coords, ped = playerCoords(source)
    if not coords or distance(coords, config.pizza.depot) > 6.0 then
        return { ok = false, message = 'Start pizza delivery at the restaurant.' }
    end

    local data, reason = manager:start(source, {
        kind = 'pizza',
        stops = selectStops(config.pizza.stops, config.pizza.stopCount),
        payout = config.pizza.payout,
        radius = config.pizza.stopRadius,
        minimumStopSeconds = config.pizza.minimumStopSeconds,
    })
    if not data then return { ok = false, message = errors[reason] } end

    local spawn = config.pizza.vehicleSpawn
    local vehicle = CreateVehicleServerSetter(joaat(config.pizza.vehicleModel), 'bike', spawn.x, spawn.y, spawn.z, spawn.w)
    local deadline = GetGameTimer() + 5000
    while vehicle ~= 0 and not DoesEntityExist(vehicle) and GetGameTimer() < deadline do Wait(0) end
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        manager:cancel(source)
        return { ok = false, message = 'The delivery scooter could not be created. Try again.' }
    end

    SetEntityOrphanMode(vehicle, 2)
    Entity(vehicle).state:set('ofmActivity', 'pizza', true)
    Entity(vehicle).state:set('ofmActivityOwner', source, true)
    pcall(SetVehicleNumberPlateText, vehicle, ('PZA%05d'):format(source % 100000))
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    manager:setVehicle(source, vehicle, netId)
    data.vehicleNetId = netId
    return { ok = true, session = data, payout = config.pizza.payout }
end)

lib.callback.register('ofm_activities:pizza:complete', function(source, token, index)
    local session = manager:get(source)
    if not session then return { ok = false, message = errors.not_active } end
    if not session.vehicle or not DoesEntityExist(session.vehicle) then
        cleanup(manager:cancel(source))
        return { ok = false, cancelled = true, message = errors.vehicle_missing }
    end

    local coords, ped = playerCoords(source)
    if not coords then return { ok = false, message = errors.too_far } end
    if GetVehiclePedIsIn(ped, false) ~= 0 then
        return { ok = false, message = errors.leave_vehicle }
    end
    if distance(coords, GetEntityCoords(session.vehicle)) > config.pizza.vehicleLeash then
        return { ok = false, message = errors.vehicle_too_far }
    end

    local stop = session.stops[session.nextIndex]
    local data, reason = manager:advance(source, token, index, distance(coords, stop))
    if not data then return { ok = false, message = errors[reason] or 'Delivery rejected.' } end
    if not data.completed then return { ok = true, session = data } end

    local player = exports.qbx_core:GetPlayer(source)
    if not player then
        cleanup(data)
        return { ok = false, cancelled = true, message = 'Character session ended before payment.' }
    end

    local inserted = MySQL.update.await(
        'INSERT IGNORE INTO ofm_activity_results (result_id, citizenid, activity, payout) VALUES (?, ?, ?, ?)',
        { data.token, player.PlayerData.citizenid, data.kind, data.payout }
    )
    if inserted ~= 1 then
        cleanup(data)
        return { ok = false, cancelled = true, message = 'This route was already paid.' }
    end
    if not exports.qbx_core:AddMoney(source, 'bank', data.payout, 'pizza-delivery') then
        MySQL.update.await('DELETE FROM ofm_activity_results WHERE result_id = ?', { data.token })
        cleanup(data)
        return { ok = false, cancelled = true, message = 'Payment failed; no route result was recorded.' }
    end

    cleanup(data)
    return { ok = true, completed = true, payout = data.payout }
end)

lib.callback.register('ofm_activities:status', function(source)
    return { ok = true, session = manager:status(source) }
end)

lib.callback.register('ofm_activities:cancel', function(source)
    cleanup(manager:cancel(source))
    return { ok = true }
end)

AddEventHandler('playerDropped', function()
    cleanup(manager:cancel(source))
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(source)
    cleanup(manager:cancel(source))
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, session in manager:all() do cleanup(session) end
end)

exports('GetActivity', function(source)
    return manager:status(source)
end)

exports('CancelActivity', function(source)
    cleanup(manager:cancel(source))
end)

print('[ofm_activities] Pizza delivery ready.')
