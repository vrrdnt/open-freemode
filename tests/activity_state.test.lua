local statePath = assert(arg[1], 'state module path is required')
dofile(statePath)

local now = 100
local sequence = 0
local manager = ActivityState.new({
    now = function() return now end,
    token = function(source, kind)
        sequence = sequence + 1
        return ('%s:%d:%d'):format(kind, source, sequence)
    end,
})
local spec = {
    kind = 'pizza',
    payout = 750,
    radius = 4,
    minimumStopSeconds = 4,
    stops = {
        { x = 1, y = 2, z = 3 },
        { x = 4, y = 5, z = 6 },
    },
}

local started = assert(manager:start(7, spec))
assert(started.nextIndex == 1 and started.totalStops == 2)
assert(select(2, manager:start(7, spec)) == 'already_active')
assert(select(2, manager:advance(7, 'wrong', 1, 0)) == 'invalid_token')
assert(select(2, manager:advance(7, started.token, 2, 0)) == 'wrong_stop')
assert(select(2, manager:advance(7, started.token, 1, 4.1)) == 'too_far')

local nextStop = assert(manager:advance(7, started.token, 1, 4))
assert(nextStop.nextIndex == 2)
assert(select(2, manager:advance(7, started.token, 2, 0)) == 'too_fast')
now = now + 4
local completed = assert(manager:advance(7, started.token, 2, 0))
assert(completed.completed and completed.payout == 750)
assert(manager:status(7) == nil)
assert(select(2, manager:advance(7, started.token, 2, 0)) == 'not_active')

local second = assert(manager:start(8, spec))
assert(second.token ~= started.token)
assert(manager:cancel(8).kind == 'pizza')
assert(manager:cancel(8) == nil)

print('Activity state lifecycle passed.')
