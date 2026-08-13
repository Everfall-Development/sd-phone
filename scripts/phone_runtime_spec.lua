package.path = './?.lua;./?/init.lua;' .. package.path

-- FiveM scheduler shims used by server.util's limiter sweep. The assertions below exercise the
-- synchronous contracts; no background work is needed in this harness.
CreateThread = function() end
Wait = function() end
GetGameTimer = function() return 0 end
AddEventHandler = function() end
LoadResourceFile = function() return nil end
lib = {}

local function read(path)
    local file = assert(io.open(path, 'r'))
    local value = file:read('*a')
    file:close()
    return value
end

local function has(path, value)
    return read(path):find(value, 1, true) ~= nil
end

local function assertExactDisabled(result)
    assert(type(result) == 'table')
    assert(result.success == false)
    assert(result.code == 'app_disabled')
    assert(result.message == 'This app is unavailable.')
end

local appConfig = dofile('configs/apps.lua')
local configuredApps = {}
for _, app in ipairs(appConfig.Apps) do configuredApps[app.id] = app end
for _, id in ipairs({ 'phone', 'messages', 'maps', 'birdy', 'services', 'ryde', 'weazelnews' }) do
    assert(configuredApps[id] and configuredApps[id].enabled == true, id .. ' must be enabled')
    assert(configuredApps[id].base == true, id .. ' must ship on the default home screen')
end
assert(configuredApps.bank.enabled == false, 'the built-in Bank must stay disabled in favour of ef_banking')

-- Prefix checks are deliberately local and type-safe. Keep this list beside the regression
-- harness so a later dependency update cannot reintroduce the removed ox_lib prefix API.
local startsWith = table.concat({ 'lib', 'string', 'startsWith' }, '.')
local prefixFiles = {
    'bridge/server/garages.lua',
    'bridge/server/housing.lua',
    'server/admin/store.lua',
    'server/birdy/actions.lua',
    'server/cherry/actions.lua',
    'server/messages/actions.lua',
    'server/photogram/actions.lua',
    'server/photos/actions.lua',
    'server/photos/init.lua',
    'server/sim/init.lua',
    'server/streaks/actions.lua',
    'server/vibez/actions.lua',
    'server/voicememos/init.lua',
}
for _, path in ipairs(prefixFiles) do
    assert(not has(path, startsWith), path .. ' still uses the removed prefix helper')
end
assert(has('bridge/server/garages.lua', "raw:sub(1, 1) == '{'"))
assert(has('bridge/server/housing.lua', "raw:sub(1, 1) == '{'"))
assert(has('server/messages/actions.lua', "store.threadPreviews(cid)"))
assert(has('server/messages/actions.lua', "store.threadMessages(cid, conversation"))
assert(has('server/messages/actions.lua', "conversation:sub(1, 2) == 'g-'"))
assert(has('server/admin/store.lua', "r.conversation:sub(1, 2) == 'g-'"))

-- The shared capability module is the only config-derived predicate used by client.appids and
-- server.util. Unknown integrations remain allowed; configured disabled apps do not.
package.preload['configs.config'] = function()
    return {
        Apps = { Apps = {
            { id = 'groups', enabled = false },
            { id = 'garages', enabled = false },
            { id = 'services', enabled = true },
        } },
        Phone = { Number = { Length = 10, Formats = { [10] = '(XXX) XXX-XXXX' } } },
    }
end
package.loaded['shared.appcaps'] = nil
package.loaded['client.appids'] = nil
package.loaded['server.util'] = nil

local appcaps = require 'shared.appcaps'
assert(appcaps.enabled('groups') == false)
assert(appcaps.enabled('garages') == false)
assert(appcaps.enabled('services') == true)
assert(appcaps.enabled('third_party') == true)
assert(appcaps.enabled(nil) == true)

local util = require 'server.util'
assert(util.appEnabled('groups') == false)
assert(util.appEnabled('services') == true)
assert(util.digits('device:555-0100') == '5550100')
assert(util.formatNumber('5550100') == '5550100')

local appIds = require 'client.appids'
assert(appIds.enabled('groups') == false)
assert(appIds.enabled('services') == true)

