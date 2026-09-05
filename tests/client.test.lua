-- Client interaction/state tests with mocked natives, not a visual Enhanced test.
local handlers, threads, sent, keys, messages = {}, {}, {}, {}, {}
local model, frozen, invincible, cam, appliedSex = '', false, false, false, nil
local keyboard, buttonBuilds, buttonDraws, buttonReleased = true, 0, 0, false
local drawnText, promptStrings = {}, {}
local dead, pause = false, false
function IsEntityDead() return dead end
function GetEntityMaxHealth() return 200 end
function SetEntityHealth(_, health) assert(health == 200) end
function ClearPedTasksImmediately() end
function ClearPedBloodDamage() end
function AnimpostfxStop(name) assert(name == 'DeathFailOut') end
function EnableControlAction() end
function IsControlJustPressed(_, control) return keys[control] end
function SetPauseMenuActive(value) pause = value end
function DoScreenFadeOut() end
function RequestScaleformMovieInstance(name) assert(name == 'INSTRUCTIONAL_BUTTONS'); return 4 end
function HasScaleformMovieLoaded() return true end
function IsUsingKeyboardAndMouse() return keyboard end
function GetControlInstructionalButton(_, control) return 'b_' .. control end
function CallScaleformMovieMethod(_, name) if name == 'CLEAR_ALL' then buttonBuilds = buttonBuilds + 1 end end
function DrawScaleformMovieFullscreen() buttonDraws = buttonDraws + 1 end
function SetScaleformMovieAsNoLongerNeeded() buttonReleased = true end
function ScaleformMovieMethodAddParamPlayerNameString(value) promptStrings[#promptStrings + 1] = value end
function GetSafeZoneSize() return 0.95 end
function GetAspectRatio() return 16 / 9 end
local originalPrint = print
function print(value) messages[#messages + 1] = value end
function RegisterNetEvent(name, callback) handlers[name] = callback end
AddEventHandler = RegisterNetEvent
function CreateThread(callback) threads[#threads + 1] = coroutine.create(callback) end
function Wait() coroutine.yield() end
function NetworkIsSessionStarted() return true end
function GetGameTimer() return 10000 end
function TriggerServerEvent(name, ...) sent[#sent + 1] = {name, ...} end
function joaat(value) return value end
function HasModelLoaded() return true end
function GetEntityModel() return model end
function SetPlayerModel(_, value) model = value; appliedSex = value end
function PlayerId() return 1 end
function PlayerPedId() return 2 end
function HasCollisionLoadedAroundEntity() return true end
function FreezeEntityPosition(_, value) frozen = value end
function SetPlayerInvincible(_, value) invincible = value end
function CreateCam() return 3 end
function RenderScriptCams(value) cam = value end
function GetOffsetFromEntityInWorldCoords() return {x = 0, y = 0, z = 0} end
function IsDisabledControlJustPressed(_, value) return keys[value] == true end
function GetCurrentResourceName() return 'ofm_core' end
for name in string.gmatch('RequestModel SetPedDefaultComponentVariation SetPedHeadBlendData SetPedFaceFeature SetPedComponentVariation SetPedHairTint SetPedEyeColor NetworkResurrectLocalPlayer SetEntityHeading RequestCollisionAtCoord SetPlayerControl SetModelAsNoLongerNeeded ShutdownLoadingScreen ShutdownLoadingScreenNui DisplayRadar SetCamCoord PointCamAtEntity SetCamFov DoScreenFadeIn DestroyCam SetTextFont SetTextScale SetTextColour SetTextWrap SetTextJustification BeginTextCommandDisplayText EndTextCommandDisplayText DrawRect DisableAllControlActions BeginScaleformMovieMethod ScaleformMovieMethodAddParamInt EndScaleformMovieMethod', '%S+') do _G[name] = function() end end
function AddTextComponentSubstringPlayerName(value)
    assert(not value:find('~INPUT_', 1, true) and not value:find('b_', 1, true), 'Glyph tokens must be rendered by Scaleform, not text')
    drawnText[value] = true
end
function NetworkResurrectLocalPlayer() dead = false end

dofile('resources/ofm_core/client.lua')
local function tick(key)
    keys = key and {[key] = true} or {}
    local ok, message = coroutine.resume(threads[2])
    assert(ok, message)
end
tick(); tick()
assert(sent[1][1] == 'ofm:requestSpawn')
handlers['ofm:characters']({})
assert(cam and frozen and invincible, 'Preview must not leave the player active in the world')
tick(201) -- create slot 1
tick()
assert(drawnText.Male and drawnText.Sex, 'Label and selection value must be separate text draws')
assert(buttonBuilds == 1 and buttonDraws > 0 and #promptStrings > 0)
keyboard = false; tick()
assert(buttonBuilds == 2, 'Changing input device must rebuild native glyphs')
local requests = #sent
tick(190) -- female
assert(appliedSex == 'mp_f_freemode_01')
tick(202) -- cancel
assert(#sent == requests, 'Cancel must not create a character')
tick(201) -- create again
tick(187); tick(201) -- heritage
tick(190) -- father
tick(202) -- back to heritage row in root
tick(187); tick(187); tick(201) -- appearance
tick(190) -- hair
tick(202) -- back to appearance row in root
tick(187) -- finish and review
tick(201)
tick(187); tick(201) -- save confirmation
assert(sent[#sent][1] == 'ofm:createCharacter' and sent[#sent][2] == 1)
assert(sent[#sent][3].father == 1 and sent[#sent][3].hair == 1, 'Section edits must preserve the same draft')
requests = #sent
tick(201)
assert(#sent == requests, 'Pending confirmation must not repeat the request')
handlers['ofm:characterError']('Retry')
tick(201)
assert(#sent == requests + 1, 'A failed save must allow an explicit retry')
local saved = {id = '99', slot = 1, appearance = sent[#sent][3]}
handlers['ofm:characters']({saved})
tick(201)
assert(sent[#sent][1] == 'ofm:selectCharacter' and sent[#sent][2] == 1)
handlers['ofm:spawnCharacter'](saved)
assert(not cam and not frozen and not invincible, 'Spawn must restore camera, movement and vulnerability')
assert(buttonReleased, 'Native prompt movie must be released on spawn')
assert(messages[#messages]:find('character 99 (slot 1)', 1, true))
handlers['ofm:spawnCharacter'](saved)
assert(#messages == 1, 'Repeated spawn event must not reset a playing character')
dead, keys = true, {[200] = true}
local ok, errorMessage = coroutine.resume(threads[1]); assert(ok, errorMessage)
assert(pause and sent[#sent][1] == 'ofm:requestRespawn', 'Dead player can pause and requests recovery')
handlers['ofm:respawnCharacter'](saved)
assert(not dead and not frozen and not invincible and not cam, 'Death recovery restores a controllable live character')
local requestsAfterRespawn = #sent
coroutine.resume(threads[1])
assert(#sent == requestsAfterRespawn, 'A living player stops requesting death recovery')
handlers.onResourceStop('ofm_core')
assert(not cam and not frozen and not invincible)
originalPrint('Client flow checks passed: preview, cancel, save confirmation, retry, selection and spawn cleanup.')
