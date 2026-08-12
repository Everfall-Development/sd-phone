---@type table sd-phone config root (configs/config.lua).
local config = require 'configs.config'

---@type table<string, true> Apps switched off in configs/apps.lua.
local disabled = {}
for _, app in ipairs((config.Apps or {}).Apps or {}) do
    if app.id and app.enabled == false then disabled[app.id] = true end
end

---Whether an app is switched on in configs/apps.lua. Unknown ids stay enabled so external
---integrations can continue to use their own application labels without being accidentally
---blocked; built-in ids are the entries represented in the config-derived set above.
---@param id any app id as configs/apps.lua names it
---@return boolean enabled
local function enabled(id)
    if type(id) ~= 'string' then return true end
    return not disabled[id] and not disabled[id:lower()]
end

return { enabled = enabled }
