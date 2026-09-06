local config = require 'config'
local catalog = VehicleRules.index(config.dealer.catalog)
local upgrades = VehicleRules.index(config.modshop.upgrades)
local garages = config.garages
local busy = {}

assert(garages[config.defaultGarage], 'default garage is required')
for id, garage in pairs(garages) do
    assert(garage.id == id, 'garage key and id must match')
end

local function responseError(message)
    return { ok = false, message = message }
end

local function playerData(source)
    local player = exports.qbx_core:GetPlayer(source)
    return player and player.PlayerData
end

local function playerNear(source, point, radius)
    local ped = GetPlayerPed(source)
    if ped == 0 then return false, nil end
    local coords = GetEntityCoords(ped)
    local dx, dy, dz = coords.x - point.x, coords.y - point.y, coords.z - point.z
    return dx * dx + dy * dy + dz * dz <= radius * radius, ped
end

local function vehicleNear(vehicle, point, radius)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    local coords = GetEntityCoords(vehicle)
    local dx, dy, dz = coords.x - point.x, coords.y - point.y, coords.z - point.z
    return dx * dx + dy * dy + dz * dz <= radius * radius
end

local function trimPlate(plate)
    return tostring(plate or ''):match('^%s*(.-)%s*$')
end

local function activityBlocked(source)
    return exports.ofm_activities:IsPlayerActive(source)
end

local function locked(source, operation)
    if busy[source] then return responseError('Finish the current vehicle request first.') end
    busy[source] = true
    local ok, result = pcall(operation)
    busy[source] = nil
    if not ok then
        print(('[ofm_vehicles] Vehicle request failed for player %d.'):format(source))
        return responseError('The vehicle service encountered an error. No completed purchase was recorded.')
    end
    return result
end

local function findSpawnedVehicle(vehicleId)
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) then
            local stateId = tonumber(Entity(vehicle).state.vehicleid)
            if stateId == vehicleId then return vehicle end
        end
    end
end

local function garageAccess(source, garageId)
    local garage = type(garageId) == 'string' and garages[garageId]
    if not garage then return nil, false end
    if garage.public then return garage, true end
    return garage, garage.propertyId and exports.ofm_properties:Owns(source, garage.propertyId) or false
end

local function spawnBayClear(garage)
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if vehicleNear(vehicle, garage.spawn, garage.spawnClearRadius) then return false end
    end
    return true
end

local function ownedVehicle(source, vehicle)
    local data = playerData(source)
    if not data or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    local vehicleId = tonumber(Entity(vehicle).state.vehicleid)
    if not vehicleId then return nil end
    return exports.qbx_vehicles:GetPlayerVehicle(vehicleId, { citizenid = data.citizenid })
end

local function currentDynamicProps(vehicle, saved)
    local props = {}
    for key, value in pairs(saved or {}) do props[key] = value end
    props.plate = trimPlate(GetVehicleNumberPlateText(vehicle))
    props.model = GetEntityModel(vehicle)
    props.engineHealth = GetVehicleEngineHealth(vehicle)
    props.bodyHealth = GetVehicleBodyHealth(vehicle)
    props.tankHealth = GetVehiclePetrolTankHealth(vehicle)
    props.dirtLevel = GetVehicleDirtLevel(vehicle)
    return props
end

lib.callback.register('ofm_vehicles:purchase', function(source, catalogId, purchaseId)
    return locked(source, function()
        local data = playerData(source)
        local item = type(catalogId) == 'string' and catalog[catalogId]
        if not data then return responseError('Load a character before purchasing a vehicle.') end
        if activityBlocked(source) then return responseError('Finish or cancel your current activity first.') end
        if not playerNear(source, config.dealer.coords, config.dealer.radius) then
            return responseError('Visit Premium Deluxe Motorsport to purchase this vehicle.')
        end
        if not item then return responseError('That vehicle is not in the server catalog.') end
        if type(purchaseId) ~= 'string' or #purchaseId < 8 or #purchaseId > 96
            or not purchaseId:match('^[%w:_%-]+$') then
            return responseError('The purchase request was invalid.')
        end

        local previous = MySQL.single.await([[
            SELECT citizenid, vehicle_id, model, price
            FROM ofm_vehicle_purchases WHERE purchase_id = ?
        ]], { purchaseId })
        if previous then
            if previous.citizenid == data.citizenid and previous.model == item.model then
                local vehicle = exports.qbx_vehicles:GetPlayerVehicle(previous.vehicle_id,
                    { citizenid = data.citizenid })
                return vehicle and {
                    ok = true, alreadyCompleted = true, vehicleId = vehicle.id,
                    model = vehicle.modelName, plate = vehicle.props.plate, price = previous.price,
                } or responseError('The completed purchase record no longer has its vehicle.')
            end
            return responseError('That purchase request has already been used.')
        end

        local balance = exports.qbx_core:GetMoney(source, 'bank')
        if not VehicleRules.canAfford(balance, item.price) then
            return responseError(('You need $%d in your bank.'):format(item.price))
        end
        if not exports.qbx_core:RemoveMoney(source, 'bank', item.price, 'owned-vehicle-purchase') then
            return responseError('The bank payment was declined.')
        end

        local vehicleId = exports.qbx_vehicles:CreatePlayerVehicle({
            model = item.model,
            citizenid = data.citizenid,
            garage = config.defaultGarage,
        })
        if not vehicleId then
            exports.qbx_core:AddMoney(source, 'bank', item.price, 'owned-vehicle-purchase-refund')
            return responseError('The owned vehicle record could not be created; payment was refunded.')
        end

        local inserted = MySQL.update.await([[
            INSERT IGNORE INTO ofm_vehicle_purchases
                (purchase_id, citizenid, vehicle_id, model, price)
            VALUES (?, ?, ?, ?, ?)
        ]], { purchaseId, data.citizenid, vehicleId, item.model, item.price })
        if inserted ~= 1 then
            exports.qbx_vehicles:DeletePlayerVehicles('vehicleId', vehicleId)
            exports.qbx_core:AddMoney(source, 'bank', item.price, 'owned-vehicle-purchase-refund')
            return responseError('The purchase could not be finalized; payment was refunded.')
        end

        local vehicle = exports.qbx_vehicles:GetPlayerVehicle(vehicleId, { citizenid = data.citizenid })
        return {
            ok = true,
            vehicleId = vehicleId,
            model = item.model,
            plate = vehicle and vehicle.props.plate or 'PENDING',
            price = item.price,
        }
    end)
end)

