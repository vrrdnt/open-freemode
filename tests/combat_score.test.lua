local modulePath = assert(arg[1], 'combat score module path is required')
dofile(modulePath)

local score = CombatScore.new(2)
local red = score:addPlayer(11, 'red', 1)
local blue = score:addPlayer(12, 'blue', 1)
score:addPlayer(13, 'red', 2)
assert(score:teamCount('red') == 2 and score:teamCount('blue') == 1)

local suicide = assert(score:recordDeath(11, 11))
assert(suicide.killer == nil and suicide.red == 0 and suicide.blue == 0)
assert(select(2, score:recordDeath(11, 12)) == 'invalid_victim')
assert(score:respawn(11) == red)
assert(select(2, score:respawn(11)) == 'not_dead')

local friendly = assert(score:recordDeath(13, 11))
assert(friendly.killer == nil and red.kills == 0)
assert(score:respawn(13))

local first = assert(score:recordDeath(12, 11))
assert(first.killer == 11 and first.red == 1 and first.winner == nil)
assert(red.kills == 1 and blue.deaths == 1)
assert(score:respawn(12))

local winning = assert(score:recordDeath(12, 11))
assert(winning.winner == 'red' and winning.red == 2)
assert(score:snapshot().red == 2)
assert(score:removePlayer(13).team == 'red')
assert(score:teamCount('red') == 1)

print('Combat score lifecycle passed.')
