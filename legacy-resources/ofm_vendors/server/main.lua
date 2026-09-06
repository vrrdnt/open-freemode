local config = require 'config'
local catalogs, vendors = VendorRules.index(config.catalogs, config.vendors)
local busy = {}

local function responseError(message)
    return { ok = false, message = message }
end

local function playerData(source)
    local player = exports.qbx_core:GetPlayer(source)
    return player and player.PlayerData
end

local function playerNear(source, vendor)
    local ped = GetPlayerPed(source)
    if ped == 0 then return false end
    if GetVehiclePedIsIn(ped, false) ~= 0 then return false end
    local coords = GetEntityCoords(ped)
    local point = vendor.coords
    local dx, dy, dz = coords.x - point.x, coords.y - point.y, coords.z - point.z
    return dx * dx + dy * dy + dz * dz <= vendor.radius * vendor.radius
end

local function purchaseTokenValid(token)
    return type(token) == 'string' and #token >= 8 and #token <= 96
        and token:match('^[%w:_%-]+$') ~= nil
end

lib.callback.register('ofm_vendors:purchase', function(source, vendorId, itemId, purchaseId)
    if busy[source] then return responseError('Finish the current vendor request first.') end
    busy[source] = true
    local chargedPrice
    local addedItem
    local ok, result = pcall(function()
        local data = playerData(source)
        local vendor = type(vendorId) == 'string' and vendors[vendorId]
        local item = vendor and type(itemId) == 'string' and catalogs[vendor.catalog][itemId]
        if not data then return responseError('Load a character before using a vendor.') end
        if exports.ofm_activities:IsPlayerActive(source) then
            return responseError('Finish or cancel your current activity first.')
        end
        if not vendor or not item or not playerNear(source, vendor) then
            return responseError('Visit the vendor marker on foot to make this purchase.')
        end
        if not purchaseTokenValid(purchaseId) then return responseError('The purchase request was invalid.') end

        local previous = MySQL.single.await([[
            SELECT citizenid, vendor_id, item_name, price FROM ofm_vendor_purchases WHERE purchase_id = ?
        ]], { purchaseId })
        if previous then
            if previous.citizenid == data.citizenid and previous.vendor_id == vendor.id
                and previous.item_name == item.name then
                return { ok = true, alreadyCompleted = true, item = item.label, price = previous.price }
            end
            return responseError('That purchase request has already been used.')
        end
        if not exports.ox_inventory:CanCarryItem(source, item.name, 1) then
            return responseError('Your inventory cannot carry that item.')
        end
        local balance = exports.qbx_core:GetMoney(source, 'bank')
        if not VendorRules.canAfford(balance, item.price) then
            return responseError(('You need $%d in your bank.'):format(item.price))
        end
        if not exports.qbx_core:RemoveMoney(source, 'bank', item.price, 'vendor-purchase') then
            return responseError('The bank payment was declined.')
        end
        chargedPrice = item.price

        local added = exports.ox_inventory:AddItem(source, item.name, 1)
        if not added then
            exports.qbx_core:AddMoney(source, 'bank', item.price, 'vendor-purchase-refund')
            chargedPrice = nil
            return responseError('The item could not be added; payment was refunded.')
        end
        addedItem = item.name

        local inserted = MySQL.update.await([[
            INSERT IGNORE INTO ofm_vendor_purchases (purchase_id, citizenid, vendor_id, item_name, price)
            VALUES (?, ?, ?, ?, ?)
        ]], { purchaseId, data.citizenid, vendor.id, item.name, item.price })
        if inserted ~= 1 then
            exports.ox_inventory:RemoveItem(source, item.name, 1)
            addedItem = nil
            exports.qbx_core:AddMoney(source, 'bank', item.price, 'vendor-purchase-refund')
            chargedPrice = nil
            return responseError('The purchase could not be finalized; payment was refunded.')
        end
        addedItem, chargedPrice = nil, nil
        return { ok = true, item = item.label, price = item.price }
    end)
    busy[source] = nil
    if not ok then
        if addedItem then pcall(function() exports.ox_inventory:RemoveItem(source, addedItem, 1) end) end
        if chargedPrice then
            pcall(function()
                exports.qbx_core:AddMoney(source, 'bank', chargedPrice, 'vendor-purchase-error-refund')
            end)
        end
        print(('[ofm_vendors] Vendor request failed for player %d.'):format(source))
        return responseError('The vendor encountered an error. No completed purchase was recorded.')
    end
    return result
end)

AddEventHandler('playerDropped', function() busy[source] = nil end)

print('[ofm_vendors] Focused supply vendor network ready.')
