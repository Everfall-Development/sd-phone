---@type fun(nuiAction: string, serverEvent: string, onAccepted?: fun(), transform?: fun(response: any): any) NUI-to-server pass-through registrar.
local proxy = require 'client.nui'
---@type FrameworkInfo Detected QBox/QBCore/ESX client framework.
local framework = require 'bridge.shared.framework'

---@type boolean Mirror of the phone's open state; broadcasts never refresh a hidden NUI.
local phoneOpen = false

AddEventHandler('sd-phone:client:openState', function(open)
    phoneOpen = open == true
end)

---Sends a live Services refresh only while the phone is visible.
---@param action string NUI action name.
---@param data? table Optional event payload.
local function sendOpenRefresh(action, data)
    if not phoneOpen then return end
    local message = { action = action }
    if type(data) == 'table' then message.data = data end
    SendNUIMessage(message)
end

---Derives a usable street/cross-street label from a GTA location.
---@param coords table|nil { x, y, z }
---@return string|nil
local function gtaLocation(coords)
    if type(coords) ~= 'table' then return nil end
    local x = tonumber(coords.x or coords[1])
    local y = tonumber(coords.y or coords[2])
    local z = tonumber(coords.z or coords[3]) or 0
    if not x or not y then return nil end

    local succeeded, streetHash, crossingHash = pcall(GetStreetNameAtCoord, x, y, z)
    if not succeeded then return nil end

    local streetSucceeded, street = pcall(GetStreetNameFromHashKey, streetHash)
    local crossingSucceeded, crossing = pcall(GetStreetNameFromHashKey, crossingHash)
    local first = streetSucceeded and type(street) == 'string' and street:match('^%s*(.-)%s*$') or nil
    local second = crossingSucceeded and type(crossing) == 'string' and crossing:match('^%s*(.-)%s*$') or nil
    if first == '' or first == 'NULL' then first = nil end
    if second == '' or second == 'NULL' then second = nil end
    if not first then return second end
    if not second or second == first then return first end
    return ('%s / %s'):format(first, second)
end

---Enriches server directory rows without mutating the cached server response.
---@param response any
---@return any
local function enrichDirectory(response)
    if type(response) ~= 'table' or response.success ~= true then return response end
    local data = response.data
    if type(data) ~= 'table' or type(data.companies) ~= 'table' then return response end

    local enriched = {}
    for key, value in pairs(response) do enriched[key] = value end
    local enrichedData = {}
    for key, value in pairs(data) do enrichedData[key] = value end
    local companies = {}

    for index, company in ipairs(data.companies) do
        if type(company) ~= 'table' then
            companies[index] = company
        else
            local copy = {}
            for key, value in pairs(company) do copy[key] = value end
            local location = gtaLocation(company.coords)
            if location then copy.location = location end
            companies[index] = copy
        end
    end

    enrichedData.companies = companies
    enriched.data = enrichedData
    return enriched
end

proxy('sd-phone:services:directory', 'sd-phone:server:services:directory', nil, enrichDirectory)
proxy('sd-phone:services:callCompany', 'sd-phone:server:services:callCompany')
proxy('sd-phone:services:inbox', 'sd-phone:server:services:inbox')
proxy('sd-phone:services:messageCompany', 'sd-phone:server:services:messageCompany')
proxy('sd-phone:services:replyCompany', 'sd-phone:server:services:replyCompany')
proxy('sd-phone:services:markRead', 'sd-phone:server:services:markRead')

---Notifies an open Businesses app that the active job or duty state may have changed.
local function notifyJobsChanged()
    sendOpenRefresh('sd-phone:services:jobsChanged')
end

if framework.qb then
    RegisterNetEvent('QBCore:Client:OnJobUpdate', notifyJobsChanged)
    RegisterNetEvent('QBCore:Client:SetDuty', notifyJobsChanged)
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', notifyJobsChanged)
    RegisterNetEvent('QBCore:Client:OnPlayerUnload', notifyJobsChanged)
elseif framework.name == 'esx' then
    RegisterNetEvent('esx:setJob', notifyJobsChanged)
    RegisterNetEvent('esx:setDuty', notifyJobsChanged)
    RegisterNetEvent('esx:playerLoaded', notifyJobsChanged)
    RegisterNetEvent('esx:onPlayerLogout', notifyJobsChanged)
end

---Relays server-side duty changes to the visible Businesses directory.
---@param data? table { job?: string }
RegisterNetEvent('sd-phone:client:services:directoryChanged', function(data)
    sendOpenRefresh('sd-phone:services:directoryChanged', data)
end)

---Relays a targeted inbox invalidation without forcing unrelated application refreshes.
---@param data table { job?: string, thread?: string }
RegisterNetEvent('sd-phone:client:services:inbox', function(data)
    sendOpenRefresh('sd-phone:services:inbox', data)
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
