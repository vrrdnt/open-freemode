local profiles, identities, spawned = {}, {}, {}

local function databaseReady()
    local ok, ready = pcall(function() return exports.ofm_db:isReady() end)
    return ok and ready == true
end

RegisterCommand('ofm_status', function(player)
    if player ~= 0 then return end
    local count = 0
    for _, profile in pairs(profiles) do
        if profile.account then count = count + 1 end
    end
    print(('[ofm_core] database=%s profiles=%d'):format(databaseReady() and 'ready' or 'unavailable', count))
end, true)

local function release(player)
    local profile = profiles[player]
    if profile and identities[profile.identity] == player then
        identities[profile.identity] = nil
    end
    profiles[player], spawned[player] = nil, nil
end

AddEventHandler('playerConnecting', function(_, _, deferrals)
    local player = tostring(source)
    deferrals.defer()
    Wait(0)
    local identity = GetPlayerIdentifierByType(player, 'license')
    if not IsPlayerAceAllowed(player, 'ofm.join') then
        local identifier = identity and identity:match('^license:%x+$') and #identity == 48
            and (' Your tester identifier: ' .. identity .. '. Give this to the server administrator privately.') or ''
        deferrals.done('Open Freemode is in development. Access is limited to authorized testers; test progress will reset.' .. identifier)
        return
    end
    local previous = identity and identities[identity]
    if previous then
        local old = profiles[previous]
        if not GetPlayerName(previous) or (previous == player and old and old.accepted and not old.joined) then
            release(previous)
        end
    end
    if not identity or identities[identity] then
        deferrals.done('A valid, unused game identity is required. Disconnect any other active session and retry.')
        return
    end
    if not databaseReady() then
        deferrals.done('The server is not ready. Please try again shortly.')
        return
    end
    identities[identity] = player
    local profile = { identity = identity }
    profiles[player] = profile
    deferrals.update('Loading your test profile...')
    local result = promise.new()
    local settled = false
    local function finish(ok, account)
        if settled then return end
        settled = true
        result:resolve({ ok = ok, account = account })
    end
    SetTimeout(15000, function() finish(false) end)
    local invoked = pcall(function() exports.ofm_db:openAccount(identity, finish) end)
    if not invoked then finish(false) end
    local answer = Citizen.Await(result)
    Wait(0)
    if not answer.ok or not GetPlayerName(player) or profiles[player] ~= profile then
        if profiles[player] == profile then release(player) end
        deferrals.done('Your profile could not be loaded. Please reconnect.')
        return
    end
    profile.account, profile.accepted = answer.account, true
    deferrals.done()
    SetTimeout(120000, function()
        if profiles[player] == profile and not profile.joined then
            DropPlayer(player, 'The connection attempt expired. Please reconnect.')
            release(player)
        end
    end)
end)

AddEventHandler('playerJoining', function(oldId)
    local previous, player = tostring(oldId), tostring(source)
    local profile = profiles[previous]
    if not profile or not profile.account then
        DropPlayer(player, 'Profile admission was interrupted. Please reconnect.')
        return
    end
    profiles[previous] = nil
    profiles[player] = profile
    profile.joined = true
    identities[profile.identity] = player
    local bucket = 100000 + tonumber(player)
    SetRoutingBucketPopulationEnabled(bucket, false)
    SetPlayerRoutingBucket(player, bucket)
end)

AddEventHandler('playerDropped', function() release(tostring(source)) end)

local function characterRequest(action, slot, appearance)
    local player = tostring(source)
    local profile = profiles[player]
    if not profile or not profile.joined or spawned[player] or profile.busy then return end
    if profile.nextRequest and GetGameTimer() < profile.nextRequest then
        TriggerClientEvent('ofm:characterError', tonumber(player), 'Please wait a moment, then select again.')
        return
    end
    profile.nextRequest = GetGameTimer() + 500
    if action ~= 'list' and slot ~= 1 and slot ~= 2 then return end
    if action == 'create' and type(appearance) ~= 'table' then return end
    if not databaseReady() then
        TriggerClientEvent('ofm:characterError', tonumber(player), 'The database is unavailable. Try again shortly.')
        return
    end
    profile.busy = true
    local settled = false
    local function finish(ok, characters)
        if settled then return end
        settled = true
        if profiles[player] ~= profile then return end
        profile.busy = false
        if not ok then
            TriggerClientEvent('ofm:characterError', tonumber(player), 'Character could not be loaded or saved. Try again.')
            return
        end
        if action == 'select' then
            for _, character in ipairs(characters) do
                if character.slot == slot then
                    spawned[player] = character
                    SetPlayerRoutingBucket(player, 0)
                    TriggerClientEvent('ofm:spawnCharacter', tonumber(player), character)
                    return
                end
            end
        end
        TriggerClientEvent('ofm:characters', tonumber(player), characters)
    end
    SetTimeout(15000, function()
        if not settled and profiles[player] == profile then
            settled = true
            DropPlayer(player, 'Character request timed out. Reconnect to check the saved result.')
            release(player)
        end
    end)
    local invoked = pcall(function()
        if action == 'create' then
            exports.ofm_db:createCharacter(profile.account.id, slot, appearance, finish)
        else
            exports.ofm_db:listCharacters(profile.account.id, finish)
        end
    end)
    if not invoked then finish(false) end
end

RegisterNetEvent('ofm:requestSpawn', function() characterRequest('list') end)
RegisterNetEvent('ofm:createCharacter', function(slot, appearance) characterRequest('create', slot, appearance) end)
RegisterNetEvent('ofm:selectCharacter', function(slot) characterRequest('select', slot) end)

RegisterNetEvent('ofm:requestRespawn', function()
    local player = tostring(source)
    local profile, character = profiles[player], spawned[player]
    if not profile or not profile.joined or not character then return end
    local ped = GetPlayerPed(player)
    if ped == 0 or GetEntityHealth(ped) > 100 then profile.deadAt = nil; return end
    local now = GetGameTimer()
    if not profile.deadAt then profile.deadAt = now; return end
    if now - profile.deadAt < 5000 then return end
    profile.deadAt = nil
    TriggerClientEvent('ofm:respawnCharacter', tonumber(player), character)
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for player in pairs(profiles) do
        DropPlayer(player, 'The development core is restarting. Please reconnect.')
    end
end)
