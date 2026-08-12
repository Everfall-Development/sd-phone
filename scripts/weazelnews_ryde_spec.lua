package.path = './?.lua;./?/init.lua;' .. package.path

local function read(path)
    local file = assert(io.open(path, 'r'))
    local value = file:read('*a')
    file:close()
    return value
end

-- Static release contracts which do not need a FiveM runtime.
local rydeConfig = dofile('configs/ryde.lua')
assert(rydeConfig.DriverJobs.taxi == 0)
assert(rydeConfig.DriverJobs.taxi_tuggers == 0)
assert(read('configs/celltowers.lua'):find("'weazelnews:view'", 1, true) == nil)
assert(read('server/weazelnews/init.lua'):find("exports('postArticle'", 1, true) == nil)
assert(read('server/weazelnews/init.lua'):find("exports('setBreakingTicker'", 1, true) == nil)
assert(read('../../[everfall]/ef_prime/modules/microphone/cl_microphone.lua'):find('public_relations%s*=%s*true'))
local weazelClient = read('client/apps/weazelnews.lua')
assert(weazelClient:find("AddEventHandler('sd-phone:client:openState'", 1, true))
assert(weazelClient:find('if open then refreshManagementAccess()', 1, true))

-- Weazel authorization: all grades of the active public_relations job qualify, unrelated jobs do
-- not. This stubs only the framework/database edges needed by the feed action.
local newsroomJob = 'public_relations'
package.preload['configs.config'] = function()
    return {
        WeazelNews = {
            Jobs = { 'public_relations' }, CheckIsBoss = false, BossGrade = 0,
            Categories = { 'General' }, ArticlesPerFeed = 10,
            MaxHeadlineLength = 160, MaxDekLength = 255, MaxBodyLength = 4000,
            MaxImageUrlLength = 512, MaxBreakingLength = 220, MaxBreakingLines = 5,
        },
    }
end
package.preload['server.weazelnews.store'] = function()
    return { articles = function() return {} end, breaking = function() return {} end }
end
package.preload['server.watchers'] = function()
    return { of = function() return { push = function() end } end }
end
package.preload['bridge.server.player'] = function()
    return { getIdentifier = function() return 'cid-news' end, getName = function() return 'Reporter' end }
end
package.preload['bridge.server.job'] = function()
    return {
        has = function(_, name) return name == newsroomJob end,
        isBoss = function() return false end,
    }
end
package.preload['server.util'] = function()
    return {
        trim = function(value) return tostring(value or '') end,
        rateLimit = function() return true end,
        onCleanup = function() end,
    }
end

package.loaded['server.weazelnews.actions'] = nil
local newsroom = require 'server.weazelnews.actions'
assert(newsroom.feed(1).data.canManage == true)
newsroomJob = 'unemployed'
assert(newsroom.feed(1).data.canManage == false)

-- Ryde authorization: active taxi/taxi_tuggers at grade 0 and on duty may register; inactive,
-- unrelated, or off-duty callers fail closed. The callback response includes the live policy.
local activeJob = 'unemployed'
local activeDuty = false
package.preload['configs.ryde'] = function()
    return {
        DriverJobs = { taxi = 0, taxi_tuggers = 0 },
        DriverPolicy = 'Active taxi or taxi_tuggers job, on duty',
        MinFare = 1, MaxFare = 100000,
    }
end
package.preload['bridge.server.job'] = function()
    return {
        getName = function() return activeJob end,
        getGrade = function() return 0 end,
        getDuty = function() return activeDuty end,
    }
end
package.preload['bridge.server.player'] = function()
    return {
        getIdentifier = function() return 'cid-driver' end,
        getSourceByIdentifier = function() return 7 end,
    }
end
package.preload['server.accounts.store'] = function()
    return {
        getSessionAccount = function() return { id = 1, username = 'driver', displayName = 'Driver' } end,
    }
end
package.preload['server.ryde.store'] = function()
    return {
        getDriver = function() return { rating_count = 0, rating_sum = 0 } end,
        upsertDriver = function() end,
        newId = function() return 'trip-test' end,
    }
end
package.preload['server.settings.store'] = function()
    return { ensurePhoneNumber = function() return '5550000' end }
end
package.preload['bridge.server.money'] = function() return {} end
package.preload['server.banking.actions'] = function() return {} end
package.preload['server.util'] = function()
    return {
        ok = function(data) return { success = true, data = data } end,
        fail = function(message) return { success = false, message = message } end,
        appEnabled = function() return true end,
    }
end

CreateThread = function() end
TriggerClientEvent = function() end
lib = { math = { round = function(value) return value end } }
for _, name in ipairs({
    'bridge.server.job', 'bridge.server.player', 'server.util', 'server.accounts.store',
    'server.ryde.store', 'server.settings.store', 'bridge.server.money', 'server.banking.actions',
}) do
    package.loaded[name] = nil
end
package.loaded['server.ryde.actions'] = nil
local ryde = require 'server.ryde.actions'

local denied = ryde.config(7)
assert(denied.data.driverAllowed == false)
assert(denied.data.job == 'unemployed')
assert(denied.data.duty == false)
assert(denied.data.policy == 'Active taxi or taxi_tuggers job, on duty')
assert(ryde.setOnline(7, { online = true }).success == false)
assert(ryde.accept(7, { requestId = 'missing', fare = 10 }).success == false)

activeJob, activeDuty = 'taxi_tuggers', true
local allowed = ryde.config(7)
assert(allowed.data.driverAllowed == true)
assert(ryde.setOnline(7, { online = true }).success == true)

activeJob, activeDuty = 'taxi', false
assert(ryde.config(7).data.driverAllowed == false)
assert(ryde.setOnline(7, { online = true }).success == false)

print('weazelnews_ryde_spec: ok')
