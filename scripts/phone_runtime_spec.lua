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

local function exists(path)
    local file = io.open(path, 'r')
    if not file then return false end
    file:close()
    return true
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

-- External first-party integrations use native SD Phone contracts, while the phone's bundled
-- compatibility surface remains intact for third-party resources.
assert(has('fxmanifest.lua', "provide 'lb-phone'"))
assert(exists('client/compat/lbphone.lua'))
assert(exists('server/compat/lbphone/init.lua'))
assert(has('client/main.lua', "require 'client.compat.lbphone'"))
assert(has('server/main.lua', "require 'server.compat.lbphone.init'"))
assert(has('server/main.lua', "require 'server.compat.lbphone.clientsupport'"))
assert(has('client/customapps.lua', 'data.onUse'))
assert(has('server/mail/init.lua', "exports('createMailAccount'"))
assert(has('server/mail/init.lua', 'return actions.signUp(source, payload)'))
assert(has('server/birdy/init.lua', "exports('deleteBirdyAccount'"))
assert(has('server/birdy/actions.lua', 'function actions.deleteAccountByHandle(rawHandle)'))

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

-- Prop model streaming yields. Closing or replacing the pose during that yield must invalidate
-- the stale creator on both the local holder and remote-replica paths, and the idle watchdog must
-- clean any orphan that survives an unexpected native interruption.
local poseSource = read('client/pose.lua')
assert(poseSource:find('local propGeneration = 0', 1, true))
assert(poseSource:find('generation ~= propGeneration or not pose.shouldHold() or ped ~= cache.ped', 1, true))
assert(poseSource:find('elseif prop then', 1, true))
assert(poseSource:find('pose.deleteProp(obj)', 1, true))
assert(poseSource:find('DetachEntity(obj, true, true)', 1, true))
assert(poseSource:find('SetEntityAsMissionEntity(obj, true, true)', 1, true))
assert(mainSource:find('local remotePropGenerations = {}', 1, true))
assert(mainSource:find('generation ~= remotePropGenerations[source] or currentPed ~= ped', 1, true))

-- Camera and video calls create GTA's native mobile-phone entity outside pose.lua. A shell close
-- must tear those owners down directly because the retained React app tree may not unmount.
local cameraSource = read('client/apps/camera.lua')
assert(cameraSource:find("AddEventHandler('sd-phone:client:openState'", 1, true))
assert(cameraSource:find('stopFlash()', 1, true))
assert(cameraSource:find('exitCameraView()', 1, true))
local callsSource = read('client/apps/calls.lua')
assert(callsSource:find("AddEventHandler('sd-phone:client:openState'", 1, true))
assert(callsSource:find('setVideoCamera(false)', 1, true))
assert(callsSource:find("TriggerServerEvent('sd-phone:server:call:video:stop')", 1, true))
local cellTowers = read('configs/celltowers.lua')
for _, disabledAction in ipairs({ 'radio', 'pages:list', 'stocks:market', 'garages:list', 'homes:list' }) do
    assert(not cellTowers:find("'" .. disabledAction .. "'", 1, true), disabledAction .. ' remains in celltower offline/cache policy')
end

-- Exercise the call session's speaker, business-party identity, accept, hangup, and missing
-- session paths with the real actions module and only its framework/database edges stubbed.
local phoneNumbers = {
    ['cid-1'] = '5550001',
    ['cid-2'] = '5550002',
    ['cid-3'] = '5550003',
    ['cid-4'] = '5550004',
}
local callerIds = { ['cid-1'] = false }
local numberOwners = {}
for cid, number in pairs(phoneNumbers) do numberOwners[number] = cid end
local callRows = {}
local blockedChecks = {}
package.preload['bridge.server.player'] = function()
    return {
        getIdentifier = function(source) return 'cid-' .. tostring(source) end,
        getName = function(source) return 'Player ' .. tostring(source) end,
        getAnySourceByIdentifier = function(cid)
            return tonumber(tostring(cid):match('cid%-(%d+)'))
        end,
    }
end
package.preload['server.settings.store'] = function()
    return {
        isAirplane = function() return false end,
        ensurePhoneNumber = function(cid) return phoneNumbers[cid] end,
        getPhoneNumber = function(cid) return phoneNumbers[cid] end,
        getCitizenByNumber = function(number) return numberOwners[number] end,
        getCallerId = function(cid) return callerIds[cid] ~= false end,
    }
