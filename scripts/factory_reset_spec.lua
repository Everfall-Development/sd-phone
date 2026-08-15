package.path = './?.lua;./?/init.lua;' .. package.path

local function read(path)
    local file = assert(io.open(path, 'r'))
    local source = file:read('*a')
    file:close()
    return source
end

local function contains(source, needle)
    assert(source:find(needle, 1, true), needle .. ' is missing')
end

local callbacks = {}
local cooldownCalls = {}
local identifierCalls = 0
local mutations = {}
local signOuts = 0
local badgePushes = 0
local wipeCalls = {}
local wipeFailure

local store = {
    getPhoneNumber = function(cid)
        mutations[#mutations + 1] = { name = 'getPhoneNumber', cid = cid }
        return '5550100'
    end,
    resetSettings = function(cid, device, scope)
        mutations[#mutations + 1] = { name = 'resetSettings', cid = cid, device = device, scope = scope }
    end,
    resetNotifPrefs = function(cid)
        mutations[#mutations + 1] = { name = 'resetNotifPrefs', cid = cid }
    end,
}

local wipeStub = {
    wipeDeviceContent = function(cid, phoneNumber)
        wipeCalls[#wipeCalls + 1] = { cid = cid, phoneNumber = phoneNumber }
        if wipeFailure then error(wipeFailure) end
    end,
}

package.preload['server.boot'] = function() return {} end
package.preload['bridge.server.player'] = function()
    return {
        getIdentifier = function(source)
            identifierCalls = identifierCalls + 1
            return source == 7 and 'cid-1' or nil
        end,
    }
end
package.preload['server.settings.store'] = function() return store end
package.preload['server.accounts.actions'] = function()
    return {
        signOutEverywhere = function(cid)
            assert(cid == 'cid-1')
            signOuts = signOuts + 1
        end,
    }
end
package.preload['server.badges.init'] = function()
    return { push = function(source) assert(source == 7); badgePushes = badgePushes + 1 end }
end
package.preload['server.photos.actions'] = function() return {} end
package.preload['bridge.server.version'] = function() return {} end
package.preload['server.services.store'] = function()
    return { resetFor = function(cid) mutations[#mutations + 1] = { name = 'services', cid = cid } end }
end
package.preload['server.wifi.store'] = function()
    return { resetFor = function(cid) mutations[#mutations + 1] = { name = 'wifi', cid = cid } end }
end
package.preload['server.bluetooth.store'] = function()
    return { resetFor = function(cid) mutations[#mutations + 1] = { name = 'bluetooth', cid = cid } end }
end
package.preload['server.admin.wipe'] = function() return wipeStub end
package.preload['server.util'] = function()
    return {
        onCleanup = function() end,
        cooldown = function(cid, key, window)
            cooldownCalls[#cooldownCalls + 1] = { cid = cid, key = key, window = window }
            return true
        end,
        cooldownLeft = function() return 0 end,
    }
end

CreateThread = function() end
SetTimeout = function() end
GetGameTimer = function() return 1000 end
Wait = function() end
exports = function() end
lib = {
    callback = {
        register = function(name, callback) callbacks[name] = callback end,
    },
}

require 'server.settings.init'
local reset = assert(callbacks['sd-phone:server:settings:factoryReset'])

local settingsSource = read('server/settings/init.lua')
local resetSourceStart = assert(settingsSource:find("lib.callback.register('sd-phone:server:settings:factoryReset'", 1, true))
local resetSource = settingsSource:sub(resetSourceStart)
contains(resetSource, "scope ~= 'settings' and scope ~= 'erase'")
contains(resetSource, "local eraseAll = scope == 'erase'")
contains(resetSource, "local retainedNumber = eraseAll and store.getPhoneNumber(cid) or nil")
contains(resetSource, "pcall(wipe.wipeDeviceContent, cid, retainedNumber)")

local invalidPayloads = { {}, { scope = 'unknown' }, { scope = 'erase ' }, { scope = 1 }, { scope = true }, 'erase' }
for _, payload in ipairs(invalidPayloads) do
    local result = reset(7, payload)
    assert(result.success == false and result.message == 'Invalid reset scope')
end
assert(reset(7, nil).success == false)
assert(#cooldownCalls == 0, 'invalid scopes must not consume a cooldown')
assert(#mutations == 0, 'invalid scopes must not mutate settings or dependent state')
assert(#wipeCalls == 0 and identifierCalls == 0, 'invalid scopes must be rejected before lookup or wipe')

local settingsResult = reset(7, { scope = 'settings', device = 'tablet' })
assert(settingsResult.success == true)
assert(cooldownCalls[#cooldownCalls].key == 'settings:reset')
assert(mutations[1].name == 'resetSettings' and mutations[1].scope == 'settings')
assert(mutations[1].device == 'tablet')
assert(#wipeCalls == 0 and signOuts == 0)

local eraseResult = reset(7, { scope = 'erase' })
assert(eraseResult.success == true)
assert(cooldownCalls[#cooldownCalls].key == 'settings:factoryReset')
assert(wipeCalls[#wipeCalls].cid == 'cid-1' and wipeCalls[#wipeCalls].phoneNumber == '5550100')
assert(signOuts == 1)

wipeFailure = 'simulated deletion failure'
local mutationsBeforeFailure = #mutations
local failedErase = reset(7, { scope = 'erase' })
assert(failedErase.success == false and failedErase.message == 'Could not erase phone content')
assert(signOuts == 1, 'failed content wipes must not sign the character out as if erase succeeded')
assert(badgePushes == 2, 'failed content wipes must not report a successful badge refresh')
assert(#mutations == mutationsBeforeFailure + 1 and mutations[#mutations].name == 'getPhoneNumber',
    'failed content wipes must not reset settings or dependent state')

local wipeSource = read('server/admin/wipe.lua')
contains(wipeSource, 'local function transactionStrict(queries)')
contains(wipeSource, "DELETE FROM phone_pending_messages WHERE number = ?")
contains(wipeSource, "DELETE FROM phone_photo_album_items WHERE album_id IN (SELECT id FROM phone_photo_albums WHERE citizenid = ?)")

package.loaded['server.admin.wipe'] = nil
package.preload['server.admin.wipe'] = nil
lib.addCommand = function() end
local transactions = {}
local transactionResult = true
local transactionFailure
MySQL = {
    transaction = {
        await = function(queries)
            transactions[#transactions + 1] = queries
            if transactionFailure then error(transactionFailure) end
            return transactionResult
        end,
    },
    update = { await = function() error('device wipe must use one transaction') end },
    query = { await = function() return {} end },
    scalar = { await = function() return nil end },
}

local wipe = require 'server.admin.wipe'
transactions = {}
local statements = wipe.wipeDeviceContent('cid-1', '5550100')
assert(#transactions == 1)
local transaction = transactions[1]
assert(statements == #transaction)
local pendingDelete
for _, call in ipairs(transaction) do
    assert(type(call) == 'table' and type(call.query) == 'string' and type(call.values) == 'table')
    if call.query:find('phone_pending_messages', 1, true) then pendingDelete = call end
end
assert(pendingDelete and pendingDelete.values[1] == '5550100')

transactionResult = false
local ok, err = pcall(wipe.wipeDeviceContent, 'cid-1', '5550100')
assert(not ok and tostring(err):find('expected true', 1))

transactionResult = nil
ok, err = pcall(wipe.wipeDeviceContent, 'cid-1', '5550100')
assert(not ok and tostring(err):find('expected true', 1))

transactionResult = true
transactionFailure = 'database transaction failed'
ok, err = pcall(wipe.wipeDeviceContent, 'cid-1', '5550100')
assert(not ok and tostring(err):find('device%-content wipe transaction failed', 1))

print('factory_reset_spec: ok')
