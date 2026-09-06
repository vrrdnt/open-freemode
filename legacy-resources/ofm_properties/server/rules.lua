PropertyRules = {}

function PropertyRules.index(entries)
    local indexed = {}
    for _, entry in ipairs(entries) do
        assert(type(entry.id) == 'string' and entry.id ~= '', 'property id is required')
        assert(type(entry.garageId) == 'string' and entry.garageId ~= '', 'garage id is required')
        assert(not indexed[entry.id], 'duplicate property id')
        assert(type(entry.price) == 'number' and entry.price >= 0, 'property price must be non-negative')
        indexed[entry.id] = entry
    end
    return indexed
end

function PropertyRules.canAfford(balance, price)
    return type(balance) == 'number' and balance >= price
end
