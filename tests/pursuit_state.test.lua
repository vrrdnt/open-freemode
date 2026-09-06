local modulePath = assert(arg[1], 'pursuit state module path is required')
dofile(modulePath)

local now = 100
local pursuit = PursuitState.new({
    now = function() return now end,
    checkpointCount = 2,
    checkpointRadius = 12,
    minimumCheckpointSeconds = { 2, 3 },
})
pursuit:addPlayer(11, 'robber')
pursuit:addPlayer(12, 'cops')
pursuit:addPlayer(13, 'cops')
assert(pursuit:teamCount('robber') == 1 and pursuit:teamCount('cops') == 2)
assert(select(2, pursuit:checkpoint(11, 1, 0, true)) == 'not_running')
assert(pursuit:start(10).deadline == 110)
assert(select(2, pursuit:start(10)) == 'already_started')
assert(select(2, pursuit:checkpoint(12, 1, 0, true)) == 'not_robber')
assert(select(2, pursuit:checkpoint(11, 2, 0, true)) == 'wrong_checkpoint')
assert(select(2, pursuit:checkpoint(11, 1, 13, true)) == 'too_far')
assert(select(2, pursuit:checkpoint(11, 1, 0, false)) == 'not_driver')
assert(select(2, pursuit:checkpoint(11, 1, 0, true)) == 'too_fast')
now = 102
assert(pursuit:checkpoint(11, 1, 0, true).completed == false)
assert(select(2, pursuit:checkpoint(11, 2, 0, true)) == 'too_fast')
now = 105
assert(pursuit:checkpoint(11, 2, 0, true).completed == true)

local copDeath = assert(pursuit:recordDeath(12, 11))
assert(copDeath.killer == 11 and copDeath.winner == nil)
assert(select(2, pursuit:recordDeath(12, 11)) == 'invalid_victim')
assert(pursuit:respawn(12).dead == false)
assert(select(2, pursuit:respawn(12)) == 'not_respawnable')

local robberDeath = assert(pursuit:recordDeath(11, 12))
assert(robberDeath.killer == 12 and robberDeath.winner == 'cops')
assert(select(2, pursuit:timeout()) == 'not_expired')
now = 110
assert(pursuit:timeout() == 'cops')
assert(pursuit:removePlayer(13).team == 'cops')

print('Pursuit state lifecycle passed.')
