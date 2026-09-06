local modulePath = assert(arg[1], 'property rules module path is required')
dofile(modulePath)

local properties = PropertyRules.index({
    { id = 'alta', garageId = 'alta', price = 150000 },
    { id = 'del_perro', garageId = 'del_perro', price = 225000 },
})
assert(properties.alta.price == 150000 and properties.del_perro.garageId == 'del_perro')
assert(not pcall(PropertyRules.index, {
    { id = 'same', garageId = 'one', price = 1 },
    { id = 'same', garageId = 'two', price = 2 },
}))
assert(PropertyRules.canAfford(150000, 150000))
assert(not PropertyRules.canAfford(149999, 150000))

print('Property rules passed.')
