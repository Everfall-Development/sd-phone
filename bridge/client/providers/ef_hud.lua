local RESOURCE <const> = 'ef_hud'

---@type table Everfall HUD provider.
local HUD = {}

---@return boolean
function HUD.active()
    return GetResourceState(RESOURCE) == 'started'
end

---@param enabled boolean
---@return boolean
function HUD.setHUDCinematicMode(enabled)
    if not HUD.active() then return false end
    local succeeded, result = pcall(function()
        return exports.ef_hud:SetHUDCinematicMode(enabled == true)
    end)
    return succeeded and result ~= false
end

return HUD