end
package.preload['server.contacts.store'] = function()
    return {
        listContacts = function() return {} end,
        insertCall = function(_, citizenid, row)
            callRows[#callRows + 1] = { citizenid = citizenid, row = row }
        end,
        pruneCalls = function() end,
        isBlocked = function(citizenid, number)
            blockedChecks[#blockedChecks + 1] = { citizenid = citizenid, number = number }
            return false
        end,
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
local serverEvents = {}
TriggerEvent = function(name, payload, source)
    serverEvents[#serverEvents + 1] = { name = name, payload = payload, source = source }
end
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

local function latestClientEvent(name, source, channel)
    for i = #clientEvents, 1, -1 do
        local event = clientEvents[i]
        if event.name == name and event.source == source
            and (not channel or event.payload.channel == channel) then
            return event
        end
    end
end

local function latestServerEvent(name)
    for i = #serverEvents, 1, -1 do
        if serverEvents[i].name == name then return serverEvents[i] end
    end
end

local ring = calls.callGroup(1, { { src = 2, cid = 'cid-2' } }, 'Public Relations', 'business:public_relations')
assert(ring.success == true)
assert(dialLimitChecks == 1 and moderationChecks == 1, 'group calls must share dial limits and moderation')
local channel = ring.data.channel
local outgoing
for _, event in ipairs(clientEvents) do
    if event.name == 'sd-phone:client:call:outgoing' and event.source == 1 then outgoing = event.payload end
end
assert(outgoing and outgoing.number == 'business:public_relations')
local groupIncoming = latestClientEvent('sd-phone:client:call:incoming', 2, channel)
assert(groupIncoming and groupIncoming.payload.number == 'business:public_relations')
assert(groupIncoming.payload.name == 'Public Relations')
assert(calls.current(2).data.number == 'business:public_relations')
local groupStarted = latestServerEvent('sd-phone:server:call:started')
assert(groupStarted and groupStarted.payload.caller.number == 'business:public_relations')
assert(groupStarted.payload.caller.number ~= '5550001')
assert(calls.current(1).data.number == 'business:public_relations')
assert(pcall(calls.setSpeaker, 1, true))
assert(pcall(calls.setSpeaker, 1, false))
assert(calls.accept(2, { channel = channel }).success == true)
assert(calls.current(1).data.number == 'business:public_relations')
assert(pcall(calls.setSpeaker, 1, true))
assert(pcall(calls.setSpeaker, 1, false))
assert(calls.hangup(1, { channel = channel }).success == true)
assert(calls.current(1).data == nil)

-- Caller-ID off is a recipient-facing privacy boundary. Keep the raw caller in the server session
-- for blocking/ownership decisions, but never send it through current(), conference events,
-- recents, group rings without a server-owned display identity, or lifecycle payloads.
clientEvents = {}
serverEvents = {}
callRows = {}
local anonymousRing = calls.callGroup(1, { { src = 2, cid = 'cid-2' } }, 'Dispatch')
assert(anonymousRing.success == true)
local anonymousChannel = anonymousRing.data.channel
local anonymousIncoming = latestClientEvent('sd-phone:client:call:incoming', 2, anonymousChannel)
assert(anonymousIncoming and anonymousIncoming.payload.number == '' and anonymousIncoming.payload.name == '')
assert(calls.current(2).data.number == '' and calls.current(2).data.name == '')
local anonymousStarted = latestServerEvent('sd-phone:server:call:started')
assert(anonymousStarted and anonymousStarted.payload.caller.number == '' and anonymousStarted.payload.caller.name == '')
assert(calls.decline(2, { channel = anonymousChannel }).success == true)
local anonymousEnded = latestServerEvent('sd-phone:server:call:ended')
assert(anonymousEnded and anonymousEnded.payload.caller.number == '' and anonymousEnded.payload.caller.name == '')

clientEvents = {}
serverEvents = {}
callRows = {}
blockedChecks = {}
local direct = calls.dial(1, { number = '5550002' })
assert(direct.success == true)
local directChannel = direct.data.channel
assert(blockedChecks[#blockedChecks].citizenid == 'cid-2' and blockedChecks[#blockedChecks].number == '5550001')
local directIncoming = latestClientEvent('sd-phone:client:call:incoming', 2, directChannel)
assert(directIncoming and directIncoming.payload.number == '' and directIncoming.payload.name == '')
assert(calls.current(2).data.number == '' and calls.current(2).data.name == '')
assert(calls.current(1).data.number == '5550002')
local directStarted = latestServerEvent('sd-phone:server:call:started')
assert(directStarted and directStarted.payload.caller.number == '' and directStarted.payload.caller.name == '')
assert(directStarted.payload.caller.citizenid == 'cid-1')
assert(calls.accept(2, { channel = directChannel }).success == true)
local directAnswered = latestServerEvent('sd-phone:server:call:answered')
assert(directAnswered and directAnswered.payload.caller.number == '' and directAnswered.payload.caller.name == '')

callerIds['cid-2'] = false
assert(calls.addCall(2, { number = '5550003' }).success == true)
local addedIncoming = latestClientEvent('sd-phone:client:call:incoming', 3, directChannel)
assert(addedIncoming and addedIncoming.payload.number == '' and addedIncoming.payload.name == '')
local addedCurrent = calls.current(3).data
assert(addedCurrent.number == '' and addedCurrent.name == '')
assert(calls.accept(3, { channel = directChannel }).success == true)
local merged = latestServerEvent('sd-phone:server:call:merged')
assert(merged and merged.payload.caller.number == '' and merged.payload.caller.name == '')
for _, event in ipairs(clientEvents) do
    if event.name == 'sd-phone:client:call:roster' and (event.source == 2 or event.source == 3) then
        for _, other in ipairs(event.payload.others or {}) do
            assert(other.number ~= '5550001' and other.name ~= 'Player 1')
            if event.source == 3 then
                assert(other.number ~= '5550002' and other.name ~= 'Player 2')
            end
        end
    end
end
assert(calls.current(3).data.number == '' and calls.current(3).data.name == '')
for _, other in ipairs(calls.current(3).data.others or {}) do
    assert(other.number ~= '5550002' and other.name ~= 'Player 2')
end
assert(calls.hangup(1, { channel = directChannel }).success == true)
local directEnded = latestServerEvent('sd-phone:server:call:ended')
assert(directEnded and directEnded.payload.caller.number == '' and directEnded.payload.caller.name == '')
for _, row in ipairs(callRows) do
    if row.citizenid == 'cid-2' or row.citizenid == 'cid-3' then
        assert(row.row.number == '' and (row.row.name == '' or row.row.name == nil))
    end
end

moderationMuted = true
local mutedRing = calls.callGroup(1, { { src = 2, cid = 'cid-2' } }, 'Public Relations', 'business:public_relations')
assert(mutedRing.success == false and mutedRing.message == 'Calls muted')
assert(pcall(calls.setSpeaker, 1, true))
assert(calls.hangup(1, { channel = channel }).success == true)

print('phone_runtime_spec: ok')
