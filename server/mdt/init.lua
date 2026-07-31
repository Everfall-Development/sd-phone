---@type table Boot reporter (server.boot): one console summary instead of per-module prints.
local boot      = require 'server.boot'
---@type table sd-phone config root (configs/config.lua).
local config    = require 'configs.config'
---@type table Shared server helpers (server.util): the configs/apps.lua switch, cleanup hooks.
local util      = require 'server.util'

---@type table MDT persistence (server.mdt.store): schema bootstrap, profiles, shift sessions.
local store     = require 'server.mdt.store'
---@type table Shell handlers (server.mdt.actions): bootstrap and the Home dashboard.
local actions   = require 'server.mdt.actions'
---@type table Persons and vehicles (server.mdt.records).
local records   = require 'server.mdt.records'
---@type table Reports and cases (server.mdt.paperwork).
local paperwork = require 'server.mdt.paperwork'
---@type table Warrants (server.mdt.warrants).
local warrants  = require 'server.mdt.warrants'
---@type table Penal code (server.mdt.offences).
local offences  = require 'server.mdt.offences'
---@type table Booking and sentencing (server.mdt.jail).
local jail      = require 'server.mdt.jail'
---@type table Department personnel (server.mdt.roster).
local roster    = require 'server.mdt.roster'
---@type table CAD (server.mdt.dispatch): in-memory units and calls.
local dispatch  = require 'server.mdt.dispatch'
---@type table Department channel (server.mdt.chat).
local chat      = require 'server.mdt.chat'
---@type table Bulletin board (server.mdt.bulletins).
local bulletins = require 'server.mdt.bulletins'
---@type table Audit viewer (server.mdt.logs).
local logs      = require 'server.mdt.logs'
---@type table Patients and medical files (server.mdt.medical): the medical terminal's person half.
local medical   = require 'server.mdt.medical'
---@type table Treatment protocols (server.mdt.protocols): the medical counterpart of the penal code.
local protocols = require 'server.mdt.protocols'

---@type table MDT config (configs/mdt.lua): the enable switch and the dispatch sweep interval.
local MDT = config.Mdt

---@type boolean Whether this server runs a terminal at all (configs/mdt.lua Enabled). Not taken
---from configs/apps.lua: a companion device enables the MDT in its own catalog, not sd-phone's.
local ENABLED = MDT.Enabled == true

---@type integer Seconds between expiry sweeps of the in-memory call board.
local SWEEP_SECONDS = math.max(5, math.floor(tonumber((MDT.Dispatch or {}).SweepSeconds) or 15))

-- Boot thread: creates the MDT tables and seeds the penal code.
if ENABLED then
    CreateThread(function()
        local ok, err = pcall(store.ensureSchema)
        if not ok then
            boot.schemaFailed('mdt', err)
            return
        end
        boot.schemaReady()
    end)
end

---@type { [1]: string, [2]: table, [3]: string }[] NUI action suffix -> owning module and the
---handler on it. Every handler is already wrapped in access.gated / access.audited by its own
---module, so nothing here decides policy.
local ROUTES = {
    { 'bootstrap',           actions,   'bootstrap' },
    { 'home',                actions,   'home' },

    { 'dispatch:state',      dispatch,  'state' },
    { 'dispatch:setStatus',  dispatch,  'setStatus' },
    { 'dispatch:attach',     dispatch,  'attach' },
    { 'dispatch:detach',     dispatch,  'detach' },
    { 'dispatch:locate',     dispatch,  'locate' },

    { 'persons:search',      records,   'personsSearch' },
    { 'persons:get',         records,   'personsGet' },
    { 'persons:notes',       records,   'personsNotes' },
    { 'persons:flags',       records,   'personsFlags' },
    { 'persons:mugshot',     records,   'personsMugshot' },

    { 'vehicles:search',     records,   'vehiclesSearch' },
    { 'vehicles:get',        records,   'vehiclesGet' },
    { 'vehicles:update',     records,   'vehiclesUpdate' },

    { 'reports:list',        paperwork, 'reportsList' },
    { 'reports:get',         paperwork, 'reportsGet' },
    { 'reports:save',        paperwork, 'reportsSave' },
    { 'reports:delete',      paperwork, 'reportsDelete' },

    { 'cases:list',          paperwork, 'casesList' },
    { 'cases:get',           paperwork, 'casesGet' },
    { 'cases:save',          paperwork, 'casesSave' },
    { 'cases:delete',        paperwork, 'casesDelete' },
    { 'cases:note',          paperwork, 'casesNote' },
    { 'cases:assign',        paperwork, 'casesAssign' },
    { 'cases:linkReport',    paperwork, 'casesLinkReport' },

    { 'warrants:list',       warrants,  'list' },
    { 'warrants:get',        warrants,  'get' },
    { 'warrants:issue',      warrants,  'issue' },
    { 'warrants:close',      warrants,  'close' },

    { 'offences:list',       offences,  'list' },
    { 'offences:save',       offences,  'save' },
    { 'offences:delete',     offences,  'delete' },

    { 'jail:list',           jail,      'list' },
    { 'jail:quote',          jail,      'quote' },
    { 'jail:book',           jail,      'book' },

    { 'roster:list',         roster,    'list' },
    { 'roster:setCallsign',  roster,    'setCallsign' },
    { 'roster:setRadio',     roster,    'setRadio' },
    { 'roster:setGrade',     roster,    'setGrade' },
    { 'roster:dismiss',      roster,    'dismiss' },
    { 'roster:page',         roster,    'page' },
    { 'me:update',           roster,    'meUpdate' },

    { 'chat:history',        chat,      'history' },
    { 'chat:send',           chat,      'send' },

    { 'bulletins:list',      bulletins, 'list' },
    { 'bulletins:save',      bulletins, 'save' },
    { 'bulletins:delete',    bulletins, 'delete' },

    { 'logs:list',           logs,      'list' },

    { 'patients:search',     medical,   'patientsSearch' },
    { 'patients:get',        medical,   'patientsGet' },
    { 'patients:update',     medical,   'patientsUpdate' },

    { 'protocols:list',      protocols, 'list' },
    { 'protocols:save',      protocols, 'save' },
    { 'protocols:delete',    protocols, 'delete' },
}

