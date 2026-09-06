local config = require 'config'
local submitting = false
local promptVisible = false
local promptText

local function notify(description, kind)
    lib.notify({ title = 'Owned Vehicles', description = description, type = kind or 'inform' })
end

local function showPrompt(text)
    if promptVisible and promptText == text then return end
    if promptVisible then lib.hideTextUI() end
    lib.showTextUI(text)
    promptVisible = true
    promptText = text
end

local function hidePrompt()
    if not promptVisible then return end
    lib.hideTextUI()
    promptVisible = false
    promptText = nil
end

local function confirmPurchase(header, content)
    return lib.alertDialog({
        header = header,
        content = content,
        centered = true,
        cancel = true,
        labels = { confirm = 'Purchase', cancel = 'Cancel' },
    }) == 'confirm'
end

local function purchaseVehicle(item)
    if submitting then return end
    if not confirmPurchase(item.label, ('$%d will be charged to your bank. The vehicle will be stored at Legion Square Garage.'):format(item.price)) then
        return
    end
    submitting = true
    local purchaseId = ('vehicle:%d:%d:%06d'):format(
        GetPlayerServerId(PlayerId()), GetGameTimer(), math.random(0, 999999))
    local response = lib.callback.await('ofm_vehicles:purchase', false, item.id, purchaseId)
    submitting = false
    if not response or not response.ok then
        return notify(response and response.message or 'The purchase could not be completed.', 'error')
    end
    notify(('%s purchased for $%d. Plate %s is stored at Legion Square.'):format(
        item.label, response.price, response.plate), 'success')
end

local function openDealer()
    local options = {}
    for _, item in ipairs(config.dealer.catalog) do
        local selected = item
        options[#options + 1] = {
            title = selected.label,
            description = ('$%d · delivered to Legion Square Garage'):format(selected.price),
            icon = 'car',
            onSelect = function() purchaseVehicle(selected) end,
        }
    end
    lib.registerContext({ id = 'ofm_vehicle_dealer', title = config.dealer.name, options = options })
    lib.showContext('ofm_vehicle_dealer')
end

local function retrieveVehicle(vehicleId)
    if submitting then return end
    submitting = true
    local response = lib.callback.await('ofm_vehicles:spawn', false, vehicleId)
    submitting = false
    if not response or not response.ok then
        return notify(response and response.message or 'The vehicle could not be retrieved.', 'error')
    end
    notify((response.recovered and 'Recovered' or 'Retrieved') .. (' owned vehicle %s.'):format(response.plate), 'success')
end

local function openGarage()
    if submitting then return end
    submitting = true
    local response = lib.callback.await('ofm_vehicles:list', false)
    submitting = false
    if not response or not response.ok then
        return notify(response and response.message or 'The garage could not be opened.', 'error')
    end

    local options = {}
    for _, vehicle in ipairs(response.vehicles) do
        local selected = vehicle
        options[#options + 1] = {
            title = ('%s · %s'):format(selected.label, selected.plate),
            description = selected.status,
            icon = 'car-side',
            disabled = not selected.available,
            onSelect = function() retrieveVehicle(selected.id) end,
        }
    end
    if #options == 0 then
        options[1] = { title = 'No owned vehicles', description = 'Purchase one at Premium Deluxe Motorsport.', disabled = true }
    end
    lib.registerContext({ id = 'ofm_legion_garage', title = config.garage.name, options = options })
    lib.showContext('ofm_legion_garage')
end

local function storeVehicle()
    if submitting then return end
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 then return openGarage() end
    submitting = true
    local response = lib.callback.await('ofm_vehicles:store', false, NetworkGetNetworkIdFromEntity(vehicle))
    submitting = false
    if not response or not response.ok then
        return notify(response and response.message or 'The vehicle could not be stored.', 'error')
    end
    notify(('Stored owned vehicle %s.'):format(response.plate), 'success')
end

