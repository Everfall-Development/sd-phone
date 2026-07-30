local RESOURCE <const> = 'ef_vehiclekeys'

---@type table Everfall vehicle-key provider. The public client export owns access checks, audio,
---network routing, and the requested lock transition.
local vehiclekeys = {}

---@return boolean
function vehiclekeys.active()
    return GetResourceState(RESOURCE) == 'started'
end

---@param vehicle number
---@param plate string
---@return boolean
local function hasAccess(vehicle, plate)
    local succeeded, accessible = pcall(function()
        return exports.ef_vehiclekeys:GetIsVehicleAccessible(vehicle, plate)
    end)
    return succeeded and accessible == true
end

---@param vehicle number
---@param plate string
---@param locked boolean
---@return boolean|nil
function vehiclekeys.setLocked(vehicle, plate, locked)
    if not vehiclekeys.active() or not hasAccess(vehicle, plate) then return nil end

    local current = GetVehicleDoorLockStatus(vehicle) >= 2
    if current == locked then return locked end

    local succeeded = pcall(function()
        exports.ef_vehiclekeys:setVehicleDoorLock(vehicle, nil, true)
    end)
    if not succeeded then return nil end

    local applied = GetVehicleDoorLockStatus(vehicle) >= 2
    if applied ~= locked then return nil end
    return applied
end

return vehiclekeys