---Registers one MDT callback under the app's 'sd-phone:server:mdt:' prefix, normalising a
---non-table payload at the boundary.
---@param action string callback name suffix
---@param fn fun(src: integer, payload: table): table
local function register(action, fn)
    lib.callback.register('sd-phone:server:mdt:' .. action, function(src, payload)
        if type(payload) ~= 'table' then payload = {} end
        return fn(src, payload)
    end)
end

---@type string Refusal every callback answers with while the terminal is switched off. The player
---sees the locked screen; the console line below is what names the switch for the server owner.
local DISABLED = 'There is no terminal on this network'

---@type boolean Whether the switched-off hint has already been printed this session.
local hinted = false

---Answers one MDT callback while the terminal is switched off, and says so once. Registering a
---refusal rather than nothing is the point of it: an unregistered callback never answers at all,
---so the terminal would sit on its loading screen forever instead of reaching its locked one.
---@return table envelope
local function refuse()
    if not hinted then
        hinted = true
        print('^3[sd-phone:mdt]^0 a device opened the MDT, but it is off (configs/mdt.lua Enabled = false)')
    end
    return util.fail(DISABLED)
end

for i = 1, #ROUTES do
    local action, module, name = ROUTES[i][1], ROUTES[i][2], ROUTES[i][3]
    local fn = type(module) == 'table' and module[name] or nil
    if not ENABLED then
        register(action, refuse)
    elseif type(fn) == 'function' then
        register(action, fn)
    else
        print(('^1[sd-phone:mdt]^0 no handler for %s (expected %s on its module)'):format(action, name))
    end
end

if ENABLED then
    -- Call board expiry.
    CreateThread(function()
        while true do
            Wait(SWEEP_SECONDS * 1000)
            local ok, err = pcall(dispatch.sweep)
            if not ok then print(('^1[sd-phone:mdt]^0 dispatch sweep failed: %s'):format(err)) end
        end
    end)

    ---Closes a departing officer's shift row and drops their unit off the call board.
    util.onCleanup(function(src, citizenid)
        pcall(dispatch.drop, src)
        if citizenid then pcall(store.closeSession, citizenid) end
    end)

    ---Flushes every open shift on stop, so a restart cannot leave shifts that look like they ran
    ---for days. Guarded to this resource only.
    ---@param resource string name of the resource that stopped
    AddEventHandler('onResourceStop', function(resource)
        if resource ~= GetCurrentResourceName() then return end
        pcall(store.closeOpenSessions)
    end)
end

-- Both exports stay registered with the terminal off, answering inertly. A caller that reaches for
-- a missing export errors where it stands, and a dispatch script has no business dying because
-- this server does not run an MDT.

---Pushes a call onto the CAD from another resource (exports['sd-phone']:mdtCreateCall). Bypasses
---the officer gate because the caller is a resource rather than a player, while keeping every
---clamp. Returns the new call id, or nil when the payload was unusable.
---@param call table { code, type, priority, location, coords, suspect?, weapon?, ttl? }
---@return string|nil callId
exports('mdtCreateCall', function(call)
    if not ENABLED then return nil end
    return dispatch.createCall(call)
end)

---Whether a citizen has an active warrant (exports['sd-phone']:mdtIsWanted). The cheap predicate
---plate readers and NPC patrols read.
---@param citizenid string
---@return boolean wanted
exports('mdtIsWanted', function(citizenid)
    if not ENABLED then return false end
    return warrants.isWanted(citizenid) == true
end)