lib.callback.register('ofm_vehicles:list', function(source, garageId)
    local data = playerData(source)
    local garage, access = garageAccess(source, garageId)
    if not data then return responseError('Load a character before opening the garage.') end
    if activityBlocked(source) then return responseError('Finish or cancel your current activity first.') end
    if not garage then return responseError('That garage does not exist.') end
    if not access then return responseError('Purchase this property garage before using it.') end
    if not playerNear(source, garage.coords, garage.radius) then
        return responseError(('Visit %s to view owned vehicles.'):format(garage.name))
    end

    local results = {}
    for _, vehicle in ipairs(exports.qbx_vehicles:GetPlayerVehicles({ citizenid = data.citizenid })) do
        local spawned = findSpawnedVehicle(vehicle.id)
        results[#results + 1] = {
            id = vehicle.id,
            label = vehicle.modelName,
            plate = vehicle.props and vehicle.props.plate or 'UNKNOWN',
            state = vehicle.state,
            garage = vehicle.garage,
            available = vehicle.state ~= 2 and not spawned
                and (vehicle.state == 0 or vehicle.garage == garage.id),
            status = vehicle.state == 2 and 'Impounded'
                or spawned and 'Out'
                or vehicle.state == 0 and 'Recoverable'
                or vehicle.garage == garage.id and 'Stored'
                or ('Stored at %s'):format(garages[vehicle.garage]
                    and garages[vehicle.garage].name or vehicle.garage or 'another garage'),
        }
    end
    return { ok = true, vehicles = results }
end)

lib.callback.register('ofm_vehicles:spawn', function(source, garageId, vehicleId)
    return locked(source, function()
        local data = playerData(source)
        local garage, access = garageAccess(source, garageId)
        if not data then return responseError('Load a character before retrieving a vehicle.') end
        if activityBlocked(source) then return responseError('Finish or cancel your current activity first.') end
        if not garage then return responseError('That garage does not exist.') end
        if not access then return responseError('Purchase this property garage before using it.') end
        local near, ped = playerNear(source, garage.coords, garage.radius)
        if not near then return responseError(('Visit %s to retrieve a vehicle.'):format(garage.name)) end
        if GetVehiclePedIsIn(ped, false) ~= 0 then return responseError('Leave your current vehicle first.') end
        vehicleId = tonumber(vehicleId)
        local vehicle = vehicleId and exports.qbx_vehicles:GetPlayerVehicle(vehicleId,
            { citizenid = data.citizenid })
        if not vehicle then return responseError('That vehicle does not belong to this character.') end
        if vehicle.state == 2 then return responseError('That vehicle is impounded.') end
        if vehicle.state == 1 and vehicle.garage ~= garage.id then
            return responseError('That vehicle is stored at another garage.')
        end
        if findSpawnedVehicle(vehicle.id) then
            return responseError('That vehicle is already out.')
        end
        if not spawnBayClear(garage) then return responseError('The garage exit is blocked.') end

        local spawn = garage.spawn
        local ok, netId, entity = pcall(qbx.spawnVehicle, {
            model = vehicle.modelName,
            spawnSource = vec4(spawn.x, spawn.y, spawn.z, spawn.w),
            warp = ped,
            props = vehicle.props,
        })
        if not ok or not entity or entity == 0 then
            return responseError('The owned vehicle could not be spawned.')
        end
        Entity(entity).state:set('vehicleid', vehicle.id, false)
        Entity(entity).state:set('ofmOwnedVehicle', true, true)
        local saved = exports.qbx_vehicles:SaveVehicle(entity, {
            garage = garage.id,
            props = vehicle.props,
        })
        if not saved then
            exports.qbx_core:DisablePersistence(entity)
            DeleteEntity(entity)
            return responseError('The vehicle state could not be saved.')
        end
        MySQL.update.await('UPDATE player_vehicles SET state = 0 WHERE id = ?', { vehicle.id })
        return { ok = true, netId = netId, plate = vehicle.props.plate, recovered = vehicle.state == 0 }
    end)
end)

