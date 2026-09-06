local config = require 'config'.pursuit

assert(#config.cops.vehicleSpawns >= config.maximumPlayers - 1,
    'City Escape needs one police vehicle spawn per possible cop')

local queue = ActivityQueue.new({
    minimum = config.minimumPlayers,
    maximum = config.maximumPlayers,
})
local members = {}
local matches = {}
local matchSequence = 0
local lobbyTicket

local function now()
    return GetGameTimer() / 1000
end

local function distance(a, b)
    local x, y, z = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(x * x + y * y + z * z)
end

local function playerPosition(source)
    local ped = GetPlayerPed(source)
    if ped == 0 then return nil, nil end
    return GetEntityCoords(ped), ped
end

local function deleteVehicle(vehicle)
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
end

local function createVehicle(model, spawn, bucket, owner, team)
    local vehicle = CreateVehicleServerSetter(joaat(model), 'automobile', spawn.x, spawn.y, spawn.z, spawn.w)
    local deadline = GetGameTimer() + 5000
    while vehicle ~= 0 and not DoesEntityExist(vehicle) and GetGameTimer() < deadline do Wait(0) end
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil end

    SetEntityRoutingBucket(vehicle, bucket)
    pcall(SetEntityOrphanMode, vehicle, 2)
    pcall(SetVehicleNumberPlateText, vehicle,
        team == 'robber' and ('RUN%05d'):format(owner % 100000) or ('OFC%05d'):format(owner % 100000))
    Entity(vehicle).state:set('ofmActivity', config.id, true)
    Entity(vehicle).state:set('ofmActivityOwner', owner, true)
    return vehicle, NetworkGetNetworkIdFromEntity(vehicle)
end

