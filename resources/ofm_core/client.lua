local menu, characters, row, slot = nil, {}, 1, 1
local draft, camera, pending, changing, playing = nil, nil, false, false, false
local buttons, buttonDevice = nil, nil
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
local sections = {edit = {1}, heritage = {2, 3, 4, 5}, appearance = {6, 7, 8, 9}}

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
    if buttons then SetScaleformMovieAsNoLongerNeeded(buttons); buttons, buttonDevice = nil, nil end
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
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedTasksImmediately(ped)
    ClearPedBloodDamage(ped)
    AnimpostfxStop('DeathFailOut')
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

RegisterNetEvent('ofm:respawnCharacter', function(character)
    if not playing or changing or not IsEntityDead(PlayerPedId()) then return end
    DoScreenFadeOut(250)
    apply(character.appearance, false)
end)

CreateThread(function()
    local lastRequest = -2000
    while true do
        if playing and IsEntityDead(PlayerPedId()) then
            -- Death must not trap the tester without access to pause/settings.
            EnableControlAction(0, 199, true)
            EnableControlAction(0, 200, true)
            if IsControlJustPressed(0, 199) or IsControlJustPressed(0, 200) then SetPauseMenuActive(true) end
            if not changing and GetGameTimer() - lastRequest >= 1000 then
                lastRequest = GetGameTimer()
                TriggerServerEvent('ofm:requestRespawn')
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

local function text(x, y, value, scale, selected, right, font)
    SetTextFont(font or 0)
    SetTextScale(scale, scale)
    SetTextColour(selected and 15 or 255, selected and 15 or 255, selected and 15 or 255, 255)
    SetTextJustification(right and 2 or 1)
    SetTextWrap(right and 0.0 or x, right or 1.0)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(value)
    EndTextCommandDisplayText(x, y)
end

local function drawButtons()
    if not buttons then buttons = RequestScaleformMovieInstance('INSTRUCTIONAL_BUTTONS') end
    if not HasScaleformMovieLoaded(buttons) then return end
    local device = IsUsingKeyboardAndMouse(0)
    if buttonDevice ~= device then
        buttonDevice = device
        CallScaleformMovieMethod(buttons, 'CLEAR_ALL')
        for index, item in ipairs({{'Back', 202}, {'Select', 201}, {'Change', 189, 190}, {'Browse', 188, 187}}) do
            BeginScaleformMovieMethod(buttons, 'SET_DATA_SLOT')
            ScaleformMovieMethodAddParamInt(index - 1)
            for i = 2, #item do
                ScaleformMovieMethodAddParamPlayerNameString(GetControlInstructionalButton(0, item[i], true))
            end
            ScaleformMovieMethodAddParamPlayerNameString(item[1])
            EndScaleformMovieMethod()
        end
        CallScaleformMovieMethod(buttons, 'DRAW_INSTRUCTIONAL_BUTTONS')
    end
    DrawScaleformMovieFullscreen(buttons, 255, 255, 255, 255, 0)
end

local function entries()
    if menu == 'slots' then
        local result = {{'Character 1', 'Create'}, {'Character 2', 'Create'}}
        for _, character in ipairs(characters) do
            result[character.slot] = {('Character %d'):format(character.slot), character.appearance.sex == 0 and 'Male' or 'Female'}
        end
        return result
    elseif menu == 'confirm' then
        return {{'Go back'}, {'Save character'}}
    elseif menu == 'features' then
        local result = {}
        for i, name in ipairs(featureNames) do result[i] = {name, tostring(draft.features[i]), (draft.features[i] + 10) / 20} end
        result[21] = {'Back to appearance'}
        return result
    elseif menu == 'edit' then
        return {{'Sex', draft.sex == 0 and 'Male' or 'Female'}, {'Heritage'}, {'Features'}, {'Appearance'}, {'Finish and review'}}
    end
    local result = {}
    for i, fieldIndex in ipairs(sections[menu]) do
        local field = fields[fieldIndex]
        local value = draft[field[2]]
        if field[2] == 'sex' then value = value == 0 and 'Male' or 'Female' end
        result[i] = {field[1], tostring(value)}
        if field[2] == 'resemblance' or field[2] == 'skinMix' then result[i][3] = value / 10 end
    end
    result[#result + 1] = {'Back to character'}
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
            local left = (1.0 - GetSafeZoneSize()) * 0.5 + 0.01
            local width = 0.40 / GetAspectRatio(false)
            local right, center = left + width, left + width / 2
            DrawRect(center, 0.09, width, 0.09, 12, 28, 44, 245)
            text(left + 0.008, 0.055, menu == 'slots' and 'Choose Character' or 'Create Character', 0.72, false, nil, 1)
            DrawRect(center, 0.15, width, 0.03, 0, 0, 0, 245)
            local headings = {features = 'FEATURES', heritage = 'HERITAGE', appearance = 'APPEARANCE', confirm = 'CONFIRM'}
            text(left + 0.008, 0.136, headings[menu] or 'CHARACTER', 0.30)
            text(right, 0.136, ('%d / %d'):format(row, #items), 0.30, false, right - 0.008)
            for index = first, first + count - 1 do
                local y = 0.17 + (index - first) * 0.034
                local selected = index == row
                local shade = selected and 240 or 15
                DrawRect(center, y + 0.016, width, 0.034, shade, shade, shade, 235)
                local item = items[index]
                text(left + 0.008, y, item[1], 0.31, selected)
                if item[2] then text(right, y, item[2], 0.31, selected, right - 0.01) end
                if item[3] then
                    local barWidth = width * 0.22
                    local barLeft = right - barWidth - 0.035
                    DrawRect(barLeft + barWidth / 2, y + 0.017, barWidth, 0.006, 110, 110, 110, 255)
                    DrawRect(barLeft + barWidth * item[3] / 2, y + 0.017, barWidth * item[3], 0.006,
                        selected and 15 or 230, selected and 15 or 230, selected and 15 or 230, 255)
                end
            end
            local foot = 0.178 + count * 0.034
            DrawRect(center, foot + 0.045, width, 0.09, 0, 0, 0, 210)
            -- Draw the description with its own wrap; values never share label text.
            SetTextFont(0); SetTextScale(0.28, 0.28); SetTextColour(255, 255, 255, 255)
            SetTextJustification(1); SetTextWrap(left + 0.008, right - 0.008)
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(pending and 'Saving / loading...' or notice)
            EndTextCommandDisplayText(left + 0.008, foot + 0.005)
            drawButtons()
            if not pending and not changing then
                if pressed(188) then row = (row - 2) % #items + 1 end
                if pressed(187) then row = row % #items + 1 end
                if menu == 'slots' and slot ~= row then slot = row; previewSlot() end
                local direction = pressed(189) and -1 or pressed(190) and 1 or 0
                if direction ~= 0 then
                    local fieldIndex = sections[menu] and sections[menu][row]
                    if fieldIndex then
                        local field = fields[fieldIndex]
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
                    elseif menu == 'edit' and row >= 2 and row <= 4 then
                        menu, row = ({'heritage', 'features', 'appearance'})[row - 1], 1
                    elseif menu == 'edit' and row == 5 then
                        menu, row = 'confirm', 1
                        notice = 'Save this character? Sex is permanent. Appearance editing is not available in this test release.'
                    elseif menu == 'features' and row == 21 then menu, row = 'edit', 3
                    elseif (menu == 'heritage' or menu == 'appearance') and row == 5 then
                        row, menu = menu == 'heritage' and 2 or 4, 'edit'
                    elseif menu == 'confirm' then
                        if row == 1 then menu, row = 'edit', 5
                        else pending = true; TriggerServerEvent('ofm:createCharacter', slot, draft) end
                    end
                elseif pressed(202) then
                    if menu == 'features' then menu, row = 'edit', 3
                    elseif menu == 'heritage' or menu == 'appearance' then row, menu = menu == 'heritage' and 2 or 4, 'edit'
                    elseif menu == 'confirm' then menu, row = 'edit', 5
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
