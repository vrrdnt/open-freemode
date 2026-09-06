local modulePath = assert(arg[1], 'vendor rules module path is required')
dofile(modulePath)

local config = dofile(assert(arg[2], 'vendor config path is required'))
local configuredCatalogs, configuredVendors = VendorRules.index(config.catalogs, config.vendors)
local vendorCount = 0
for _ in pairs(configuredVendors) do vendorCount = vendorCount + 1 end
assert(vendorCount == 6, 'focused vendor network must contain six locations')
for _, catalog in pairs(configuredCatalogs) do
    for _, item in pairs(catalog) do
        assert(not item.name:match('^WEAPON_'), 'persistent vendors must not duplicate vMenu weapons')
    end
end
assert(next(dofile(assert(arg[3], 'ox_inventory shop override path is required'))) == nil,
    'upstream sample shops must remain disabled')

local catalogs, vendors = VendorRules.index({
    supplies = {
        { id = 'armour', name = 'armour', price = 750 },
        { id = 'bandage', name = 'bandage', price = 150 },
    },
}, {
    { id = 'city', catalog = 'supplies' },
})
assert(catalogs.supplies.armour.price == 750 and vendors.city.catalog == 'supplies')
assert(not pcall(VendorRules.index, { supplies = {
    { id = 'same', name = 'armour', price = 1 },
    { id = 'same', name = 'bandage', price = 1 },
} }, { { id = 'city', catalog = 'supplies' } }))
assert(not pcall(VendorRules.index, { supplies = {
    { id = 'bad', name = 'armour', price = 1.5 },
} }, { { id = 'city', catalog = 'supplies' } }))
assert(not pcall(VendorRules.index, { supplies = {
    { id = 'armour', name = 'armour', price = 750 },
} }, { { id = 'city', catalog = 'missing' } }))
assert(VendorRules.canAfford(750, 750))
assert(not VendorRules.canAfford(749, 750))

print('Vendor rules passed.')
