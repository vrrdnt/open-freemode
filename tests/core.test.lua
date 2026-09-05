-- Exercise admission decisions with a mocked Cfx boundary; this is not a client join test.
local handlers, emitted, dropped = {}, {}, {}
local allowed, ready, dbOk, reads = false, true, true, 0
local identity = 'license:' .. string.rep('a', 40)
function AddEventHandler(name, callback) handlers[name] = callback end
RegisterNetEvent = AddEventHandler
function Wait() end
function SetTimeout() end
function IsPlayerAceAllowed() return allowed end
function GetPlayerIdentifierByType() return identity end
function GetPlayerName() return 'Test player' end
function GetCurrentResourceName() return 'ofm_core' end
function TriggerClientEvent(name, player, account) emitted[#emitted + 1] = {name, player, account} end
function DropPlayer(player) dropped[#dropped + 1] = player end
promise = {new = function() return {resolve = function(self, value) self.value = value end} end}
Citizen = {Await = function(p) assert(p.value, 'Mock requires a settled callback'); return p.value end}
exports = {ofm_db = {
    isReady = function() return ready end,
    openAccount = function(_, _, callback) reads = reads + 1; callback(dbOk, {id = '42'}) end
}}
dofile('resources/ofm_core/server.lua')
local function connect(player)
    source = player
    local done, errorMessage = false, nil
    handlers.playerConnecting(nil, nil, {
        defer = function() end, update = function() end,
        done = function(message) done = true; errorMessage = message end,
    })
    assert(done)
    return errorMessage
end
assert(connect(1) and reads == 0, 'Unauthorized players must not access SQL')
allowed, ready = true, false
assert(connect(1) and reads == 0, 'Unavailable SQL must refuse admission')
ready, dbOk = true, false
assert(connect(1), 'Failed profile load must reject admission')
dbOk = true
assert(not connect(1), 'A failed attempt must release its identity reservation')
assert(connect(2), 'Concurrent duplicate identity must be refused')
source = 10
handlers.playerJoining('1')
handlers['ofm:requestSpawn']()
handlers['ofm:requestSpawn']()
assert(#emitted == 1 and emitted[1][2] == 10 and emitted[1][3] == '42', 'Only admitted profile may spawn once')
source = 99
handlers['ofm:requestSpawn']()
assert(#emitted == 1, 'Unadmitted client must not trigger a spawn')
source = 10
handlers.playerDropped()
assert(not connect(3), 'Disconnect must release the active identity')
source = 11
handlers.playerJoining('3')
handlers.onResourceStop('ofm_core')
assert(#dropped == 1 and dropped[1] == '11', 'Core restart must require profile admission again')
print('Core admission checks passed: access, SQL failure, duplicate identity, join mapping, spawn replay and reconnect.')
