ActivityQueue = {}

local Queue = {}
Queue.__index = Queue

function ActivityQueue.new(options)
    return setmetatable({
        entries = {},
        order = {},
        minimum = assert(options.minimum),
        maximum = assert(options.maximum),
    }, Queue)
end

RaceQueue = ActivityQueue

function Queue:join(source, data)
    if self.entries[source] then return nil, 'already_queued' end
    if #self.order >= self.maximum then return nil, 'queue_full' end
    self.entries[source] = data
    self.order[#self.order + 1] = source
    return #self.order
end

function Queue:remove(source)
    local entry = self.entries[source]
    if not entry then return nil end
    self.entries[source] = nil
    for index, queuedSource in ipairs(self.order) do
        if queuedSource == source then
            table.remove(self.order, index)
            break
        end
    end
    return entry
end

function Queue:size()
    return #self.order
end

function Queue:sources()
    local sources = {}
    for index, source in ipairs(self.order) do sources[index] = source end
    return sources
end

function Queue:lock()
    if #self.order < self.minimum then return nil, 'not_ready' end
    local entries = {}
    for _, source in ipairs(self.order) do
        entries[#entries + 1] = { source = source, data = self.entries[source] }
    end
    self.entries = {}
    self.order = {}
    return entries
end
