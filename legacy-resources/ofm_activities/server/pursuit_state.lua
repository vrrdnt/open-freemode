PursuitState = {}

local State = {}
State.__index = State

function PursuitState.new(options)
    return setmetatable({
        now = assert(options.now),
        checkpointCount = assert(options.checkpointCount),
        checkpointRadius = assert(options.checkpointRadius),
        minimumCheckpointSeconds = options.minimumCheckpointSeconds or 0,
        phase = 'countdown',
        players = {},
        nextCheckpoint = 1,
    }, State)
end

function State:addPlayer(source, team)
    assert(not self.players[source], 'player already exists')
    self.players[source] = {
        team = assert(team),
        kills = 0,
        deaths = 0,
        dead = false,
    }
    return self.players[source]
end

function State:removePlayer(source)
    local player = self.players[source]
    self.players[source] = nil
    return player
end

function State:teamCount(team)
    local count = 0
    for _, player in pairs(self.players) do
        if player.team == team then count = count + 1 end
    end
    return count
end

function State:start(durationSeconds)
    if self.phase ~= 'countdown' then return nil, 'already_started' end
    self.phase = 'running'
    self.startedAt = self.now()
    self.deadline = self.startedAt + assert(durationSeconds)
    self.lastCheckpointAt = self.startedAt
    return self:snapshot()
end

function State:checkpoint(source, index, distance, isDriver)
    local player = self.players[source]
    if self.phase ~= 'running' then return nil, 'not_running' end
    if not player or player.team ~= 'robber' or player.dead then return nil, 'not_robber' end
    if index ~= self.nextCheckpoint then return nil, 'wrong_checkpoint' end
    if not isDriver then return nil, 'not_driver' end
    if distance > self.checkpointRadius then return nil, 'too_far' end

    local now = self.now()
    local minimum = type(self.minimumCheckpointSeconds) == 'table'
        and (self.minimumCheckpointSeconds[index] or 0) or self.minimumCheckpointSeconds
    if now - self.lastCheckpointAt < minimum then return nil, 'too_fast' end
    self.lastCheckpointAt = now
    self.nextCheckpoint = self.nextCheckpoint + 1
    return {
        completed = self.nextCheckpoint > self.checkpointCount,
        completedCheckpoints = self.nextCheckpoint - 1,
        totalCheckpoints = self.checkpointCount,
    }
end

function State:recordDeath(victim, killer)
    local victimState = self.players[victim]
    if self.phase ~= 'running' or not victimState or victimState.dead then return nil, 'invalid_victim' end

    victimState.dead = true
    victimState.deaths = victimState.deaths + 1
    local credited
    local killerState = killer and self.players[killer]
    if killerState and killer ~= victim and killerState.team ~= victimState.team then
        killerState.kills = killerState.kills + 1
        credited = killer
    end

    return {
        victim = victim,
        killer = credited,
        winner = victimState.team == 'robber' and 'cops' or nil,
    }
end

function State:respawn(source)
    local player = self.players[source]
    if self.phase ~= 'running' or not player or player.team ~= 'cops' or not player.dead then
        return nil, 'not_respawnable'
    end
    player.dead = false
    return player
end

function State:timeout()
    if self.phase ~= 'running' or self.now() < self.deadline then return nil, 'not_expired' end
    return 'cops'
end

function State:snapshot()
    return {
        phase = self.phase,
        nextCheckpoint = self.nextCheckpoint,
        totalCheckpoints = self.checkpointCount,
        deadline = self.deadline,
    }
end
