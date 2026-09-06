CombatScore = {}

local Score = {}
Score.__index = Score

function CombatScore.new(limit)
    return setmetatable({
        limit = assert(limit),
        players = {},
        scores = { red = 0, blue = 0 },
    }, Score)
end

function Score:addPlayer(source, team, spawnIndex)
    assert(not self.players[source], 'player already exists')
    self.players[source] = {
        team = assert(team),
        kills = 0,
        deaths = 0,
        dead = false,
        spawnIndex = assert(spawnIndex),
    }
    return self.players[source]
end

function Score:removePlayer(source)
    local player = self.players[source]
    self.players[source] = nil
    return player
end

function Score:teamCount(team)
    local count = 0
    for _, player in pairs(self.players) do
        if player.team == team then count = count + 1 end
    end
    return count
end

function Score:recordDeath(victim, killer)
    local victimState = self.players[victim]
    if not victimState or victimState.dead then return nil, 'invalid_victim' end

    victimState.dead = true
    victimState.deaths = victimState.deaths + 1
    local credited
    local killerState = killer and self.players[killer]
    if killerState and killer ~= victim and killerState.team ~= victimState.team then
        killerState.kills = killerState.kills + 1
        self.scores[killerState.team] = self.scores[killerState.team] + 1
        credited = killer
    end

    local winner
    if self.scores.red >= self.limit then winner = 'red' end
    if self.scores.blue >= self.limit then winner = 'blue' end
    return {
        victim = victim,
        killer = credited,
        winner = winner,
        red = self.scores.red,
        blue = self.scores.blue,
        limit = self.limit,
    }
end

function Score:respawn(source)
    local player = self.players[source]
    if not player or not player.dead then return nil, 'not_dead' end
    player.dead = false
    return player
end

function Score:snapshot()
    return { red = self.scores.red, blue = self.scores.blue, limit = self.limit }
end
