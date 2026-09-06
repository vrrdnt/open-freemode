local config = require 'config'
local properties = PropertyRules.index(config.properties)
local busy = {}

local function responseError(message)
    return { ok = false, message = message }
end

local function playerData(source)
    local player = exports.qbx_core:GetPlayer(source)
    return player and player.PlayerData
end

local function playerNear(source, property)
    local ped = GetPlayerPed(source)
    if ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    local point = property.coords
    local dx, dy, dz = coords.x - point.x, coords.y - point.y, coords.z - point.z
    return dx * dx + dy * dy + dz * dz <= property.radius * property.radius
end

local function ownsCitizen(citizenid, propertyId)
    if not citizenid or not properties[propertyId] then return false end
    return MySQL.scalar.await([[
        SELECT 1 FROM ofm_property_purchases
        WHERE citizenid = ? AND property_id = ? LIMIT 1
    ]], { citizenid, propertyId }) ~= nil
end

exports('Owns', function(source, propertyId)
    local data = playerData(source)
    return data and ownsCitizen(data.citizenid, propertyId) or false
end)

lib.callback.register('ofm_properties:status', function(source, propertyId)
    local data = playerData(source)
    local property = type(propertyId) == 'string' and properties[propertyId]
    if not data then return responseError('Load a character before using a property.') end
    if not property or not playerNear(source, property) then
        return responseError('Visit the property marker to manage it.')
    end
    return {
        ok = true,
        owned = ownsCitizen(data.citizenid, property.id),
        property = { id = property.id, name = property.name, district = property.district, price = property.price },
    }
end)

lib.callback.register('ofm_properties:purchase', function(source, propertyId, purchaseId)
    if busy[source] then return responseError('Finish the current property request first.') end
    busy[source] = true
    local chargedPrice
    local ok, result = pcall(function()
        local data = playerData(source)
        local property = type(propertyId) == 'string' and properties[propertyId]
        if not data then return responseError('Load a character before purchasing a property.') end
        if exports.ofm_activities:IsPlayerActive(source) then
            return responseError('Finish or cancel your current activity first.')
        end
        if not property or not playerNear(source, property) then
            return responseError('Visit the property marker to purchase it.')
        end
        if type(purchaseId) ~= 'string' or #purchaseId < 8 or #purchaseId > 96
            or not purchaseId:match('^[%w:_%-]+$') then
            return responseError('The purchase request was invalid.')
        end

        local previous = MySQL.single.await([[
            SELECT citizenid, property_id, price FROM ofm_property_purchases WHERE purchase_id = ?
        ]], { purchaseId })
        if previous then
            if previous.citizenid == data.citizenid and previous.property_id == property.id then
                return { ok = true, alreadyCompleted = true, property = property.name, price = previous.price }
            end
            return responseError('That purchase request has already been used.')
        end
        if ownsCitizen(data.citizenid, property.id) then
            return responseError('This character already owns that property garage.')
        end

        local balance = exports.qbx_core:GetMoney(source, 'bank')
        if not PropertyRules.canAfford(balance, property.price) then
            return responseError(('You need $%d in your bank.'):format(property.price))
        end
        if not exports.qbx_core:RemoveMoney(source, 'bank', property.price, 'property-garage-purchase') then
            return responseError('The bank payment was declined.')
        end
        chargedPrice = property.price

        local inserted = MySQL.update.await([[
            INSERT IGNORE INTO ofm_property_purchases (purchase_id, citizenid, property_id, price)
            VALUES (?, ?, ?, ?)
        ]], { purchaseId, data.citizenid, property.id, property.price })
        if inserted ~= 1 then
            exports.qbx_core:AddMoney(source, 'bank', property.price, 'property-garage-purchase-refund')
            chargedPrice = nil
            return responseError('The property purchase could not be finalized; payment was refunded.')
        end
        chargedPrice = nil
        return { ok = true, property = property.name, price = property.price }
    end)
    busy[source] = nil
    if not ok then
        if chargedPrice then
            pcall(function()
                exports.qbx_core:AddMoney(source, 'bank', chargedPrice, 'property-garage-purchase-error-refund')
            end)
        end
        print(('[ofm_properties] Property request failed for player %d.'):format(source))
        return responseError('The property service encountered an error. No completed purchase was recorded.')
    end
    return result
end)

AddEventHandler('playerDropped', function() busy[source] = nil end)

print('[ofm_properties] Purchasable apartment garages ready.')