local function purchaseUpgrade(upgrade)
    if submitting then return end
    if not confirmPurchase(upgrade.label, ('$%d will be charged to your bank.'):format(upgrade.price)) then return end
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 then return notify('Drive an owned vehicle into Burton Customs.', 'error') end
    submitting = true
    local response = lib.callback.await('ofm_vehicles:modify', false,
        NetworkGetNetworkIdFromEntity(vehicle), upgrade.id)
    submitting = false
    if not response or not response.ok then
        return notify(response and response.message or 'The modification could not be installed.', 'error')
    end
    notify(('%s installed for $%d.'):format(response.label, response.price), 'success')
end

local function openModshop()
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId() then
        return notify('Enter the driver seat of an owned vehicle first.', 'error')
    end
    SetVehicleModKit(vehicle, 0)
    local options = {}
    for _, upgrade in ipairs(config.modshop.upgrades) do
        local selected = upgrade
        local disabled = selected.props.modEngine and selected.props.modEngine >= GetNumVehicleMods(vehicle, 11)
            or selected.props.modBrakes and selected.props.modBrakes >= GetNumVehicleMods(vehicle, 12)
            or selected.props.modTransmission and selected.props.modTransmission >= GetNumVehicleMods(vehicle, 13)
        options[#options + 1] = {
            title = selected.label,
            description = disabled and 'Unavailable for this model' or ('$%d from bank'):format(selected.price),
            icon = selected.id == 'repair' and 'wrench' or 'gears',
            disabled = disabled,
            onSelect = function() purchaseUpgrade(selected) end,
        }
    end
    lib.registerContext({ id = 'ofm_vehicle_modshop', title = config.modshop.name, options = options })
    lib.showContext('ofm_vehicle_modshop')
end

RegisterNetEvent('ofm_vehicles:applyUpgrade', function(netId, props, repair)
    if not NetworkDoesEntityExistWithNetworkId(netId) then return end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle == 0 or vehicle ~= GetVehiclePedIsIn(PlayerPedId(), false) then return end
    lib.setVehicleProperties(vehicle, props, repair == true)
end)

local locations = {
    { data = config.dealer, sprite = 326, colour = 3, label = config.dealer.name },
    { data = config.garage, sprite = 357, colour = 2, label = config.garage.name },
    { data = config.modshop, sprite = 72, colour = 5, label = config.modshop.name },
}

CreateThread(function()
    for _, location in ipairs(locations) do
        local point = location.data.coords
        local blip = AddBlipForCoord(point.x, point.y, point.z)
        SetBlipSprite(blip, location.sprite)
        SetBlipColour(blip, location.colour)
        SetBlipScale(blip, 0.8)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(location.label)
        EndTextCommandSetBlipName(blip)
    end

    while true do
        local sleep = 750
        local activeLocation
        local activeDistance
        if not LocalPlayer.state.ofmActivity then
            local coords = GetEntityCoords(PlayerPedId())
            for index, location in ipairs(locations) do
                local point = location.data.coords
                local range = #(coords - vec3(point.x, point.y, point.z))
                if range < 30.0 then
                    sleep = 0
                    DrawMarker(1, point.x, point.y, point.z - 1.0,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3.0, 3.0, 0.5,
                        80, 180, 120, 165, false, false, 2, false)
                end
                if range < 3.0 and (not activeDistance or range < activeDistance) then
                    activeLocation, activeDistance = index, range
                end
            end
        end

        if activeLocation and not submitting then
            sleep = 0
            if activeLocation == 1 then
                showPrompt('[E] Browse owned vehicles')
                if IsControlJustReleased(0, 38) then hidePrompt() openDealer() end
            elseif activeLocation == 2 then
                local driving = GetVehiclePedIsIn(PlayerPedId(), false) ~= 0
                showPrompt(driving and '[E] Store owned vehicle' or '[E] Open owned garage')
                if IsControlJustReleased(0, 38) then hidePrompt() storeVehicle() end
            else
                showPrompt('[E] Modify owned vehicle')
                if IsControlJustReleased(0, 38) then hidePrompt() openModshop() end
            end
        else
            hidePrompt()
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then hidePrompt() end
end)

print('[ofm_vehicles] Owned vehicle client ready.')
