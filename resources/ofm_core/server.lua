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
    if not IsPlayerAceAllowed(player, 'ofm.join') then
        deferrals.done('Open Freemode is in development. Access is limited to authorized testers; test progress will reset.')
        return
    end
    local identity = GetPlayerIdentifierByType(player, 'license')
    if not identity or identities[identity] then
        deferrals.done('A valid, unused game identity is required. Disconnect any other active session and retry.')
        return
    end
    if not databaseReady() then
        deferrals.done('The server is not ready. Please try again shortly.')
        return
    end
    identities[identity] = player
    profiles[player] = { identity = identity }
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
    if not answer.ok or not GetPlayerName(player) or not profiles[player] then
        release(player)
        deferrals.done('Your profile could not be loaded. Please reconnect.')
        return
    end
    profiles[player].account = answer.account
    deferrals.done()
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
    identities[profile.identity] = player
end)

AddEventHandler('playerDropped', function() release(tostring(source)) end)

RegisterNetEvent('ofm:requestSpawn', function()
    local player = tostring(source)
    if not profiles[player] or not profiles[player].account or spawned[player] then return end
    if not databaseReady() then return end
    spawned[player] = true
    TriggerClientEvent('ofm:spawnTestPlayer', tonumber(player), profiles[player].account.id)
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for player in pairs(profiles) do
        DropPlayer(player, 'The development core is restarting. Please reconnect.')
    end
end)
