local menu, characters, row, slot = nil, {}, 1, 1
local draft, camera, pending, changing, playing = nil, nil, false, false, false
local notice = 'Choose a character. Test progress will reset before public launch.'
local featureNames = {'Nose width', 'Nose height', 'Nose length', 'Nose bridge', 'Nose tip', 'Nose shift',
    'Brow height', 'Brow depth', 'Cheekbone height', 'Cheekbone width', 'Cheek fullness', 'Eye opening',
    'Lip thickness', 'Jaw width', 'Jaw shape', 'Chin height', 'Chin length', 'Chin width', 'Chin shape', 'Neck width'}
local fields = {
    {'Sex', 'sex', 0, 1}, {'Father', 'father', 0, 20}, {'Mother', 'mother', 21, 41},
    {'Resemblance', 'resemblance', 0, 10}, {'Skin blend', 'skinMix', 0, 10},
    {'Hair', 'hair', 0, 22}, {'Hair color', 'hairColor', 0, 63},
    {'Hair highlight', 'hairHighlight', 0, 63}, {'Eye color', 'eyes', 0, 30},
}

local function newAppearance()
    local features = {}
    for i = 1, 20 do features[i] = 0 end
    return {version = 1, sex = 0, father = 0, mother = 21, resemblance = 5, skinMix = 5,
        hair = 0, hairColor = 0, hairHighlight = 0, eyes = 0, features = features}
end

local function appearance(ped, value)
    SetPedHeadBlendData(ped, value.father, value.mother, 0, value.father, value.mother, 0,
        value.resemblance / 10.0, value.skinMix / 10.0, 0.0, false)
    for i = 1, 20 do SetPedFaceFeature(ped, i - 1, value.features[i] / 10.0) end
    SetPedComponentVariation(ped, 2, value.hair, 0, 0)
    SetPedHairTint(ped, value.hairColor, value.hairHighlight)
    SetPedEyeColor(ped, value.eyes)
end

local function clearPreview()
    RenderScriptCams(false, false, 0, true, true)
    if camera then DestroyCam(camera, false); camera = nil end
    FreezeEntityPosition(PlayerPedId(), false)
    SetPlayerInvincible(PlayerId(), false)
    DisplayRadar(true)
end

local function apply(value, preview)
    changing = true
    local model = joaat(value.sex == 0 and 'mp_m_freemode_01' or 'mp_f_freemode_01')
    RequestModel(model)
    local deadline = GetGameTimer() + 15000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then
        changing = false
        notice = 'Character model could not load. Reconnect to retry.'
        print(notice)
        return false
    end
    if GetEntityModel(PlayerPedId()) ~= model then SetPlayerModel(PlayerId(), model) end
    local ped = PlayerPedId()
    NetworkResurrectLocalPlayer(-1037.7, -2737.8, 20.17, 180.0, true, false)
    ped = PlayerPedId()
    SetPedDefaultComponentVariation(ped)
    appearance(ped, value)
    SetEntityHeading(ped, 180.0)
    RequestCollisionAtCoord(-1037.7, -2737.8, 20.17)
    FreezeEntityPosition(ped, true)
    deadline = GetGameTimer() + 10000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do Wait(0) end
    SetPlayerControl(PlayerId(), true, 0)
    SetModelAsNoLongerNeeded(model)
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    if preview then
        SetPlayerInvincible(PlayerId(), true)
        DisplayRadar(false)
        if not camera then camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true) end
        local position = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.0, 0.6)
        SetCamCoord(camera, position.x, position.y, position.z)
        PointCamAtEntity(camera, ped, 0.0, 0.0, 0.6, true)
        SetCamFov(camera, 40.0)
        RenderScriptCams(true, false, 0, true, true)
    else
        clearPreview()
    end
    DoScreenFadeIn(500)
    changing = false
    return true
end

local function selectedCharacter()
    for _, character in ipairs(characters) do
        if character.slot == slot then return character end
    end
end

local function previewSlot()
    local character = selectedCharacter()
    draft = character and character.appearance or newAppearance()
    apply(draft, true)
end

RegisterNetEvent('ofm:characters', function(result)
    if playing then return end
    characters, pending, menu, row = result, false, 'slots', slot
    notice = 'Choose a character. Test progress will reset before public launch.'
    previewSlot()
end)

RegisterNetEvent('ofm:characterError', function(message)
    pending = false
    notice = message
end)

RegisterNetEvent('ofm:spawnCharacter', function(character)
    if playing or changing then return end
    pending = true
    if apply(character.appearance, false) then
        playing, menu, pending = true, nil, false
        print(('Open Freemode character %s (slot %d) loaded. Test progress will reset.'):format(character.id, character.slot))
    end
end)