lib.callback.register('ofm_vehicles:store', function(source, garageId, netId)
    return locked(source, function()
        if activityBlocked(source) then return responseError('Finish or cancel your current activity first.') end
        local garage, access = garageAccess(source, garageId)
        if not garage then return responseError('That garage does not exist.') end
        if not access then return responseError('Purchase this property garage before using it.') end
        local near, ped = playerNear(source, garage.coords, garage.radius)
        if not near then return responseError(('Drive into %s to store the vehicle.'):format(garage.name)) end
        local vehicle = tonumber(netId) and NetworkGetEntityFromNetworkId(tonumber(netId)) or 0
        if vehicle == 0 or not DoesEntityExist(vehicle) or not vehicleNear(vehicle, garage.coords, garage.radius) then
            return responseError('The vehicle is not inside the garage marker.')
        end
        if GetVehiclePedIsIn(ped, false) ~= vehicle or GetPedInVehicleSeat(vehicle, -1) ~= ped then
            return responseError('You must be driving the vehicle you want to store.')
        end
        local owned = ownedVehicle(source, vehicle)
        if not owned then return responseError('Only a vehicle owned by this character can be stored.') end
        if Entity(vehicle).state.ofmActivity then return responseError('Activity vehicles cannot be stored.') end

        local props = currentDynamicProps(vehicle, owned.props)
        local saved = exports.qbx_vehicles:SaveVehicle(vehicle, {
            state = 1,
            garage = garage.id,
            props = props,
        })
        if not saved then return responseError('The owned vehicle could not be saved.') end
        exports.qbx_core:DisablePersistence(vehicle)
        DeleteEntity(vehicle)
        return { ok = true, vehicleId = owned.id, plate = props.plate }
    end)
end)

lib.callback.register('ofm_vehicles:modify', function(source, netId, upgradeId)
    return locked(source, function()
        local near, ped = playerNear(source, config.modshop.coords, config.modshop.radius)
        local upgrade = type(upgradeId) == 'string' and upgrades[upgradeId]
        if activityBlocked(source) then return responseError('Finish or cancel your current activity first.') end
        if not near then return responseError('Visit Burton Customs to modify a vehicle.') end
        if not upgrade then return responseError('That modification is not offered here.') end
        local vehicle = tonumber(netId) and NetworkGetEntityFromNetworkId(tonumber(netId)) or 0
        if vehicle == 0 or not DoesEntityExist(vehicle) or not vehicleNear(vehicle, config.modshop.coords, config.modshop.radius) then
            return responseError('Keep the vehicle inside Burton Customs.')
        end
        if GetVehiclePedIsIn(ped, false) ~= vehicle or GetPedInVehicleSeat(vehicle, -1) ~= ped then
            return responseError('You must be driving the vehicle being modified.')
        end
        local owned = ownedVehicle(source, vehicle)
        if not owned then return responseError('Only a vehicle owned by this character can be modified.') end
        if Entity(vehicle).state.ofmActivity then return responseError('Activity vehicles cannot be modified.') end

        local current = currentDynamicProps(vehicle, owned.props)
        local props, changed = VehicleRules.apply(current, upgrade.props)
        if not changed then return responseError('That option is already installed.') end
        local balance = exports.qbx_core:GetMoney(source, 'bank')
        if not VehicleRules.canAfford(balance, upgrade.price) then
            return responseError(('You need $%d in your bank.'):format(upgrade.price))
        end
        if not exports.qbx_core:RemoveMoney(source, 'bank', upgrade.price, 'owned-vehicle-modification') then
            return responseError('The bank payment was declined.')
        end

        local saved = exports.qbx_vehicles:SaveVehicle(vehicle, { props = props })
        if not saved then
            exports.qbx_core:AddMoney(source, 'bank', upgrade.price, 'owned-vehicle-modification-refund')
            return responseError('The modification could not be saved; payment was refunded.')
        end
        lib.setVehicleProperties(vehicle, props)
        TriggerClientEvent('ofm_vehicles:applyUpgrade', source,
            NetworkGetNetworkIdFromEntity(vehicle), props, upgrade.id == 'repair')
        return { ok = true, label = upgrade.label, price = upgrade.price }
    end)
end)

AddEventHandler('playerDropped', function() busy[source] = nil end)

print('[ofm_vehicles] Owned vehicle dealer, garage and modification service ready.')
