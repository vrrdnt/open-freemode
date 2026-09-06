local statePath = assert(arg[1], 'state module path is required')
dofile(statePath)

local now = 100
local sequence = 0
local published = {}
local changes = {}
local manager = ActivityState.new({
    now = function() return now end,
    token = function(source, kind)
        sequence = sequence + 1
        return ('%s:%d:%d'):format(kind, source, sequence)
    end,
    onChange = function(source, kind, previousKind)
        published[source] = kind
        changes[#changes + 1] = { source = source, kind = kind, previousKind = previousKind }
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
assert(published[7] == 'pizza')
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
assert(published[7] == nil and changes[#changes].previousKind == 'pizza')
assert(select(2, manager:advance(7, started.token, 2, 0)) == 'not_active')

local second = assert(manager:start(8, spec))
assert(second.token ~= started.token)
assert(published[8] == 'pizza')
assert(manager:cancel(8).kind == 'pizza')
assert(published[8] == nil and changes[#changes].previousKind == 'pizza')
assert(manager:cancel(8) == nil)

local reserved = assert(manager:reserve(10, 'tdm'))
assert(reserved.kind == 'tdm' and reserved.totalStops == 0)
assert(published[10] == 'tdm')
assert(select(2, manager:reserve(10, 'race')) == 'already_active')
assert(manager:cancel(10).kind == 'tdm')
assert(published[10] == nil and changes[#changes].previousKind == 'tdm')

local race = assert(manager:start(9, {
    kind = 'race',
    payout = 500,
    radius = 13,
    minimumStopSeconds = 1,
    stops = {{ x = 10, y = 20, z = 30 }},
}))
assert(race.kind == 'race' and race.totalStops == 1)
assert(published[9] == 'race')
assert(select(2, manager:advance(9, race.token, 1, 13.1)) == 'too_far')
local raceFinished = assert(manager:advance(9, race.token, 1, 13))
assert(raceFinished.completed and raceFinished.kind == 'race' and raceFinished.payout == 500)
assert(published[9] == nil and changes[#changes].previousKind == 'race')
assert(#changes == 8)

print('Activity state lifecycle passed.')
