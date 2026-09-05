-- Client interaction/state tests with mocked natives, not a visual Enhanced test.
local handlers, threads, sent, keys, messages = {}, {}, {}, {}, {}
local model, frozen, invincible, cam, appliedSex = '', false, false, false, nil
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
for name in string.gmatch('RequestModel SetPedDefaultComponentVariation SetPedHeadBlendData SetPedFaceFeature SetPedComponentVariation SetPedHairTint SetPedEyeColor NetworkResurrectLocalPlayer SetEntityHeading RequestCollisionAtCoord SetPlayerControl SetModelAsNoLongerNeeded ShutdownLoadingScreen ShutdownLoadingScreenNui DisplayRadar SetCamCoord PointCamAtEntity SetCamFov DoScreenFadeIn DestroyCam SetTextFont SetTextScale SetTextColour SetTextWrap SetTextOutline BeginTextCommandDisplayText AddTextComponentSubstringPlayerName EndTextCommandDisplayText DrawRect DisableAllControlActions', '%S+') do _G[name] = function() end end

dofile('resources/ofm_core/client.lua')
local function tick(key)
    keys = key and {[key] = true} or {}
    local ok, message = coroutine.resume(threads[1])
    assert(ok, message)
end
tick(); tick()
assert(sent[1][1] == 'ofm:requestSpawn')
handlers['ofm:characters']({})
assert(cam and frozen and invincible, 'Preview must not leave the player active in the world')
tick(201) -- create slot 1
local requests = #sent
tick(190) -- female
assert(appliedSex == 'mp_f_freemode_01')
tick(202) -- cancel
assert(#sent == requests, 'Cancel must not create a character')
tick(201) -- create again
for _ = 1, 10 do tick(187) end -- finish and review
tick(201)
tick(187); tick(201) -- save confirmation
assert(sent[#sent][1] == 'ofm:createCharacter' and sent[#sent][2] == 1)
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
assert(messages[#messages]:find('character 99 (slot 1)', 1, true))
handlers['ofm:spawnCharacter'](saved)
assert(#messages == 1, 'Repeated spawn event must not reset a playing character')
handlers.onResourceStop('ofm_core')
assert(not cam and not frozen and not invincible)
originalPrint('Client flow checks passed: preview, cancel, save confirmation, retry, selection and spawn cleanup.')
