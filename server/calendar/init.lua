---@type table Boot reporter (server.boot).
local boot = require 'server.boot'
---@type table Authoritative Calendar persistence.
local store = require 'server.calendar.store'
---@type table Citizen-scoped Calendar actions.
local actions = require 'server.calendar.actions'

CreateThread(function()
    local ok, err = pcall(store.ensureSchema)
    if not ok then
        boot.schemaFailed('calendar', err)
        return
    end
    boot.schemaReady()
    lib.print.debug('[sd-phone] Calendar schema ready')
end)

lib.callback.register('sd-phone:server:calendar:list', function(src)
    return actions.list(src)
end)

lib.callback.register('sd-phone:server:calendar:save', function(src, payload)
    return actions.save(src, payload)
end)

lib.callback.register('sd-phone:server:calendar:delete', function(src, payload)
    return actions.delete(src, payload)
end)

lib.callback.register('sd-phone:server:calendar:note', function(src, payload)
    return actions.saveDayNote(src, payload)
end)

return actions
