local modulePath = assert(arg[1], 'vehicle rules module path is required')
dofile(modulePath)

local catalog = VehicleRules.index({
    { id = 'blista', price = 18000 },
    { id = 'sultan', price = 45000 },
})
assert(catalog.blista.price == 18000 and catalog.sultan.price == 45000)
assert(not pcall(VehicleRules.index, { { id = 'same', price = 1 }, { id = 'same', price = 2 } }))
assert(VehicleRules.canAfford(45000, 45000))
assert(not VehicleRules.canAfford(44999, 45000))

local original = { plate = 'OWNED', modEngine = 1, color1 = 0 }
local upgraded, changed = VehicleRules.apply(original, { modEngine = 2, color1 = 27 })
assert(changed and upgraded.modEngine == 2 and upgraded.color1 == 27)
assert(original.modEngine == 1 and original.color1 == 0)
local duplicate, duplicateChanged = VehicleRules.apply(upgraded, { modEngine = 2, color1 = 27 })
assert(not duplicateChanged and duplicate.plate == 'OWNED')

print('Vehicle rules passed.')
