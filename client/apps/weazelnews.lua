---@type fun(nuiAction: string, serverEvent: string) NUI->server pass-through registrar (client.nui).
local proxy = require 'client.nui'

-- Thin delegates into server/weazelnews: the public feed plus the boss-gated newsroom
-- (article CRUD, the breaking ticker).
proxy('sd-phone:weazelnews:feed',        'sd-phone:server:weazelnews:feed')
proxy('sd-phone:weazelnews:watch',       'sd-phone:server:weazelnews:watch')
proxy('sd-phone:weazelnews:view',        'sd-phone:server:weazelnews:view')
proxy('sd-phone:weazelnews:save',        'sd-phone:server:weazelnews:save')
proxy('sd-phone:weazelnews:delete',      'sd-phone:server:weazelnews:delete')
proxy('sd-phone:weazelnews:setBreaking', 'sd-phone:server:weazelnews:setBreaking')
