local config = require 'config'

assert(#config.race.publicGrid >= config.race.publicMaximumPlayers,
    'Airport Dash needs one grid slot per public racer')

math.randomseed(os.time())

local manager = ActivityState.new({
    now = os.time,
    token = function(source, kind)
        return ('%s:%d:%d:%06d'):format(kind, source, os.time(), math.random(0, 999999))
    end,
})
OFMActivityManager = manager
local raceRuns = {}
local raceQueue = ActivityQueue.new({
    minimum = config.race.publicMinimumPlayers,
    maximum = config.race.publicMaximumPlayers,
})
local matches = {}
local matchSequence = 0
local queueCountdown

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

local function broadcastQueueStatus(message)
    local size = raceQueue:size()
    for _, queuedSource in ipairs(raceQueue:sources()) do
        TriggerClientEvent('ofm_activities:race:queueStatus', queuedSource, size, message)
    end
end

local function restoreRace(source, run)
    if not run then return end
    if run.vehicle and DoesEntityExist(run.vehicle) then
        FreezeEntityPosition(run.vehicle, false)
        if run.previousVehicleBucket then
            exports.qbx_core:SetEntityBucket(run.vehicle, run.previousVehicleBucket)
        end
        if run.restoreVehicle then
            SetEntityCoords(run.vehicle, run.restoreVehicle.x, run.restoreVehicle.y, run.restoreVehicle.z,
                false, false, false, false)
            SetEntityHeading(run.vehicle, run.restoreVehicle.w)
        end
    end
    if run.previousPlayerBucket and GetPlayerName(source) then
        exports.qbx_core:SetPlayerBucket(source, run.previousPlayerBucket)
    end
end

local function leaveMatch(source, run)
    local match = run and run.matchId and matches[run.matchId]
    if not match then return end
    match.players[source] = nil
    if not next(match.players) then matches[run.matchId] = nil end
end

