---@type table Boot reporter (server.boot): one console summary instead of per-module prints.
local boot = require 'server.boot'
---@type table Company inbox persistence.
local msgstore = require 'server.services.msgstore'
---@type table Wallet invoice persistence.
local invoicestore = require 'server.services.invoicestore'
---@type table Focused Businesses directory, calling, and messaging authority.
local businesses = require 'server.services.businesses'
---@type table Wallet invoice actions. Business management callbacks are intentionally not registered.
local invoices = require 'server.services.invoices'
---@type table Shared server helpers.
local util = require 'server.util'

-- Businesses retains the existing message history, and Banking retains existing personal and
-- received invoices. Legacy Services preferences, saved jobs, company management, and roster
-- schemas are not bootstrapped by the release surface.
CreateThread(function()
    local succeeded, err = pcall(function()
        msgstore.ensureSchema()
        invoicestore.ensureSchema()
    end)
    if not succeeded then
        boot.schemaFailed('businesses', err)
        return
    end
    boot.schemaReady()
end)

lib.callback.register('sd-phone:server:services:directory', function(source)
    return businesses.directory(source)
end)

lib.callback.register('sd-phone:server:services:callCompany', function(source, payload)
    return businesses.call(source, payload)
end)

lib.callback.register('sd-phone:server:services:inbox', function(source)
    return businesses.inbox(source)
end)

lib.callback.register('sd-phone:server:services:messageCompany', function(source, payload)
    return businesses.message(source, payload)
end)

lib.callback.register('sd-phone:server:services:replyCompany', function(source, payload)
    return businesses.reply(source, payload)
end)

lib.callback.register('sd-phone:server:services:markRead', function(source, payload)
    return businesses.markRead(source, payload)
end)

-- Open phones refresh the public directory when a QBox job or duty state changes. The client
-- drops this event while the phone is closed, so a duty toggle does not fan server reads out to
-- hidden NUIs; opening Businesses always performs its own fresh read.
local function broadcastDirectoryChanged(currentName, previousName)
    TriggerClientEvent('sd-phone:client:services:directoryChanged', -1, {
        job = currentName,
        previousJob = previousName,
    })
end

AddEventHandler('QBCore:Server:OnJobUpdate', function(_, currentJob, previousJob)
    local currentName = type(currentJob) == 'table' and currentJob.name or nil
    local previousName = type(previousJob) == 'table' and previousJob.name or nil
    broadcastDirectoryChanged(currentName, previousName)
end)

AddEventHandler('QBCore:Server:SetDuty', function()
    broadcastDirectoryChanged()
end)

-- Wallet owns every reachable invoice callback. There is no Services-side create, list, or
-- cancel authority, so company invoicing and management cannot be invoked through stale NUI.
lib.callback.register('sd-phone:server:banking:invoices:create', function(source, payload)
    return invoices.personalCreate(source, payload)
end)

lib.callback.register('sd-phone:server:banking:invoices:sent', function(source)
    return invoices.personalSent(source)
end)

lib.callback.register('sd-phone:server:banking:invoices:cancel', function(source, payload)
    return invoices.personalCancel(source, payload)
end)

lib.callback.register('sd-phone:server:banking:invoices:received', function(source)
    return invoices.received(source)
end)

lib.callback.register('sd-phone:server:banking:invoices:pay', function(source, payload)
    return invoices.pay(source, payload)
end)

---Returns the current live Businesses directory without caching an unavailable resource result.
---@return table[]|nil companies
---@return string|nil error
exports('getCompanyDirectory', function()
    return businesses.companyList()
end)

---Sends a customer message to a business through the same authoritative path as the phone NUI.
---@param source number
---@param payload table
---@return { success: boolean, message?: string }
exports('messageCompany', function(source, payload)
    if type(source) ~= 'number' then return util.fail('Player not found') end
    local result = businesses.message(source, payload)
    return { success = result.success == true, message = result.message }
end)
