---@type table Canonical built-in app ids and server-configured availability flags.
local appIds = require 'client.appids'

---@type table<string, string[]> NUI actions that exist only for disabled built-in apps.
local DISABLED_CALLBACKS = {
    groups = {
        'list', 'create', 'invite', 'accept', 'decline', 'leave', 'disband', 'kick',
        'setAvatar', 'setActive',
    },
    pages = { 'list', 'create', 'update', 'delete', 'watch' },
    garages = { 'list', 'waypoint', 'lockstate', 'setlock', 'mileage', 'valet' },
    homes = { 'list', 'waypoint', 'lock', 'keyHolders', 'giveKey', 'removeKey' },
    stocks = { 'market', 'deposit', 'withdraw', 'buy', 'sell', 'holders', 'watch' },
    radio = { 'get', 'leave', 'set', 'saved:list', 'saved:add', 'saved:update', 'saved:remove' },
}

local appgate = {}

---@return table standard disabled-app response
function appgate.disabledResult()
    return {
        success = false,
        code = 'app_disabled',
        message = 'This app is unavailable.',
    }
end

---@param id string app id from configs/apps.lua
---@return boolean enabled
function appgate.enabled(id)
    return appIds.enabled(id)
end

for app, actions in pairs(DISABLED_CALLBACKS) do
    if not appgate.enabled(app) then
        for i = 1, #actions do
            local action = actions[i]
            RegisterNUICallback(('sd-phone:%s:%s'):format(app, action),
                function(_, cb)
                    cb(appgate.disabledResult())
                end)
        end
    end
end

if not appgate.enabled('groups') then
    -- Keep the client export contract for scripts that only query the active crew. The disabled
    -- app must not start its refresh thread or issue a callback just to answer these queries.
    exports('getActiveGroupId', function() return nil end)
    exports('getActiveGroup', function() return nil end)
    exports('refreshActiveGroup', function() end)
end

return appgate
