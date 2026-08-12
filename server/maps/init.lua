---@type table Boot reporter (server.boot): one console summary instead of per-module prints.
local boot = require 'server.boot'

---@type table Maps persistence layer (server.maps.store): one JSON row per citizenid.
local store   = require 'server.maps.store'
---@type table Authoritative Maps handlers (server.maps.actions): sanitize + cap + scope.
local actions = require 'server.maps.actions'
---@type table AirShare core (server.share.core): per-kind delivery handler registry.
local share   = require 'server.share.core'

-- Delivery handler for accepted pin AirShares.
share.registerHandler('pin', actions.deliverShare)

---Bootstraps the pins schema once at boot.
CreateThread(function()
    local ok, err = pcall(store.ensureSchema)
    if not ok then
        boot.schemaFailed('maps', err)
        return
    end
    boot.schemaReady()
end)

-- NUI callbacks: thin delegates into server.maps.actions.
lib.callback.register('sd-phone:server:maps:list', function(src)
    return actions.list(src)
end)

lib.callback.register('sd-phone:server:maps:save', function(src, payload)
    return actions.save(src, payload)
end)

lib.callback.register('sd-phone:server:maps:sharePin', function(src, payload)
    payload = type(payload) == 'table' and payload or {}
    return actions.requestShare(src, payload.target, payload)
end)

-- Development-only map tools. Registration stays server-side so ox_lib owns command
-- metadata and the calibration command is protected by the command.mapcal ACE.
lib.addCommand('mapcal', {
    help = 'Calibrate the phone map',
    restricted = true,
}, function(source)
    if source <= 0 then return end
    TriggerClientEvent('sd-phone:client:maps:calibrateNext', source)
end)

lib.addCommand('mapcaldone', {
    help = 'Stop phone map calibration',
}, function(source)
    if source <= 0 then return end
    TriggerClientEvent('sd-phone:client:maps:calibrateDone', source)
end)

lib.addCommand('maptiles', {
    help = 'Check phone map tiles',
}, function(source)
    if source <= 0 then return end
    TriggerClientEvent('sd-phone:client:maps:tilecheck', source)
end)