local function sourcesOf(match)
    local sources = {}
    for source in pairs(match.state.players) do sources[#sources + 1] = source end
    return sources
end

local function queueStatus(message)
    local size = queue:size()
    for _, source in ipairs(queue:sources()) do
        TriggerClientEvent('ofm_activities:pursuit:queueStatus', source, size, message)
    end
end

local function releasePlayer(source, message, result)
    local online = GetPlayerName(source) ~= nil
    local wasQueued = queue:remove(source) ~= nil
    local member = members[source]
    local match = member and member.matchId and matches[member.matchId]
    if match then match.state:removePlayer(source) end

    if member then
        deleteVehicle(member.vehicle)
        if member.previousBucket ~= nil and online then
            exports.qbx_core:SetPlayerBucket(source, member.previousBucket)
        end
        if online then Player(source).state:set('ofmPursuitTeam', nil, true) end
        members[source] = nil
    end
    OFMActivityManager:cancel(source)

    if online then
        TriggerClientEvent('ofm_activities:pursuit:restore', source,
            member and member.returnPosition or nil, message, result)
    end
    if wasQueued then queueStatus('Queue updated.') end
    return match
end

local function recordResult(source, match, player, winner)
    local qbxPlayer = exports.qbx_core:GetPlayer(source)
    if not qbxPlayer then return nil end

    local won = player.team == winner
    local payout = won and config.winnerPayout or config.loserPayout
    local resultId = ('%s:%s'):format(match.id, qbxPlayer.PlayerData.citizenid)
    local inserted = MySQL.update.await([[
        INSERT IGNORE INTO ofm_match_results
            (result_id, match_id, citizenid, activity, team, kills, deaths, won, payout)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        resultId,
        match.id,
        qbxPlayer.PlayerData.citizenid,
        config.id,
        player.team,
        player.kills,
        player.deaths,
        won and 1 or 0,
        payout,
    })
    if inserted ~= 1 then return nil end

    if not exports.qbx_core:AddMoney(source, 'bank', payout, 'city-escape-pursuit') then
        MySQL.update.await('DELETE FROM ofm_match_results WHERE result_id = ?', { resultId })
        return nil
    end
    return { won = won, payout = payout, kills = player.kills, deaths = player.deaths }
end

local function finishMatch(match, winner, reason)
    if not match or match.phase == 'ended' then return end
    match.phase = 'ended'
    match.state.phase = 'ended'
    local participants = {}
    for _, source in ipairs(sourcesOf(match)) do
        participants[#participants + 1] = { source = source, player = match.state.players[source] }
    end

    for _, participant in ipairs(participants) do
        local result = winner and recordResult(participant.source, match, participant.player, winner) or nil
        releasePlayer(participant.source, reason, result)
    end
    matches[match.id] = nil
end

local function checkEmptyTeam(match)
    if not match or match.phase == 'ended' then return end
    if match.state:teamCount('robber') == 0 or match.state:teamCount('cops') == 0 then
        finishMatch(match, nil, 'City Escape cancelled because a team became empty.')
    end
end

local function respawnCop(source, matchId)
    local match = matches[matchId]
    local member = members[source]
    local player = match and match.state.players[source]
    if not match or match.phase ~= 'running' or not member or not player or not player.dead then return end

    local spawn = config.cops.vehicleSpawns[member.spawnIndex]
    local vehicle, netId = createVehicle(config.cops.vehicleModel, spawn, match.bucket, source, 'cops')
    if not vehicle then
        finishMatch(match, nil, 'City Escape cancelled because a police vehicle could not respawn.')
        return
    end
    match.state:respawn(source)
    member.vehicle = vehicle
    member.vehicleNetId = netId
    TriggerClientEvent('ofm_activities:pursuit:respawn', source, {
        spawn = spawn,
        vehicleNetId = netId,
        loadout = config.cops.loadout,
        armor = config.cops.armor,
    })
end

local function processDeath(victim, killer)
    local member = members[victim]
    local match = member and member.matchId and matches[member.matchId]
    local victimState = match and match.state.players[victim]
    if not match or match.phase ~= 'running' or not victimState or victimState.dead then return end

    SetTimeout(100, function()
        member = members[victim]
        match = member and member.matchId and matches[member.matchId]
        victimState = match and match.state.players[victim]
        if not match or match.phase ~= 'running' or not victimState or victimState.dead then return end

        local victimCoords, victimPed = playerPosition(victim)
        if not victimPed or GetEntityHealth(victimPed) > 0 then return end
        local credited
        killer = tonumber(killer)
        local killerMember = killer and members[killer]
        local killerState = killerMember and killerMember.matchId == match.id and match.state.players[killer]
        if killerState and killer ~= victim and killerState.team ~= victimState.team then
            local killerCoords = playerPosition(killer)
            if killerCoords and victimCoords and distance(killerCoords, victimCoords) <= config.maximumKillDistance then
                credited = killer
            end
        end

        local result = match.state:recordDeath(victim, credited)
        if not result then return end
        if result.winner then
            finishMatch(match, result.winner, 'Police stopped the getaway.')
            return
        end

        deleteVehicle(member.vehicle)
        member.vehicle = nil
        member.vehicleNetId = nil
        TriggerClientEvent('ofm_activities:pursuit:copDown', victim, config.respawnSeconds)
        SetTimeout(config.respawnSeconds * 1000, function() respawnCop(victim, match.id) end)
    end)
end

local function monitorMatch(matchId)
    SetTimeout(1000, function()
        local match = matches[matchId]
        if not match or match.phase ~= 'running' then return end

        local winner = match.state:timeout()
        if winner then
            finishMatch(match, winner, 'Time expired before the robber escaped.')
            return
        end

        local robber = members[match.robber]
        local vehicle = robber and robber.vehicle
        if not vehicle or not DoesEntityExist(vehicle) or GetEntityHealth(vehicle) <= 0 then
            finishMatch(match, 'cops', 'Police destroyed the getaway vehicle.')
            return
        end
        monitorMatch(matchId)
    end)
end

local function startMatch(entries)
    matchSequence = matchSequence + 1
    local matchId = ('city-escape:%d:%d'):format(os.time(), matchSequence)
    local bucket = config.bucketBase + matchSequence
    local match = {
        id = matchId,
        bucket = bucket,
        phase = 'countdown',
        state = PursuitState.new({
            now = now,
            checkpointCount = #config.checkpoints,
            checkpointRadius = config.checkpointRadius,
            minimumCheckpointSeconds = config.minimumCheckpointSeconds,
        }),
    }
    matches[matchId] = match
    SetRoutingBucketPopulationEnabled(bucket, false)

    local valid = {}
    for _, entry in ipairs(entries) do
        local source = entry.source
        local member = members[source]
        local coords, ped = playerPosition(source)
        local session = OFMActivityManager:get(source)
        if member and member.phase == 'queued' and session and session.token == member.token
            and coords and distance(coords, config.queue) <= config.queueRadius
            and GetVehiclePedIsIn(ped, false) == 0 then
            valid[#valid + 1] = { source = source, member = member, coords = coords, ped = ped }
        else
            releasePlayer(source, 'You left the City Escape queue area or entered a vehicle.')
        end
    end

    if #valid < config.minimumPlayers then
        for _, entry in ipairs(valid) do
            releasePlayer(entry.source, 'Not enough players remained to start City Escape.')
        end
        matches[matchId] = nil
        return
    end

    for index, entry in ipairs(valid) do
        local source, member = entry.source, entry.member
        local team = index == 1 and 'robber' or 'cops'
        local spawnIndex = team == 'cops' and index - 1 or 1
        local role = config[team]
        local spawn = team == 'robber' and role.vehicleSpawn or role.vehicleSpawns[spawnIndex]
        local vehicle, netId = createVehicle(role.vehicleModel, spawn, bucket, source, team)
        if not vehicle then
            for _, activeSource in ipairs(sourcesOf(match)) do
                releasePlayer(activeSource, 'City Escape could not create every activity vehicle.')
            end
            for remaining = index, #valid do
                releasePlayer(valid[remaining].source, 'City Escape could not create every activity vehicle.')
            end
            matches[matchId] = nil
            return
        end

        member.phase = 'countdown'
        member.matchId = matchId
        member.team = team
        member.spawnIndex = spawnIndex
        member.previousBucket = GetPlayerRoutingBucket(source)
        member.returnPosition = {
            x = entry.coords.x, y = entry.coords.y, z = entry.coords.z, w = GetEntityHeading(entry.ped),
        }
        member.vehicle = vehicle
        member.vehicleNetId = netId
        match.state:addPlayer(source, team)
        if team == 'robber' then match.robber = source end
        exports.qbx_core:SetPlayerBucket(source, bucket)
        Player(source).state:set('ofmPursuitTeam', team, true)
    end

    for _, entry in ipairs(valid) do
        local member = members[entry.source]
        local role = config[member.team]
        TriggerClientEvent('ofm_activities:pursuit:prepare', entry.source, {
            token = member.token,
            name = config.name,
            team = member.team,
            teamLabel = role.label,
            vehicleNetId = member.vehicleNetId,
            vehicleSpawn = member.team == 'robber' and role.vehicleSpawn or role.vehicleSpawns[member.spawnIndex],
            countdownSeconds = config.countdownSeconds,
            durationSeconds = config.durationSeconds,
            loadout = role.loadout,
            armor = role.armor,
            robber = match.robber,
            totalCheckpoints = #config.checkpoints,
        })
    end

    SetTimeout(config.countdownSeconds * 1000, function()
        local current = matches[matchId]
        if not current or current.phase ~= 'countdown' then return end
        current.phase = 'running'
        current.state:start(config.durationSeconds)
        for source in pairs(current.state.players) do
            local member = members[source]
            if member then member.phase = 'running' end
            TriggerClientEvent('ofm_activities:pursuit:start', source, config.durationSeconds)
        end
        monitorMatch(matchId)
    end)
end

local function scheduleMatch()
    if lobbyTicket or queue:size() < config.minimumPlayers then return end
    local ticket = {}
    lobbyTicket = ticket
    queueStatus(('City Escape lobby locks in %d seconds. Stay on foot in the marker.'):format(config.lobbySeconds))
    SetTimeout(config.lobbySeconds * 1000, function()
        if lobbyTicket ~= ticket then return end
        lobbyTicket = nil
        local entries = queue:lock()
        if entries then startMatch(entries) else queueStatus('Waiting for at least two players.') end
    end)
end

lib.callback.register('ofm_activities:pursuit:join', function(source)
    if not exports.qbx_core:GetPlayer(source) then
        return { ok = false, message = 'Load a character before joining City Escape.' }
    end
    local coords, ped = playerPosition(source)
    if not coords or distance(coords, config.queue) > config.queueRadius then
        return { ok = false, message = 'Enter the City Escape marker first.' }
    end
    if GetVehiclePedIsIn(ped, false) ~= 0 then
        return { ok = false, message = 'Leave your vehicle before joining City Escape.' }
    end

    local reservation, reason = OFMActivityManager:reserve(source, 'pursuit')
    if not reservation then
        return { ok = false, message = reason == 'already_active' and 'Finish or cancel your current activity first.'
            or 'City Escape could not be reserved.' }
    end
    local position, queueReason = queue:join(source, { token = reservation.token })
    if not position then
        OFMActivityManager:cancel(source)
        return { ok = false, message = queueReason == 'queue_full' and 'The City Escape queue is full.'
            or 'You are already queued.' }
    end
    members[source] = { token = reservation.token, phase = 'queued' }
    scheduleMatch()
    queueStatus()
    return { ok = true, token = reservation.token, position = position }
end)

lib.callback.register('ofm_activities:pursuit:checkpoint', function(source, token, index)
    local member = members[source]
    local match = member and member.matchId and matches[member.matchId]
    if not member or member.token ~= token or member.team ~= 'robber' or not match or match.phase ~= 'running' then
        return { ok = false, message = 'No active getaway accepted that checkpoint.' }
    end
    local checkpoint = config.checkpoints[index]
    local coords, ped = playerPosition(source)
    local vehicle = member.vehicle
    if not checkpoint or not coords or not vehicle or not DoesEntityExist(vehicle) then
        return { ok = false, message = 'The getaway vehicle is unavailable.' }
    end
    local isDriver = GetVehiclePedIsIn(ped, false) == vehicle and GetPedInVehicleSeat(vehicle, -1) == ped
    local progress, reason = match.state:checkpoint(source, index, distance(coords, checkpoint), isDriver)
    if not progress then
        local messages = {
            wrong_checkpoint = 'Follow the escape checkpoints in order.',
            not_driver = 'Drive the assigned getaway vehicle through the checkpoint.',
            too_far = 'Move inside the escape checkpoint.',
            too_fast = 'That checkpoint was reached too quickly to validate.',
        }
        return { ok = false, message = messages[reason] or 'The checkpoint was rejected.' }
    end

    if progress.completed then
        finishMatch(match, 'robber', 'The robber escaped the city.')
    else
        for activeSource in pairs(match.state.players) do
            TriggerClientEvent('ofm_activities:pursuit:progress', activeSource,
                progress.completedCheckpoints, progress.totalCheckpoints)
        end
    end
    return { ok = true, completed = progress.completed, nextCheckpoint = index + 1 }
end)

lib.callback.register('ofm_activities:pursuit:cancel', function(source)
    if not OFMCancelPursuit(source, true) then
        return { ok = false, message = 'You are not in City Escape.' }
    end
    return { ok = true }
end)

function OFMCancelPursuit(source, notifyPlayer)
    local member = members[source]
    if not member then return false end
    local match = member.matchId and matches[member.matchId]
    local message
    if notifyPlayer then
        message = member.phase == 'queued' and 'Left the City Escape queue.' or 'You left City Escape.'
    end
    releasePlayer(source, message)
    checkEmptyTeam(match)
    return true
end

lib.callback.register('ofm_activities:pursuit:status', function(source)
    local member = members[source]
    return {
        ok = true,
        queued = member and member.phase == 'queued' or false,
        token = member and member.token or nil,
        phase = member and member.phase or nil,
    }
end)

AddEventHandler('baseevents:onPlayerKilled', function(killer) processDeath(source, killer) end)
AddEventHandler('baseevents:onPlayerDied', function() processDeath(source, nil) end)
AddEventHandler('playerDropped', function() OFMCancelPursuit(source) end)
AddEventHandler('QBCore:Server:OnPlayerUnload', function(source) OFMCancelPursuit(source) end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    local sources = {}
    for source in pairs(members) do sources[#sources + 1] = source end
    for _, source in ipairs(sources) do releasePlayer(source, 'City Escape stopped.') end
end)

print('[ofm_activities] City Escape cops and robbers ready.')
