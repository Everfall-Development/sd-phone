---@type table sd-phone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Job bridge (bridge.server.job): the player's live framework job.
local job    = require 'bridge.server.job'
---@type table Gate evaluator (server.gates): reads the `requires` spec both app catalogs share.
local gates  = require 'server.gates'

---@type table App gate; the table returned at end of file. Answers one question for the client:
---which apps must NOT appear on this player's home screen right now.
---
---configs/apps.lua decides which apps a SERVER has. This decides which of them a PLAYER can see,
---and it exists because the answer changes with the job they are holding. The client has no job
---awareness of its own, so it asks on every open and gets the answer for the character that is
---actually loaded.
---
---Two things feed the answer: the terminal rule below, which derives itself from configs/mdt.lua so
---a new department cannot silently have no app, and any `requires` an entry carries, which
---server.gates evaluates. The terminal rule stays hand-written because it is derived rather than
---declared - there is no `requires` to put in configs/apps.lua that knows the MDT's departments.
local appgate = {}

---@type table<string, string[]> Disabled app callback suffixes. These callbacks remain registered
---when an app is off so direct NUI/server requests fail with the same safe response instead of
---falling through to a missing callback or, worse, a partially initialized module.
local DISABLED_CALLBACKS = {
    groups = {
        'list', 'create', 'invite', 'accept', 'decline', 'leave', 'disband', 'kick',
        'setAvatar', 'setActive', 'activeId', 'exportView',
    },
    pages = { 'list', 'create', 'update', 'delete', 'watch' },
    garages = { 'list', 'valet', 'valetInfo' },
    homes = { 'list', 'lock', 'keyHolders', 'giveKey', 'removeKey' },
    stocks = { 'market', 'deposit', 'withdraw', 'buy', 'sell', 'holders', 'watch' },
    radio = { 'get', 'save', 'canTune', 'saved:list', 'saved:add', 'saved:update', 'saved:remove' },
}

---@return table standard disabled-app response
function appgate.disabledResult()
    return {
        success = false,
        code = 'app_disabled',
        message = 'This app is unavailable.',
    }
end

---@param id string app id from configs/apps.lua
---@return boolean enabled
function appgate.enabled(id)
    return require('server.util').appEnabled(id)
end

---Registers safe callback refusals for every disabled app. Enabled modules own their callback
---names and are required normally by server/main.lua, so this cannot collide with a live module.
local function registerDisabledCallbacks()
    for app, suffixes in pairs(DISABLED_CALLBACKS) do
        if not appgate.enabled(app) then
            for i = 1, #suffixes do
                local suffix = suffixes[i]
                lib.callback.register(('sd-phone:server:%s:%s'):format(app, suffix), function()
                    return appgate.disabledResult()
                end)
            end
        end
    end
end

registerDisabledCallbacks()

if not appgate.enabled('radio') then
    RegisterNetEvent('sd-phone:server:radio:presence', function() end)
end

if not appgate.enabled('groups') then
    -- Preserve the external group export names without loading the schema, player hooks, or
    -- actions module. The disabled app must not become a dependency for other resources.
    exports('getActiveGroup', function() return nil end)
    exports('getActiveGroupId', function() return nil end)
    exports('getGroup', function() return nil end)
end

---@type table MDT config (configs/mdt.lua).
local MDT = config.Mdt or {}

---@type boolean Whether the terminal runs on this server at all.
local MDT_ENABLED = MDT.Enabled == true

---@type table<string, string> Framework job name -> terminal domain, built from the departments
---the MDT is already configured with. Deriving it here rather than repeating the job names in
---configs/apps.lua is what keeps a new department from silently having no app: add it to
---Mdt.Departments and its members get the right icon on their next open.
local TERMINAL_JOBS = {}
for _, dept in ipairs(MDT.Departments or {}) do
    if dept.job then
        local kind = dept.type
        TERMINAL_JOBS[dept.job] = (kind == 'ems' or kind == 'doj') and kind or 'leo'
    end
end

---@type table<string, string> App id -> the domain that may see it.
local TERMINAL_APPS = {
    mdt    = 'leo',
    emsmdt = 'ems',
    dojmdt = 'doj',
}

---Every app id this player must not be shown.
---@param src integer player server id
---@return string[] ids
function appgate.hidden(src)
    local out, seen = {}, {}

    for _, app in ipairs(config.Apps.Apps or {}) do
        if app.id and not appgate.enabled(app.id) then
            out[#out + 1] = app.id
            seen[app.id] = true
        end
    end

    -- With no terminal on the server, or no terminal job, every terminal app is hidden. A player
    -- who is neither police nor a medic sees neither icon rather than one that refuses them.
    local domain = MDT_ENABLED and TERMINAL_JOBS[job.getName(src) or ''] or nil
    for id, needs in pairs(TERMINAL_APPS) do
        if needs ~= domain and not seen[id] then out[#out + 1] = id end
    end

    -- Anything an entry gates for itself. A terminal app could also carry a `requires`, so this
    -- appends rather than replaces and the list is deduplicated on the way out.
    local seen = {}
    for i = 1, #out do seen[out[i]] = true end
    for _, id in ipairs(gates.hiddenBaseApps(src)) do
        if not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end

    table.sort(out)
    return out
end

---The client asks on every open, so a job change between opens is picked up with no event to miss.
---Deliberately ungated: a civilian is a valid caller and gets the full hidden list back.
lib.callback.register('sd-phone:server:apps:hidden', function(src)
    return appgate.hidden(src)
end)

return appgate