local function text(x, y, value, scale, selected)
    SetTextFont(0)
    SetTextScale(scale, scale)
    SetTextColour(selected and 15 or 255, selected and 15 or 255, selected and 15 or 255, 255)
    SetTextWrap(x, 0.345)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(value)
    EndTextCommandDisplayText(x, y)
end

local function entries()
    if menu == 'slots' then
        local result = {'Character 1 - Create', 'Character 2 - Create'}
        for _, character in ipairs(characters) do
            result[character.slot] = ('Character %d - %s'):format(character.slot, character.appearance.sex == 0 and 'Male' or 'Female')
        end
        return result
    elseif menu == 'confirm' then
        return {'Go back', 'Save character'}
    elseif menu == 'features' then
        local result = {}
        for i, name in ipairs(featureNames) do result[i] = name .. '  < ' .. draft.features[i] .. ' >' end
        result[21] = 'Back to appearance'
        return result
    end
    local result = {}
    for i, field in ipairs(fields) do
        local value = draft[field[2]]
        if field[2] == 'sex' then value = value == 0 and 'Male' or 'Female' end
        result[i] = field[1] .. '  < ' .. value .. ' >'
    end
    result[#fields + 1], result[#fields + 2] = 'Facial features', 'Finish and review'
    return result
end

local function pressed(control)
    return IsDisabledControlJustPressed(0, control)
end

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(100) end
    local lastRequest = -3000
    while not playing do
        Wait(0)
        if not menu and not pending and GetGameTimer() - lastRequest > 3000 then
            lastRequest = GetGameTimer()
            TriggerServerEvent('ofm:requestSpawn')
        end
        if menu then
            DisableAllControlActions(0)
            local items = entries()
            local first = math.max(1, math.min(row - 3, #items - 7))
            local count = math.min(8, #items)
            DrawRect(0.185, 0.10, 0.33, 0.075, 15, 35, 50, 245)
            text(0.03, 0.075, menu == 'slots' and 'Choose character' or 'Create character', 0.55)
            for index = first, first + count - 1 do
                local y = 0.15 + (index - first) * 0.04
                local selected = index == row
                local shade = selected and 240 or 15
                DrawRect(0.185, y + 0.017, 0.33, 0.039, shade, shade, shade, 235)
                text(0.03, y, items[index], 0.33, selected)
            end
            local foot = 0.16 + count * 0.04
            text(0.03, foot, pending and 'Saving / loading...' or notice, 0.30)
            text(0.03, foot + 0.10, '~INPUT_FRONTEND_UP~ ~INPUT_FRONTEND_DOWN~ Browse   ~INPUT_FRONTEND_LEFT~ ~INPUT_FRONTEND_RIGHT~ Change', 0.28)
            text(0.03, foot + 0.14, '~INPUT_FRONTEND_ACCEPT~ Select   ~INPUT_FRONTEND_CANCEL~ Back', 0.28)
            if not pending and not changing then
                if pressed(188) then row = (row - 2) % #items + 1 end
                if pressed(187) then row = row % #items + 1 end
                if menu == 'slots' and slot ~= row then slot = row; previewSlot() end
                local direction = pressed(189) and -1 or pressed(190) and 1 or 0
                if direction ~= 0 then
                    if menu == 'edit' and fields[row] then
                        local field = fields[row]
                        draft[field[2]] = math.max(field[3], math.min(field[4], draft[field[2]] + direction))
                        if field[2] == 'sex' then apply(draft, true) else appearance(PlayerPedId(), draft) end
                    elseif menu == 'features' and row <= 20 then
                        draft.features[row] = math.max(-10, math.min(10, draft.features[row] + direction))
                        appearance(PlayerPedId(), draft)
                    end
                end
                if pressed(201) then
                    if menu == 'slots' then
                        if selectedCharacter() then
                            pending = true
                            TriggerServerEvent('ofm:selectCharacter', slot)
                        else
                            menu, row = 'edit', 1
                            notice = 'Preview your appearance. Nothing is saved until you confirm.'
                        end
                    elseif menu == 'edit' and row == #fields + 1 then menu, row = 'features', 1
                    elseif menu == 'edit' and row == #fields + 2 then
                        menu, row = 'confirm', 1
                        notice = 'Save this character? Sex is permanent. Appearance editing is not available in this test release.'
                    elseif menu == 'features' and row == 21 then menu, row = 'edit', #fields + 1
                    elseif menu == 'confirm' then
                        if row == 1 then menu, row = 'edit', #fields + 2
                        else pending = true; TriggerServerEvent('ofm:createCharacter', slot, draft) end
                    end
                elseif pressed(202) then
                    if menu == 'features' then menu, row = 'edit', #fields + 1
                    elseif menu == 'confirm' then menu, row = 'edit', #fields + 2
                    elseif menu == 'edit' then menu, row = 'slots', slot; previewSlot()
                    end
                    notice = 'Choose a character. Test progress will reset before public launch.'
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then clearPreview() end
end)
