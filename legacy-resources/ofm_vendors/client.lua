local config = require 'config'
local submitting = false
local promptVisible = false

local function notify(description, kind)
    lib.notify({ title = 'Supplies', description = description, type = kind or 'inform' })
end

local function hidePrompt()
    if not promptVisible then return end
    lib.hideTextUI()
    promptVisible = false
end

local function purchase(vendor, item)
    if submitting then return end
    local confirmation = lib.alertDialog({
        header = item.label,
        content = ('$%d will be charged to your bank.'):format(item.price),
        centered = true,
        cancel = true,
        labels = { confirm = 'Purchase', cancel = 'Cancel' },
    })
    if confirmation ~= 'confirm' then return end
    submitting = true
    local purchaseId = ('vendor:%d:%d:%06d'):format(
        GetPlayerServerId(PlayerId()), GetGameTimer(), math.random(0, 999999))
    local response = lib.callback.await('ofm_vendors:purchase', false, vendor.id, item.id, purchaseId)
    submitting = false
    if not response or not response.ok then
        return notify(response and response.message or 'The purchase could not be completed.', 'error')
    end
    notify(('%s purchased for $%d.'):format(response.item, response.price), 'success')
end

local function openVendor(vendor)
    local options = {}
    for _, item in ipairs(config.catalogs[vendor.catalog]) do
        local selected = item
        options[#options + 1] = {
            title = selected.label,
            description = ('$%d from bank'):format(selected.price),
            icon = selected.id == 'armour' and 'shield-halved'
                or selected.id == 'bandage' and 'bandage' or 'parachute-box',
            onSelect = function() purchase(vendor, selected) end,
        }
    end
    local contextId = 'ofm_vendor_' .. vendor.id
    lib.registerContext({ id = contextId, title = vendor.name, options = options })
    lib.showContext(contextId)
end

CreateThread(function()
    for _, vendor in ipairs(config.vendors) do
        local point = vendor.coords
        local blip = AddBlipForCoord(point.x, point.y, point.z)
        SetBlipSprite(blip, vendor.blip.sprite)
        SetBlipColour(blip, vendor.blip.colour)
        SetBlipScale(blip, 0.68)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(vendor.name)
        EndTextCommandSetBlipName(blip)
    end

    while true do
        local sleep = 750
        local active
        local activeDistance
        if not LocalPlayer.state.ofmActivity and GetVehiclePedIsIn(PlayerPedId(), false) == 0 then
            local coords = GetEntityCoords(PlayerPedId())
            for _, vendor in ipairs(config.vendors) do
                local point = vendor.coords
                local distance = #(coords - vec3(point.x, point.y, point.z))
                if distance < 20.0 then
                    sleep = 0
                    DrawMarker(1, point.x, point.y, point.z - 1.0,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.2, 0.35,
                        82, 170, 125, 155, false, false, 2, false)
                end
                if distance < 2.0 and (not activeDistance or distance < activeDistance) then
                    active, activeDistance = vendor, distance
                end
            end
        end

        if active and not submitting then
            sleep = 0
            if not promptVisible then
                lib.showTextUI('[E] Browse supplies')
                promptVisible = true
            end
            if IsControlJustReleased(0, 38) then hidePrompt() openVendor(active) end
        else
            hidePrompt()
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then hidePrompt() end
end)

print('[ofm_vendors] Supply vendor client ready.')
