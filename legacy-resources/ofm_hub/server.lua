local config = require 'config'

local function playerData(source)
    local player = exports.qbx_core:GetPlayer(source)
    return player and player.PlayerData
end

lib.callback.register('ofm_hub:status', function(source)
    local data = playerData(source)
    if not data then return { ok = false } end
    local appearance = MySQL.scalar.await(
        'SELECT 1 FROM playerskins WHERE citizenid = ? LIMIT 1', { data.citizenid })
    local version = MySQL.scalar.await(
        'SELECT onboarding_version FROM ofm_player_guides WHERE citizenid = ?', { data.citizenid })
    return {
        ok = true,
        appearanceReady = appearance ~= nil,
        completed = tonumber(version or 0) >= config.onboardingVersion,
    }
end)

lib.callback.register('ofm_hub:complete', function(source)
    local data = playerData(source)
    if not data then return false end
    MySQL.update.await([[
        INSERT INTO ofm_player_guides (citizenid, onboarding_version, completed_at)
        VALUES (?, ?, current_timestamp())
        ON DUPLICATE KEY UPDATE
          completed_at = IF(onboarding_version < VALUES(onboarding_version), VALUES(completed_at), completed_at),
          onboarding_version = GREATEST(onboarding_version, VALUES(onboarding_version))
    ]], { data.citizenid, config.onboardingVersion })
    return true
end)

print('[ofm_hub] Onboarding, activity browser and handbook ready.')
