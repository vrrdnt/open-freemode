ActivityState = {}

local Manager = {}
Manager.__index = Manager

local function snapshot(session)
    local stop = session.stops[session.nextIndex]
    return {
        kind = session.kind,
        token = session.token,
        nextIndex = session.nextIndex,
        totalStops = #session.stops,
        stop = stop and { x = stop.x, y = stop.y, z = stop.z } or nil,
        vehicleNetId = session.vehicleNetId,
    }
end

function ActivityState.new(options)
    return setmetatable({
        sessions = {},
        now = assert(options.now),
        token = assert(options.token),
    }, Manager)
end

function Manager:start(source, spec)
    if self.sessions[source] then return nil, 'already_active' end
    if not spec.stops or #spec.stops == 0 then return nil, 'no_stops' end

    local session = {
        kind = assert(spec.kind),
        token = self.token(source, spec.kind),
        stops = spec.stops,
        payout = assert(spec.payout),
        radius = assert(spec.radius),
        minimumStopSeconds = spec.minimumStopSeconds or 0,
        nextIndex = 1,
        lastCompletedAt = self.now() - (spec.minimumStopSeconds or 0),
    }
    self.sessions[source] = session
    return snapshot(session)
end

function Manager:get(source)
    return self.sessions[source]
end

function Manager:status(source)
    local session = self.sessions[source]
    return session and snapshot(session) or nil
end

function Manager:setVehicle(source, entity, netId)
    local session = self.sessions[source]
    if not session then return false end
    session.vehicle = entity
    session.vehicleNetId = netId
    return true
end

function Manager:advance(source, token, index, distance)
    local session = self.sessions[source]
    if not session then return nil, 'not_active' end
    if token ~= session.token then return nil, 'invalid_token' end
    if index ~= session.nextIndex then return nil, 'wrong_stop' end
    if distance > session.radius then return nil, 'too_far' end

    local now = self.now()
    if now - session.lastCompletedAt < session.minimumStopSeconds then
        return nil, 'too_fast'
    end
    session.lastCompletedAt = now
    session.nextIndex = session.nextIndex + 1

    if session.nextIndex > #session.stops then
        self.sessions[source] = nil
        return {
            completed = true,
            kind = session.kind,
            token = session.token,
            payout = session.payout,
            vehicle = session.vehicle,
        }
    end

    return snapshot(session)
end

function Manager:cancel(source)
    local session = self.sessions[source]
    self.sessions[source] = nil
    return session
end

function Manager:all()
    return pairs(self.sessions)
end