-- Disabled client callbacks return the release contract without loading the disabled app module.
local nuiCallbacks = {}
local exported = {}
RegisterNUICallback = function(name, handler) nuiCallbacks[name] = handler end
exports = function(name, handler) exported[name] = handler end
package.preload['client.appids'] = function() return appIds end
package.loaded['client.appgate'] = nil
local clientGate = require 'client.appgate'
local clientResult
nuiCallbacks['sd-phone:groups:list']({}, function(result) clientResult = result end)
assertExactDisabled(clientResult)
assert(clientGate.enabled('groups') == false)
assert(exported.getActiveGroupId() == nil)

-- The server callback fallback has the same envelope and hidden-app query includes the disabled
-- rows without touching any of their stores.
local serverCallbacks = {}
lib = { callback = { register = function(name, handler) serverCallbacks[name] = handler end } }
RegisterNetEvent = function() end
package.preload['bridge.server.job'] = function() return { getName = function() return 'unemployed' end } end
package.preload['server.util'] = function() return { appEnabled = appcaps.enabled } end
package.loaded['server.appgate'] = nil
local serverGate = require 'server.appgate'
local serverResult = serverCallbacks['sd-phone:server:groups:list'](1, {})
assertExactDisabled(serverResult)
local hidden = serverGate.hidden(1)
local hiddenGroups = false
local hiddenGarages = false
for _, id in ipairs(hidden) do
    hiddenGroups = hiddenGroups or id == 'groups'
    hiddenGarages = hiddenGarages or id == 'garages'
end
assert(hiddenGroups and hiddenGarages)

-- External notification exports share the same server-side capability gate; a disabled app never
-- reaches the client event, while the Businesses surface remains deliverable.
local notificationExports = {}
exports = function(name, handler) notificationExports[name] = handler end
RegisterCommand = function() end
package.preload['bridge.server.player'] = function()
    return { getSourceByIdentifier = function() return 7 end, getAnySourceByIdentifier = function() return 7 end }
end
package.preload['server.settings.store'] = function() return {} end
package.loaded['server.notifications.init'] = nil
local notificationPushes = 0
TriggerClientEvent = function() notificationPushes = notificationPushes + 1 end
local notifications = require 'server.notifications.init'
assert(notificationExports.notify(7, { appId = 'groups', title = 'blocked' }) == false)
assert(notificationPushes == 0)
assert(notificationExports.notify(7, { appId = '', app = 'groups', title = 'also blocked' }) == false)
assert(notificationPushes == 0)
assert(notificationExports.notify(7, { appId = 'services', title = 'allowed' }) == true)
assert(notificationPushes == 1)
assert(notifications ~= nil)

-- The badge module must not import the disabled groups store at all.
local badgesSource = read('server/badges/init.lua')
assert(has('server/badges/init.lua', "util.appEnabled('groups') and require 'server.groups.store'"))
assert(not badgesSource:find("local groupStore     = require 'server.groups.store'", 1, true))

-- Native-open and incoming-ring gates are source contracts: OpenPhone reports refusal, boats are
-- allowed, and the ring is pushed BEFORE the open is attempted and never gated on it - a refused
-- open (dead, swimming, another NUI focused) must still ring and light the island.
local mainSource = read('client/main.lua')
assert(has('client/main.lua', 'local function OpenPhone()'))
assert(has('client/main.lua', 'if phoneState.open then return true end'))
assert(has('client/main.lua', 'if config.Phone.BlockWhileSwimming and IsPedSwimming(ped) and not IsPedInAnyBoat(ped) then'))
assert(has('client/main.lua', "function OpenApp(appId, link)"))
assert(not has('client/apps/calls.lua', "if not exports['sd-phone']:open() then return end"))
local callsSource = read('client/apps/calls.lua')
local ringPush = callsSource:find("pushCall('sd-phone:call:incoming', data)", 1, true)
local ringOpen = callsSource:find("exports['sd-phone']:open()", ringPush or 1, true)
assert(ringPush and ringOpen and ringPush < ringOpen)
assert(mainSource:find('function OpenPhone%(%)', 1) ~= nil)
assert(has('client/main.lua', "cb(appgate.disabledResult())"))
assert(has('client/main.lua', "cb({ ok = OpenPhone() })"))
local cellTowers = read('configs/celltowers.lua')
for _, disabledAction in ipairs({ 'radio', 'pages:list', 'stocks:market', 'garages:list', 'homes:list' }) do
    assert(not cellTowers:find("'" .. disabledAction .. "'", 1, true), disabledAction .. ' remains in celltower offline/cache policy')
end

