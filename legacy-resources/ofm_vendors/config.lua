return {
    catalogs = {
        convenience = {
            { id = 'bandage', name = 'bandage', label = 'Bandage', price = 150 },
            { id = 'parachute', name = 'parachute', label = 'Parachute', price = 500 },
        },
        ammunation = {
            { id = 'armour', name = 'armour', label = 'Bulletproof Vest', price = 750 },
            { id = 'bandage', name = 'bandage', label = 'Bandage', price = 150 },
            { id = 'parachute', name = 'parachute', label = 'Parachute', price = 500 },
        },
    },
    vendors = {
        { id = 'strawberry_store', catalog = 'convenience', name = 'Strawberry Convenience Store',
            coords = { x = 25.70, y = -1347.30, z = 29.49 }, radius = 4.0,
            blip = { sprite = 59, colour = 2 } },
        { id = 'del_perro_store', catalog = 'convenience', name = 'Del Perro Convenience Store',
            coords = { x = -1222.92, y = -906.98, z = 12.33 }, radius = 4.0,
            blip = { sprite = 59, colour = 2 } },
        { id = 'sandy_store', catalog = 'convenience', name = 'Sandy Shores Convenience Store',
            coords = { x = 1961.48, y = 3739.96, z = 32.34 }, radius = 4.0,
            blip = { sprite = 59, colour = 2 } },
        { id = 'paleto_store', catalog = 'convenience', name = 'Paleto Bay Convenience Store',
            coords = { x = 1728.66, y = 6414.16, z = 35.03 }, radius = 4.0,
            blip = { sprite = 59, colour = 2 } },
        { id = 'downtown_ammunation', catalog = 'ammunation', name = 'Downtown AmmuNation Supplies',
            coords = { x = 22.56, y = -1109.89, z = 29.80 }, radius = 4.0,
            blip = { sprite = 110, colour = 1 } },
        { id = 'sandy_ammunation', catalog = 'ammunation', name = 'Sandy Shores AmmuNation Supplies',
            coords = { x = 1693.44, y = 3760.16, z = 34.71 }, radius = 4.0,
            blip = { sprite = 110, colour = 1 } },
    },
}
