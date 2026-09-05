-- Exercise admission decisions with a mocked Cfx boundary; this is not a client join test.
local handlers, emitted, dropped, commands, messages = {}, {}, {}, {}, {}
local allowed, ready, dbOk, reads = false, true, true, 0
local missingExport, failedExport = false, false
local originalPrint = print
function print(message) messages[#messages + 1] = message end
function RegisterCommand(name, callback, restricted) assert(restricted); commands[name] = callback end
local identity = 'license:' .. string.rep('a', 40)
local absent = {}
local expirations = {}
function AddEventHandler(name, callback) handlers[name] = callback end
RegisterNetEvent = AddEventHandler
function Wait() end
function SetTimeout(milliseconds, callback)
    if milliseconds == 120000 then expirations[#expirations + 1] = callback end
end
function IsPlayerAceAllowed() return allowed end
function GetPlayerIdentifierByType() return identity end
function GetPlayerName(player) return not absent[tostring(player)] and 'Test player' or nil end
function GetCurrentResourceName() return 'ofm_core' end
function TriggerClientEvent(name, player, account) emitted[#emitted + 1] = {name, player, account} end
function DropPlayer(player) dropped[#dropped + 1] = player end
promise = {new = function() return {resolve = function(self, value) self.value = value end} end}
Citizen = {Await = function(p) assert(p.value, 'Mock requires a settled callback'); return p.value end}
exports = {ofm_db = {
    isReady = function() if missingExport then error('Resource stopped') end; return ready end,
    openAccount = function(_, _, callback)
        if failedExport then error('Resource export failed') end
        reads = reads + 1; callback(dbOk, {id = '42'})
    end
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
ready, missingExport = true, true
assert(connect(1) and reads == 0, 'A stopped database resource must refuse admission')
commands.ofm_status(0)
assert(messages[#messages] == '[ofm_core] database=unavailable profiles=0')
missingExport, failedExport = false, true
assert(connect(1), 'Export failure must settle the deferral and release admission')
failedExport = false
ready, dbOk = true, false
assert(connect(1), 'Failed profile load must reject admission')
dbOk = true
assert(not connect(1), 'A failed attempt must release its identity reservation')
assert(connect(2), 'Concurrent duplicate identity must be refused')
absent['1'] = true
assert(not connect(3), 'An abandoned attempt without a drop event must not block reconnect')
assert(not connect(3), 'A retried completed handshake with the same temporary ID must be admitted')
source = 10
handlers.playerJoining('3')
for _, expire in ipairs(expirations) do expire() end
assert(#dropped == 0, 'Old connection timers must not drop a joined or replacement session')
assert(connect(10), 'An active joined session must not be replaced by a duplicate attempt')
handlers['ofm:requestSpawn']()
handlers['ofm:requestSpawn']()
assert(#emitted == 1 and emitted[1][2] == 10 and emitted[1][3] == '42', 'Only admitted profile may spawn once')
commands.ofm_status(0)
assert(messages[#messages] == '[ofm_core] database=ready profiles=1')
local count = #messages
commands.ofm_status(10)
assert(#messages == count, 'Status diagnostics must be console-only')
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
handlers.playerDropped()
assert(not connect(4))
expirations[#expirations]()
assert(#dropped == 2 and dropped[2] == '4', 'An unfinished handshake must expire')
assert(not connect(5), 'Expired handshake must release the identity reservation')
originalPrint('Core admission checks passed: access, SQL/resource failure, console status, duplicate identity, join mapping, spawn replay and reconnect.')