local function matchSources(match)
    local sources = {}
    for source in pairs(match.players) do sources[#sources + 1] = source end
    return sources
end

local function cancelActivity(source)
    if OFMCancelTdm and OFMCancelTdm(source) then return end
    local wasQueued = raceQueue:remove(source) ~= nil
    local run = raceRuns[source]
    restoreRace(source, run)
    leaveMatch(source, run)
    raceRuns[source] = nil
    cleanup(manager:cancel(source))
    if wasQueued then broadcastQueueStatus('Queue updated.') end
end

local function raceVehicle(source, expected, radius)
    local coords, ped = playerCoords(source)
    if not coords or (radius and distance(coords, config.race.start) > radius) then return nil end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or (expected and vehicle ~= expected) or GetPedInVehicleSeat(vehicle, -1) ~= ped then return nil end
    return vehicle
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
    not_active = 'No activity is active.',
    invalid_token = 'This delivery route is no longer valid.',
    wrong_stop = 'Deliveries must be completed in route order.',
    too_far = 'Move closer to the delivery door.',
    too_fast = 'That delivery was submitted too quickly.',
    vehicle_missing = 'The delivery vehicle was lost, so the route was cancelled.',
    vehicle_too_far = 'Bring the delivery vehicle closer before completing this stop.',
    leave_vehicle = 'Step off the scooter to deliver the pizza.',
    race_not_started = 'The race countdown has not finished.',
    race_vehicle_missing = 'Your race vehicle was lost, so the run was cancelled.',
    race_wrong_vehicle = 'Finish the race in the vehicle you started with.',
    race_driver = 'You must be driving the race vehicle.',
    already_queued = 'You are already waiting for a public race.',
    queue_full = 'The public race queue is full. Try the next race.',
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

local function startPublicCountdown(entries)
    matchSequence = matchSequence + 1
    local matchId = ('airport-dash:%d:%d'):format(os.time(), matchSequence)
    local bucket = config.race.publicBucketBase + matchSequence
    local match = { id = matchId, bucket = bucket, players = {}, finished = 0 }
    matches[matchId] = match
    SetRoutingBucketPopulationEnabled(bucket, false)

    local entrants = {}
    for index, entry in ipairs(entries) do
        local source = entry.source
        local run = raceRuns[source]
        local vehicle = run and raceVehicle(source, run.vehicle, config.race.publicStagingRadius)
        local slot = config.race.publicGrid[index]
        if run and run.phase == 'queued' and vehicle and slot then
            local original = GetEntityCoords(vehicle)
            run.phase = 'countdown'
            run.matchId = matchId
            run.previousPlayerBucket = GetPlayerRoutingBucket(source)
            run.previousVehicleBucket = GetEntityRoutingBucket(vehicle)
            run.restoreVehicle = { x = original.x, y = original.y, z = original.z, w = GetEntityHeading(vehicle) }
            match.players[source] = true
            FreezeEntityPosition(vehicle, true)
            exports.qbx_core:SetPlayerBucket(source, bucket)
            exports.qbx_core:SetEntityBucket(vehicle, bucket)
            SetEntityCoords(vehicle, slot.x, slot.y, slot.z, false, false, false, false)
            SetEntityHeading(vehicle, slot.w)
            entrants[#entrants + 1] = {
                source = source,
                run = run,
                slot = slot,
                vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle),
            }
        else
            cancelActivity(source)
            TriggerClientEvent('ofm_activities:race:cancelled', source, 'You left the staging area or vehicle.')
        end
    end

    if #entrants < config.race.publicMinimumPlayers then
        for _, source in ipairs(matchSources(match)) do
            cancelActivity(source)
            TriggerClientEvent('ofm_activities:race:cancelled', source, 'Not enough drivers remained for the public race.')
        end
        matches[matchId] = nil
        return
    end

    match.totalPlayers = #entrants
    local vehicleNetIds = {}
    for index, entrant in ipairs(entrants) do vehicleNetIds[index] = entrant.vehicleNetId end
    for _, entrant in ipairs(entrants) do
        local session = manager:status(entrant.source)
        session.name = config.race.name
        session.mode = 'public'
        session.phase = 'countdown'
        TriggerClientEvent('ofm_activities:race:countdown', entrant.source, session,
            config.race.publicCountdownSeconds, entrant.slot, vehicleNetIds)
    end

    SetTimeout(config.race.publicCountdownSeconds * 1000, function()
        local current = matches[matchId]
        if not current then return end
        local ready = {}
        for _, source in ipairs(matchSources(current)) do
            local run = raceRuns[source]
            if run and run.matchId == matchId and raceVehicle(source, run.vehicle) then
                ready[#ready + 1] = source
            else
                cancelActivity(source)
                TriggerClientEvent('ofm_activities:race:cancelled', source, 'You left the vehicle during the countdown.')
            end
        end

        if #ready < config.race.publicMinimumPlayers then
            for _, source in ipairs(ready) do
                cancelActivity(source)
                TriggerClientEvent('ofm_activities:race:cancelled', source, 'Not enough drivers remained for the public race.')
            end
            matches[matchId] = nil
            return
        end

        local startedAt = GetGameTimer()
        current.totalPlayers = #ready
        for _, source in ipairs(ready) do
            local run = raceRuns[source]
            run.phase = 'running'
            run.startedAt = startedAt
            run.restoreVehicle = nil
            FreezeEntityPosition(run.vehicle, false)
            TriggerClientEvent('ofm_activities:race:go', source, run.token, current.totalPlayers,
                config.race.publicGhostSeconds)
        end
    end)
end

local function schedulePublicRace()
    if queueCountdown or raceQueue:size() < config.race.publicMinimumPlayers then return end
    local countdown = { startsAt = GetGameTimer() + config.race.publicLobbySeconds * 1000 }
    queueCountdown = countdown
    broadcastQueueStatus(('Public race locks in %d seconds. Stay near the start.'):format(config.race.publicLobbySeconds))
    SetTimeout(config.race.publicLobbySeconds * 1000, function()
        if queueCountdown ~= countdown then return end
        queueCountdown = nil
        local entries = raceQueue:lock()
        if not entries then
            broadcastQueueStatus('Waiting for at least two drivers.')
            return
        end
        startPublicCountdown(entries)
    end)
end

lib.callback.register('ofm_activities:race:start', function(source)
    if not exports.qbx_core:GetPlayer(source) then
        return { ok = false, message = 'Load a character before starting a race.' }
    end
    local vehicle = raceVehicle(source, nil, config.race.startRadius)
    if not vehicle then return { ok = false, message = 'Enter the start marker in the driver seat of a vehicle.' } end

    local data, reason = manager:start(source, {
        kind = 'race',
        stops = config.race.checkpoints,
        payout = config.race.payout,
        radius = config.race.checkpointRadius,
        minimumStopSeconds = config.race.minimumCheckpointSeconds,
    })
    if not data then return { ok = false, message = errors[reason] } end

    FreezeEntityPosition(vehicle, true)
    raceRuns[source] = { token = data.token, vehicle = vehicle, mode = 'solo', phase = 'countdown' }
    SetTimeout(15000, function()
        local run = raceRuns[source]
        if run and run.token == data.token and not run.startedAt then cancelActivity(source) end
    end)
    data.name = config.race.name
    data.mode = 'solo'
    return { ok = true, session = data, payout = config.race.payout }
end)

lib.callback.register('ofm_activities:race:queue', function(source)
    if not exports.qbx_core:GetPlayer(source) then
        return { ok = false, message = 'Load a character before joining a race.' }
    end
    local vehicle = raceVehicle(source, nil, config.race.startRadius)
    if not vehicle then return { ok = false, message = 'Enter the start marker in the driver seat of a vehicle.' } end

    local data, reason = manager:start(source, {
        kind = 'race',
        stops = config.race.checkpoints,
        payout = 0,
        radius = config.race.checkpointRadius,
        minimumStopSeconds = config.race.minimumCheckpointSeconds,
    })
    if not data then return { ok = false, message = errors[reason] } end

    local position, queueReason = raceQueue:join(source, { vehicle = vehicle, token = data.token })
    if not position then
        manager:cancel(source)
        return { ok = false, message = errors[queueReason] }
    end
    raceRuns[source] = { token = data.token, vehicle = vehicle, mode = 'public', phase = 'queued' }
    schedulePublicRace()
    broadcastQueueStatus()
    return {
        ok = true,
        token = data.token,
        position = position,
        size = raceQueue:size(),
        launchInMs = queueCountdown and math.max(0, queueCountdown.startsAt - GetGameTimer()) or nil,
    }
end)

lib.callback.register('ofm_activities:race:begin', function(source, token)
    local session = manager:get(source)
    local run = raceRuns[source]
    if not session or session.kind ~= 'race' or not run or run.mode ~= 'solo'
        or token ~= session.token or token ~= run.token then
        cancelActivity(source)
        return { ok = false, cancelled = true, message = errors.invalid_token }
    end
    if not raceVehicle(source, run.vehicle, config.race.startRadius) then
        cancelActivity(source)
        return { ok = false, cancelled = true, message = 'Stay in the driver seat at the start marker.' }
    end

    run.phase = 'running'
    run.startedAt = GetGameTimer()
    FreezeEntityPosition(run.vehicle, false)
    return { ok = true }
end)

lib.callback.register('ofm_activities:race:checkpoint', function(source, token, index)
    local session = manager:get(source)
    local run = raceRuns[source]
    if not session or session.kind ~= 'race' or not run then
        return { ok = false, cancelled = true, message = errors.not_active }
    end
    if token ~= session.token or token ~= run.token then
        return { ok = false, message = errors.invalid_token }
    end
    if not run.startedAt then return { ok = false, message = errors.race_not_started } end
    if not DoesEntityExist(run.vehicle) then
        cancelActivity(source)
        return { ok = false, cancelled = true, message = errors.race_vehicle_missing }
    end

    local coords, ped = playerCoords(source)
    if not coords then return { ok = false, message = errors.too_far } end
    if GetVehiclePedIsIn(ped, false) ~= run.vehicle then
        return { ok = false, message = errors.race_wrong_vehicle }
    end
    if GetPedInVehicleSeat(run.vehicle, -1) ~= ped then
        return { ok = false, message = errors.race_driver }
    end

    local checkpoint = session.stops[session.nextIndex]
    local data, reason = manager:advance(source, token, index, distance(coords, checkpoint))
    if not data then return { ok = false, message = errors[reason] or 'Checkpoint rejected.' } end
    if not data.completed then
        data.name = config.race.name
        data.mode = run.mode
        return { ok = true, session = data }
    end

    local elapsed = GetGameTimer() - run.startedAt
    local raceId = config.race.id
    local payout = data.payout
    local finishPlace
    local totalPlayers
    if run.mode == 'public' then
        local match = matches[run.matchId]
        if not match then
            cancelActivity(source)
            return { ok = false, cancelled = true, message = 'The public race is no longer active.' }
        end
        match.finished = match.finished + 1
        finishPlace = match.finished
        totalPlayers = match.totalPlayers
        payout = config.race.publicPayouts[finishPlace] or config.race.publicFinisherPayout
        raceId = config.race.id .. '_public'
    end

    restoreRace(source, run)
    leaveMatch(source, run)
    raceRuns[source] = nil
    local player = exports.qbx_core:GetPlayer(source)
    if not player then
        return { ok = false, cancelled = true, message = 'Character session ended before the result was saved.' }
    end

    local inserted = MySQL.update.await(
        'INSERT IGNORE INTO ofm_race_results (result_id, citizenid, race_id, elapsed_ms, payout) VALUES (?, ?, ?, ?, ?)',
        { data.token, player.PlayerData.citizenid, raceId, elapsed, payout }
    )
    if inserted ~= 1 then
        return { ok = false, cancelled = true, message = 'This race result was already recorded.' }
    end
    if not exports.qbx_core:AddMoney(source, 'bank', payout, 'airport-dash-race') then
        MySQL.update.await('DELETE FROM ofm_race_results WHERE result_id = ?', { data.token })
        return { ok = false, cancelled = true, message = 'Payment failed; no race result was recorded.' }
    end

    local personalBest = MySQL.scalar.await(
        'SELECT MIN(elapsed_ms) FROM ofm_race_results WHERE citizenid = ? AND race_id = ?',
        { player.PlayerData.citizenid, raceId }
    )
    local leaderboardRank = MySQL.scalar.await([[
        SELECT COUNT(*) + 1 FROM (
            SELECT citizenid, MIN(elapsed_ms) AS best
            FROM ofm_race_results WHERE race_id = ? GROUP BY citizenid
        ) AS ranked WHERE best < ?
    ]], { raceId, personalBest })
    return {
        ok = true,
        completed = true,
        mode = run.mode,
        elapsedMs = elapsed,
        personalBestMs = personalBest,
        leaderboardRank = leaderboardRank,
        finishPlace = finishPlace,
        totalPlayers = totalPlayers,
        payout = payout,
    }
end)

lib.callback.register('ofm_activities:status', function(source)
    local session = manager:status(source)
    if session and session.kind == 'race' then
        local run = raceRuns[source]
        session.name = config.race.name
        session.mode = run and run.mode
        session.phase = run and run.phase
        session.started = run and run.startedAt ~= nil
    end
    return { ok = true, session = session }
end)

lib.callback.register('ofm_activities:cancel', function(source)
    cancelActivity(source)
    return { ok = true }
end)

AddEventHandler('playerDropped', function()
    cancelActivity(source)
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(source)
    cancelActivity(source)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    local sources = {}
    for source in manager:all() do sources[#sources + 1] = source end
    for _, source in ipairs(sources) do cancelActivity(source) end
end)

exports('GetActivity', function(source)
    return manager:status(source)
end)

exports('CancelActivity', function(source)
    cancelActivity(source)
end)

print('[ofm_activities] Pizza delivery and solo/public Airport Dash racing ready.')
