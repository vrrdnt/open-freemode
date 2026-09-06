local config = require 'config'
local submitting = false
local promptVisible = false
local promptText

local function notify(description, kind)
    lib.notify({ title = 'Properties', description = description, type = kind or 'inform' })
end

local function showPrompt(text)
    if promptVisible and promptText == text then return end
    if promptVisible then lib.hideTextUI() end
    lib.showTextUI(text)
    promptVisible, promptText = true, text
end

local function hidePrompt()
    if not promptVisible then return end
    lib.hideTextUI()
    promptVisible, promptText = false, nil
end

local function useGarage(property)
    if GetResourceState('ofm_vehicles') ~= 'started' then
        return notify('The owned vehicle service is still starting.', 'error')
    end
    exports.ofm_vehicles:UseGarage(property.garageId)
end

local function purchase(property)
    if submitting then return end
    local confirmation = lib.alertDialog({
        header = property.name,
        content = ('$%d will be charged to your bank. This permanently unlocks its garage for the current character.'):format(property.price),
        centered = true,
        cancel = true,
        labels = { confirm = 'Purchase', cancel = 'Cancel' },
    })
    if confirmation ~= 'confirm' then return end
    submitting = true
    local purchaseId = ('property:%d:%d:%06d'):format(
        GetPlayerServerId(PlayerId()), GetGameTimer(), math.random(0, 999999))
    local response = lib.callback.await('ofm_properties:purchase', false, property.id, purchaseId)
    submitting = false
    if not response or not response.ok then
        return notify(response and response.message or 'The property could not be purchased.', 'error')
    end
    notify(('%s purchased for $%d. Its garage is now active.'):format(response.property, response.price), 'success')
end

local function openProperty(property)
    if submitting then return end
    submitting = true
    local response = lib.callback.await('ofm_properties:status', false, property.id)
    submitting = false
    if not response or not response.ok then
        return notify(response and response.message or 'The property could not be opened.', 'error')
    end
    local options = response.owned and {
        {
            title = 'Open private garage',
            description = 'Retrieve an owned vehicle stored at this property.',
            icon = 'warehouse',
            onSelect = function() useGarage(property) end,
        },
        {
            title = 'Owned property garage',
            description = ('Purchased in %s. Access belongs to this character.'):format(response.property.district),
            icon = 'house-circle-check',
            disabled = true,
        },
    } or {
        {
            title = ('Purchase for $%d'):format(response.property.price),
            description = 'Permanent garage access for this character. No interior is included in this first property slice.',
            icon = 'key',
            onSelect = function() purchase(property) end,
        },
    }
    lib.registerContext({ id = 'ofm_property_' .. property.id, title = property.name, options = options })
    lib.showContext('ofm_property_' .. property.id)
end

CreateThread(function()
    for _, property in ipairs(config.properties) do
        local point = property.coords
        local blip = AddBlipForCoord(point.x, point.y, point.z)
        SetBlipSprite(blip, 40)
        SetBlipColour(blip, 46)
        SetBlipScale(blip, 0.72)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(property.name)
        EndTextCommandSetBlipName(blip)
    end

    while true do
        local sleep = 750
        local active
        local activeDistance
        if not LocalPlayer.state.ofmActivity then
            local coords = GetEntityCoords(PlayerPedId())
            for _, property in ipairs(config.properties) do
                local point = property.coords
                local distance = #(coords - vec3(point.x, point.y, point.z))
                if distance < 30.0 then
                    sleep = 0
                    DrawMarker(1, point.x, point.y, point.z - 1.0,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3.0, 3.0, 0.5,
                        238, 173, 47, 165, false, false, 2, false)
                end
                if distance < 3.0 and (not activeDistance or distance < activeDistance) then
                    active, activeDistance = property, distance
                end
            end
        end

        if active and not submitting then
            sleep = 0
            local driving = GetVehiclePedIsIn(PlayerPedId(), false) ~= 0
            showPrompt(driving and '[E] Use property garage' or '[E] Manage property')
            if IsControlJustReleased(0, 38) then
                hidePrompt()
                if driving then useGarage(active) else openProperty(active) end
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

print('[ofm_properties] Property garage client ready.')
