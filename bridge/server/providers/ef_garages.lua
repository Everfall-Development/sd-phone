local RESOURCE <const> = 'ef_garages'

---@type table Everfall garages provider. Vehicle ownership remains a read-only DB concern in the
---generic bridge; this module owns ef_garages' runtime collection shape and display details.
local garages = {}

garages.profile = {
    garage = { 'garage' },
    state = { 'state' },
    stored = { [1] = true },
    impound = { [0] = true, [2] = true },
}

---@return boolean
function garages.active()
    return GetResourceState(RESOURCE) == 'started'
end

---@return table|nil
function garages.getCollection()
    if not garages.active() then return nil end
    local succeeded, collection = pcall(function()
        return exports.ef_garages:GetGarages()
    end)
    if succeeded and type(collection) == 'table' then return collection end
    return nil
end

---@param collection table|nil
---@param garageId any
---@return table|nil
function garages.getGarage(collection, garageId)
    if type(collection) ~= 'table' or garageId == nil then return nil end
    local garage = collection[garageId]
    return type(garage) == 'table' and garage or nil
end

---@param garage table|nil
---@return any coords
local function firstAccessPoint(garage)
    local accessPoint = garage and garage.accessPoints and garage.accessPoints[1]
    return accessPoint and accessPoint.coords or nil
end

---@param collection table|nil
---@param garageId any
---@return any coords
function garages.getStoredCoords(collection, garageId)
    return firstAccessPoint(garages.getGarage(collection, garageId))
end

---@param collection table|nil
---@param row table
---@param garageId any
---@return any coords
function garages.getImpoundCoords(collection, row, garageId)
    if type(collection) ~= 'table' then return nil end

    local own = garages.getGarage(collection, garageId)
    if own and (own.type == 'depot' or own.type == 'seizure') then
        return firstAccessPoint(own)
    end

    local wantedType = tonumber(row.state) == 2 and 'seizure' or 'depot'
    local wantedTerritory = row.territory
    local fallback
    for _, garage in pairs(collection) do
        if type(garage) == 'table' and garage.type == wantedType then
            local coords = firstAccessPoint(garage)
            if coords then
                if garage.territory == wantedTerritory and (garage.vehicleType == nil or garage.vehicleType == 'car' or garage.vehicleType == 'all') then
                    return coords
                end
                fallback = fallback or coords
            end
        end
    end
    return fallback
end

---@param collection table|nil
---@param garageId any
---@return string|nil
function garages.getLabel(collection, garageId)
    local garage = garages.getGarage(collection, garageId)
    if garage and type(garage.label) == 'string' and garage.label ~= '' then return garage.label end
    return nil
end

---ef_garages persists kilometres and presents miles in its own UI. Match that player-facing unit.
---@param row table
---@return integer|nil mileage
---@return string|nil unit
function garages.getMileage(row)
    local kilometres = tonumber(row.mileage)
    if not kilometres or kilometres < 0 then return nil end
    return math.floor(kilometres * 0.621371 + 0.5), 'mi'
end

return garages
