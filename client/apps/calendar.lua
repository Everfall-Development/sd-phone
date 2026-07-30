---@type fun(nuiAction: string, serverEvent: string) NUI-to-server callback proxy.
local proxy = require 'client.nui'

proxy('sd-phone:calendar:list', 'sd-phone:server:calendar:list')
proxy('sd-phone:calendar:save', 'sd-phone:server:calendar:save')
proxy('sd-phone:calendar:delete', 'sd-phone:server:calendar:delete')
proxy('sd-phone:calendar:note', 'sd-phone:server:calendar:note')

---Forwards canonical server mutations to the phone NUI. ef_tablet registers the same global
---client event separately and forwards it into its own NUI.
RegisterNetEvent('sd-phone:client:calendar:changed', function(change)
    SendNUIMessage({ action = 'sd-phone:calendar:changed', data = change })
    lib.print.debug(('[sd-phone] Calendar live change forwarded operation=%s'):format(
        tostring(change and change.operation)
    ))
end)
