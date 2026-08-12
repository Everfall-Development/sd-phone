---@type fun(nuiAction: string, serverEvent: string) NUI->server pass-through registrar (client.nui).
local proxy = require 'client.nui'
---@type table Client job state, kept current by the framework job events.
local job = require 'bridge.client.job'

local function refreshManagementAccess()
    SendNUIMessage({ action = 'sd-phone:weazelnews:feed', data = { type = 'changed' } })
end

-- Thin delegates into server/weazelnews: the public feed plus the staff-gated newsroom
-- (article CRUD, the breaking ticker).
proxy('sd-phone:weazelnews:feed',        'sd-phone:server:weazelnews:feed')
proxy('sd-phone:weazelnews:watch',       'sd-phone:server:weazelnews:watch')
proxy('sd-phone:weazelnews:view',        'sd-phone:server:weazelnews:view')
proxy('sd-phone:weazelnews:save',        'sd-phone:server:weazelnews:save')
proxy('sd-phone:weazelnews:delete',      'sd-phone:server:weazelnews:delete')
proxy('sd-phone:weazelnews:setBreaking', 'sd-phone:server:weazelnews:setBreaking')

-- Refresh the open newsroom when the active job changes so the cogwheel follows the same
-- server-authoritative permission check as every mutation.
job.onChange(function()
    refreshManagementAccess()
end)

-- A character load can keep the same job name/grade while replacing the underlying player
-- object, so refresh the open newsroom even when the job bridge has no value change to report.
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', refreshManagementAccess)
RegisterNetEvent('esx:playerLoaded', refreshManagementAccess)

-- Re-evaluate the staff tools on every phone reopen. The NUI feed is the authoritative snapshot
-- for the newsroom gear, so a stale closed-phone state cannot hide or grant management controls.
AddEventHandler('sd-phone:client:openState', function(open)
    if open then refreshManagementAccess() end
end)
