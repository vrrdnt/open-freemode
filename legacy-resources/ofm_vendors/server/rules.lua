VendorRules = {}

function VendorRules.index(catalogEntries, vendorEntries)
    local catalogs = {}
    for catalogId, entries in pairs(catalogEntries) do
        assert(type(catalogId) == 'string' and catalogId ~= '', 'catalog id is required')
        local items = {}
        for _, item in ipairs(entries) do
            assert(type(item.id) == 'string' and item.id ~= '', 'item id is required')
            assert(type(item.name) == 'string' and item.name ~= '', 'item name is required')
            assert(type(item.price) == 'number' and item.price >= 0 and item.price % 1 == 0,
                'item price must be a non-negative integer')
            assert(not items[item.id], 'duplicate vendor item id')
            items[item.id] = item
        end
        assert(next(items), 'vendor catalog cannot be empty')
        catalogs[catalogId] = items
    end

    local vendors = {}
    for _, vendor in ipairs(vendorEntries) do
        assert(type(vendor.id) == 'string' and vendor.id ~= '', 'vendor id is required')
        assert(not vendors[vendor.id], 'duplicate vendor id')
        assert(catalogs[vendor.catalog], 'vendor catalog does not exist')
        vendors[vendor.id] = vendor
    end
    return catalogs, vendors
end

function VendorRules.canAfford(balance, price)
    return type(balance) == 'number' and balance >= price
end
