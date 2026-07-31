---@type table sd-phone config root (configs/config.lua); read for the MDT jail overrides.
local config    = require 'configs.config'
---@type table Framework detection (bridge.shared.framework): name ('qb'|'esx') + live core handle.
local framework = require 'bridge.shared.framework'
---@type table Player bridge (bridge.server.player): framework-native player object resolution.
local player    = require 'bridge.server.player'

---@type table Jail module; the table returned at end of file. The one capability sd-phone has no
---abstraction for, so it degrades to "no jail installed" rather than throwing.
local jail = {}

---@type table MDT jail settings (configs/mdt.lua Jail); Resource may name a prison resource.
local JAIL = (config.Mdt or {}).Jail or {}

---@type string[] Prison resources probed in order when no explicit override is configured.
local RESOURCES = { 'qbx_prison', 'qb-prison', 'xt-prison' }

---@type string[] Export names tried on the active prison resource, in order.
local EXPORTS = { 'JailPlayer', 'jailPlayer', 'SendToJail', 'sendToJail' }

---@type string[] Client events tried when the active resource exposes no usable export.
local EVENTS = { 'prison:client:Enter', 'police:client:SendToJail' }

---Resolve the running prison resource: an explicit config override wins, otherwise the first
---candidate reporting `started`.
---@return string|nil name resource name, nil when none is running
local function detect()
    local override = JAIL.Resource
    if type(override) == 'string' and override ~= '' and override ~= 'auto' then
        return GetResourceState(override) == 'started' and override or nil
    end
    for i = 1, #RESOURCES do
        if GetResourceState(RESOURCES[i]) == 'started' then return RESOURCES[i] end
    end
    return nil
end

---@type string|nil Active prison resource, resolved once at load.
local ACTIVE = detect()

---Whether this server can actually imprison anyone: a detected prison resource, or the QBCore /
---QBox metadata path that qb-policejob's own jail cell reads.
---@return boolean
function jail.available()
    return ACTIVE ~= nil or framework.qb == true
end

---@type string|nil Resource name of the detected prison system, nil when there is none.
function jail.system()
    return ACTIVE
end

---Try the active prison resource's own export. Each candidate is pcall'd because an export that
---does not exist raises rather than returning nil.
---@param source integer target player server id
---@param months integer sentence length
---@return boolean handled
local function viaExport(source, months)
    if not ACTIVE then return false end
    for i = 1, #EXPORTS do
        local name = EXPORTS[i]
        local ok, res = pcall(function() return exports[ACTIVE][name](nil, source, months) end)
        if ok and res ~= false then return true end
    end
    return false
end

---Write the QBCore / QBox jail metadata the framework's own prison scripts read on spawn.
---@param source integer target player server id
---@param months integer sentence length
local function writeMetadata(source, months)
    if not framework.qb then return end
    local p = player.get(source)
    if not p or not p.Functions or not p.Functions.SetMetaData then return end
    p.Functions.SetMetaData('injail', months)
    p.Functions.SetMetaData('criminalrecord', { hasRecord = true, date = os.date('%Y-%m-%d %H:%M:%S') })
end

---Imprison an online player for `months`. False when nothing on this server can serve a sentence,
---so the caller can fall back to a fine instead of failing the whole booking.
---@param source integer target player server id
---@param months integer sentence length in months
---@return boolean sentenced
function jail.sendToJail(source, months)
    local time = math.floor(tonumber(months) or 0)
    if time < 1 then return false end
    if not source or not GetPlayerName(source) then return false end

    if viaExport(source, time) then
        writeMetadata(source, time)
        return true
    end

    if not framework.qb then return false end

    writeMetadata(source, time)
    for i = 1, #EVENTS do
        TriggerClientEvent(EVENTS[i], source, time)
    end
    return true
end

return jail
