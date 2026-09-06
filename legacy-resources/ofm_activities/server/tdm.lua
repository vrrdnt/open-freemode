local config = require 'config'.tdm

assert(#config.teams.red.spawns >= math.ceil(config.maximumPlayers / 2)
    and #config.teams.blue.spawns >= math.floor(config.maximumPlayers / 2),
    'Terminal Clash needs enough spawns for both teams')

local queue = ActivityQueue.new({
    minimum = config.minimumPlayers,
    maximum = config.maximumPlayers,
})
local members = {}
local matches = {}
local matchSequence = 0
local lobbyTicket

local function distance(a, b)
    local x, y, z = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(x * x + y * y + z * z)
end

local function playerPosition(source)
    local ped = GetPlayerPed(source)
    if ped == 0 then return nil, nil end
    return GetEntityCoords(ped), ped
end

local function sourcesOf(match)
    local sources = {}
    for source in pairs(match.score.players) do sources[#sources + 1] = source end
    return sources
end

local function queueStatus(message)
    local size = queue:size()
    for _, source in ipairs(queue:sources()) do
        TriggerClientEvent('ofm_activities:tdm:queueStatus', source, size, message)
    end
end

local function releasePlayer(source, message, result)
    local online = GetPlayerName(source) ~= nil
    local wasQueued = queue:remove(source) ~= nil
    local member = members[source]
    local match = member and member.matchId and matches[member.matchId]
    if match then match.score:removePlayer(source) end

    if member then
        if member.previousBucket ~= nil and online then
            exports.qbx_core:SetPlayerBucket(source, member.previousBucket)
        end
        if online then Player(source).state:set('ofmTdmTeam', nil, true) end
        members[source] = nil
    end
    OFMActivityManager:cancel(source)

    if online then
        TriggerClientEvent('ofm_activities:tdm:restore', source,
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

    if not exports.qbx_core:AddMoney(source, 'bank', payout, 'terminal-clash-tdm') then
        MySQL.update.await('DELETE FROM ofm_match_results WHERE result_id = ?', { resultId })
        return nil
    end
    return { won = won, payout = payout, kills = player.kills, deaths = player.deaths }
end

local function finishMatch(match, winner, reason)
    if not match or match.phase == 'ended' then return end
    match.phase = 'ended'
    local participants = {}
    for _, source in ipairs(sourcesOf(match)) do
        participants[#participants + 1] = { source = source, player = match.score.players[source] }
    end

    for _, participant in ipairs(participants) do
        local result = winner and recordResult(participant.source, match, participant.player, winner) or nil
        releasePlayer(participant.source, reason, result)
    end
    matches[match.id] = nil
end

local function checkForfeit(match)
    if not match or match.phase == 'ended' then return end
    local red = match.score:teamCount('red')
    local blue = match.score:teamCount('blue')
    if red == 0 or blue == 0 then
        finishMatch(match, nil, 'Terminal Clash cancelled because a team became empty.')
    end
end

local function broadcastScore(match, result)
    result.respawnSeconds = config.respawnSeconds
    for source in pairs(match.score.players) do
        TriggerClientEvent('ofm_activities:tdm:score', source, result)
    end
end

local function respawnFor(player)
    local team = config.teams[player.team]
    player.spawnIndex = (player.spawnIndex % #team.spawns) + 1
    return team.spawns[player.spawnIndex]
end

local function processDeath(victim, killer)
    local member = members[victim]
    local match = member and member.matchId and matches[member.matchId]
    local victimState = match and match.score.players[victim]
    if not match or match.phase ~= 'running' or not victimState or victimState.dead then return end

    SetTimeout(100, function()
        member = members[victim]
        match = member and member.matchId and matches[member.matchId]
        victimState = match and match.score.players[victim]
        if not match or match.phase ~= 'running' or not victimState or victimState.dead then return end

        local victimPed = GetPlayerPed(victim)
        if victimPed == 0 or GetEntityHealth(victimPed) > 0 then return end
        local credited
        killer = tonumber(killer)
        local killerMember = killer and members[killer]
        local killerState = killerMember and killerMember.matchId == match.id and match.score.players[killer]
        if killerState and killer ~= victim and killerState.team ~= victimState.team then
            local killerCoords, killerPed = playerPosition(killer)
            local victimCoords = GetEntityCoords(victimPed)
            if killerPed and killerCoords and distance(killerCoords, victimCoords) <= config.maximumKillDistance then
                credited = killer
            end
        end

        local result = match.score:recordDeath(victim, credited)
        if not result then return end
        broadcastScore(match, result)
        if result.winner then
            local winner = result.winner
            finishMatch(match, winner, ('%s team wins %d–%d.'):format(
                config.teams[winner].label, result.red, result.blue))
            return
        end

        SetTimeout(config.respawnSeconds * 1000, function()
            local currentMember = members[victim]
            local currentMatch = currentMember and currentMember.matchId and matches[currentMember.matchId]
            local currentState = currentMatch and currentMatch.score.players[victim]
            if not currentMatch or currentMatch.phase ~= 'running' or not currentState or not currentState.dead then return end
            currentMatch.score:respawn(victim)
            TriggerClientEvent('ofm_activities:tdm:respawn', victim, respawnFor(currentState), currentMatch.score:snapshot())
        end)
    end)
end

local function startMatch(entries)
    matchSequence = matchSequence + 1
    local matchId = ('terminal-clash:%d:%d'):format(os.time(), matchSequence)
    local bucket = config.bucketBase + matchSequence
    local match = {
        id = matchId,
        bucket = bucket,
        phase = 'countdown',
        score = CombatScore.new(config.scoreLimit),
    }
    matches[matchId] = match
    SetRoutingBucketPopulationEnabled(bucket, false)

    local teamSlots = { red = 0, blue = 0 }
    local valid = 0
    for _, entry in ipairs(entries) do
        local source = entry.source
        local member = members[source]
        local coords, ped = playerPosition(source)
        local session = OFMActivityManager:get(source)
        if member and member.phase == 'queued' and session and session.token == member.token
            and coords and distance(coords, config.queue) <= config.queueRadius then
            valid = valid + 1
            local team = valid % 2 == 1 and 'red' or 'blue'
            teamSlots[team] = teamSlots[team] + 1
            local spawn = config.teams[team].spawns[teamSlots[team]]
            member.phase = 'countdown'
            member.matchId = matchId
            member.previousBucket = GetPlayerRoutingBucket(source)
            member.returnPosition = {
                x = coords.x, y = coords.y, z = coords.z, w = GetEntityHeading(ped),
            }
            match.score:addPlayer(source, team, teamSlots[team])
            exports.qbx_core:SetPlayerBucket(source, bucket)
            Player(source).state:set('ofmTdmTeam', team, true)
            TriggerClientEvent('ofm_activities:tdm:prepare', source, {
                token = member.token,
                name = config.name,
                team = team,
                teamLabel = config.teams[team].label,
                spawn = spawn,
                countdownSeconds = config.countdownSeconds,
                scoreLimit = config.scoreLimit,
                loadout = config.loadout,
                armor = config.armor,
            })
        else
            releasePlayer(source, 'You left the TDM queue area.')
        end
    end

    if valid < config.minimumPlayers or match.score:teamCount('red') == 0 or match.score:teamCount('blue') == 0 then
        finishMatch(match, nil, 'Not enough players remained to start TDM.')
        return
    end

    SetTimeout(config.countdownSeconds * 1000, function()
        local current = matches[matchId]
        if not current or current.phase ~= 'countdown' then return end
        current.phase = 'running'
        for source, player in pairs(current.score.players) do
            local member = members[source]
            if member then member.phase = 'running' end
            local snapshot = current.score:snapshot()
            snapshot.team = player.team
            TriggerClientEvent('ofm_activities:tdm:start', source, snapshot)
        end
    end)
end

local function scheduleMatch()
    if lobbyTicket or queue:size() < config.minimumPlayers then return end
    local ticket = {}
    lobbyTicket = ticket
    queueStatus(('TDM lobby locks in %d seconds. Stay inside the marker.'):format(config.lobbySeconds))
    SetTimeout(config.lobbySeconds * 1000, function()
        if lobbyTicket ~= ticket then return end
        lobbyTicket = nil
        local entries = queue:lock()
        if entries then startMatch(entries) else queueStatus('Waiting for at least two players.') end
    end)
end

lib.callback.register('ofm_activities:tdm:join', function(source)
    if not exports.qbx_core:GetPlayer(source) then
        return { ok = false, message = 'Load a character before joining TDM.' }
    end
    local coords, ped = playerPosition(source)
    if not coords or distance(coords, config.queue) > config.queueRadius then
        return { ok = false, message = 'Enter the Terminal Clash marker first.' }
    end
    if GetVehiclePedIsIn(ped, false) ~= 0 then
        return { ok = false, message = 'Leave your vehicle before joining Terminal Clash.' }
    end

    local reservation, reason = OFMActivityManager:reserve(source, 'tdm')
    if not reservation then
        return { ok = false, message = reason == 'already_active' and 'Finish or cancel your current activity first.'
            or 'TDM could not be reserved.' }
    end

    local position, queueReason = queue:join(source, { token = reservation.token })
    if not position then
        OFMActivityManager:cancel(source)
        return { ok = false, message = queueReason == 'queue_full' and 'The TDM queue is full.'
            or 'You are already queued.' }
    end
    members[source] = { token = reservation.token, phase = 'queued' }
    scheduleMatch()
    queueStatus()
    return {
        ok = true,
        token = reservation.token,
        position = position,
        size = queue:size(),
        launchInMs = lobbyTicket and config.lobbySeconds * 1000 or nil,
    }
end)

lib.callback.register('ofm_activities:tdm:cancel', function(source)
    if not OFMCancelTdm(source, true) then
        return { ok = false, message = 'You are not in Terminal Clash.' }
    end
    return { ok = true }
end)

function OFMCancelTdm(source, notifyPlayer)
    local member = members[source]
    if not member then return false end
    local match = member.matchId and matches[member.matchId]
    local message
    if notifyPlayer then
        message = member.phase == 'queued' and 'Left the TDM queue.' or 'You forfeited Terminal Clash.'
    end
    releasePlayer(source, message)
    checkForfeit(match)
    return true
end

lib.callback.register('ofm_activities:tdm:status', function(source)
    local member = members[source]
    local match = member and member.matchId and matches[member.matchId]
    return {
        ok = true,
        queued = member and member.phase == 'queued' or false,
        token = member and member.token or nil,
        phase = member and member.phase or nil,
        score = match and match.score:snapshot() or nil,
    }
end)

AddEventHandler('baseevents:onPlayerKilled', function(killer)
    processDeath(source, killer)
end)

AddEventHandler('baseevents:onPlayerDied', function()
    processDeath(source, nil)
end)

local function playerLeaving(source)
    OFMCancelTdm(source)
end

AddEventHandler('playerDropped', function() playerLeaving(source) end)
AddEventHandler('QBCore:Server:OnPlayerUnload', playerLeaving)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    local sources = {}
    for source in pairs(members) do sources[#sources + 1] = source end
    for _, source in ipairs(sources) do releasePlayer(source, 'Terminal Clash stopped.') end
end)

print('[ofm_activities] Terminal Clash TDM ready.')
