AddEventHandler('playerConnecting', function(_, _, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)
    if not IsPlayerAceAllowed(src, 'ofm.join') then
        deferrals.done('Open Freemode Legacy is in development. Authorized testers only; test progress will reset.')
        return
    end
    deferrals.done()
end)

RegisterCommand('ofm_status', function(src)
    if src ~= 0 then return end
    print('[ofm_session] Legacy Qbox foundation running; supply vendors, owned vehicles, property garages and all four launch activities are installed.')
end, true)

CreateThread(function()
    print('[ofm_session] Legacy foundation started.')
end)