-- Exercise the call session's speaker, business-party identity, accept, hangup, and missing
-- session paths with the real actions module and only its framework/database edges stubbed.
package.preload['bridge.server.player'] = function()
    return {
        getIdentifier = function(source) return 'cid-' .. tostring(source) end,
        getName = function(source) return 'Player ' .. tostring(source) end,
    }
end
package.preload['server.settings.store'] = function()
    return {
        isAirplane = function() return false end,
        ensurePhoneNumber = function() return '5550001' end,
        getPhoneNumber = function(cid) return cid == 'cid-2' and '5550002' or '5550001' end,
    }
end
package.preload['server.contacts.store'] = function()
    return {
        listContacts = function() return {} end,
        insertCall = function() end,
        pruneCalls = function() end,
        isBlocked = function() return false end,
        newId = function() return 'call-row' end,
    }
end
package.preload['server.badges.init'] = function() return { pushApp = function() end } end
local moderationMuted = false
local moderationChecks = 0
package.preload['server.admin.moderation'] = function()
    return {
        guard = function(_, scope)
            assert(scope == 'calls')
            moderationChecks = moderationChecks + 1
            if moderationMuted then return { success = false, message = 'Calls muted' } end
        end,
    }
end
package.preload['server.payphone.store'] = function() return { locationForNumber = function() end } end
package.preload['server.service'] = function() return { allows = function() return true end } end
local dialLimitChecks = 0
package.preload['server.util'] = function()
    return {
        ok = function(data) return { success = true, data = data } end,
        fail = function(message) return { success = false, message = message } end,
        digits = function(value) return tostring(value or ''):gsub('%D', '') end,
        rateLimit = function(_, key)
            if key == 'call:dial' then dialLimitChecks = dialLimitChecks + 1 end
            return true
        end,
        cooldown = function() return true end,
        trim = function(value) return tostring(value or '') end,
        initialsFor = function(value) return tostring(value or ''):sub(1, 2) end,
        formatNumber = function(value) return tostring(value or '') end,
        colorFor = function() return '#000000' end,
        smallTable = function() return true end,
    }
end
package.preload['configs.config'] = function()
    return {
        Apps = { Apps = {} },
        Phone = { Items = {} },
        Contacts = { MaxRecents = 20 },
        CellTowers = { DropCallsAfter = false },
        Payphone = { Enabled = false },
    }
end

local clientEvents = {}
TriggerClientEvent = function(name, source, payload)
    clientEvents[#clientEvents + 1] = { name = name, source = source, payload = payload }
end
TriggerEvent = function() end
CreateThread = function() end
SetTimeout = function() end
GetPlayers = function() return {} end
GetConvar = function() return '' end
GetResourceState = function() return 'missing' end
package.loaded['configs.config'] = nil
package.loaded['server.util'] = nil
package.loaded['bridge.server.player'] = nil
package.loaded['server.settings.store'] = nil
package.loaded['server.contacts.store'] = nil
package.loaded['server.calls.actions'] = nil
local calls = require 'server.calls.actions'
local ring = calls.callGroup(1, { { src = 2, cid = 'cid-2' } }, 'Public Relations', 'business:public_relations')
assert(ring.success == true)
assert(dialLimitChecks == 1 and moderationChecks == 1, 'group calls must share dial limits and moderation')
local channel = ring.data.channel
local outgoing
for _, event in ipairs(clientEvents) do
    if event.name == 'sd-phone:client:call:outgoing' and event.source == 1 then outgoing = event.payload end
end
assert(outgoing and outgoing.number == 'business:public_relations')
assert(calls.current(1).data.number == 'business:public_relations')
assert(pcall(calls.setSpeaker, 1, true))
assert(pcall(calls.setSpeaker, 1, false))
assert(calls.accept(2, { channel = channel }).success == true)
assert(calls.current(1).data.number == 'business:public_relations')
assert(pcall(calls.setSpeaker, 1, true))
assert(pcall(calls.setSpeaker, 1, false))
assert(calls.hangup(1, { channel = channel }).success == true)
assert(calls.current(1).data == nil)
moderationMuted = true
local mutedRing = calls.callGroup(1, { { src = 2, cid = 'cid-2' } }, 'Public Relations', 'business:public_relations')
assert(mutedRing.success == false and mutedRing.message == 'Calls muted')
assert(pcall(calls.setSpeaker, 1, true))
assert(calls.hangup(1, { channel = channel }).success == true)

print('phone_runtime_spec: ok')
