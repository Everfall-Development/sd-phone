---@type fun(nuiAction: string, serverEvent: string) NUI-to-server pass-through registrar.
local proxy = require 'client.nui'

proxy('sd-phone:services:directory', 'sd-phone:server:services:directory')
proxy('sd-phone:services:callCompany', 'sd-phone:server:services:callCompany')
proxy('sd-phone:services:inbox', 'sd-phone:server:services:inbox')
proxy('sd-phone:services:messageCompany', 'sd-phone:server:services:messageCompany')
proxy('sd-phone:services:replyCompany', 'sd-phone:server:services:replyCompany')
proxy('sd-phone:services:markRead', 'sd-phone:server:services:markRead')

---Relays a targeted inbox invalidation without forcing unrelated application refreshes.
---@param data table { job?: string, thread?: string }
RegisterNetEvent('sd-phone:client:services:inbox', function(data)
    SendNUIMessage({ action = 'sd-phone:services:inbox', data = data })
end)

---Drops a GPS waypoint on the selected business location.
---@param payload table { coords?: { x?: number, y?: number } }
RegisterNUICallback('sd-phone:services:locate', function(payload, callback)
    local coords = payload and payload.coords
    local x = coords and tonumber(coords.x)
    local y = coords and tonumber(coords.y)
    if not x or not y then
        callback({ success = false, message = 'No location set' })
        return
    end

    SetNewWaypoint(x, y)
    callback({ success = true })
end)
