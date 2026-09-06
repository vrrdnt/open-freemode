VehicleRules = {}

function VehicleRules.index(entries)
    local indexed = {}
    for _, entry in ipairs(entries) do
        assert(type(entry.id) == 'string' and entry.id ~= '', 'entry id is required')
        assert(not indexed[entry.id], 'duplicate entry id')
        assert(type(entry.price) == 'number' and entry.price >= 0, 'entry price must be non-negative')
        indexed[entry.id] = entry
    end
    return indexed
end

function VehicleRules.apply(props, changes)
    local updated = {}
    for key, value in pairs(props or {}) do updated[key] = value end
    local changed = false
    for key, value in pairs(changes) do
        if updated[key] ~= value then changed = true end
        updated[key] = value
    end
    return updated, changed
end

function VehicleRules.canAfford(balance, price)
    return type(balance) == 'number' and balance >= price
end
