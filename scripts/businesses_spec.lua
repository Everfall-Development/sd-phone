package.path = './?.lua;./?/init.lua;' .. package.path

local resourceState = 'started'
local activeJobs = { [7] = 'beanmachine', [8] = 'beanmachine', [9] = 'unemployed' }
local duty = { [7] = true, [8] = false, [9] = false }
local messages = {}
local clientEvents = {}
local callTargets
local liveBusinesses = {
    beanmachine = {
        Enabled = true,
        Type = 'restaurant',
        Blip = { Enable = true, Name = 'Bean Machine', Coords = { x = 12, y = 34, z = 5 } },
    },
    hidden = {
        Enabled = false,
        Type = 'vendor',
        Blip = { Enable = true, Name = 'Hidden Shop', Coords = { x = 1, y = 2, z = 3 } },
    },
    no_blip = {
        Enabled = true,
        Type = 'vendor',
        Blip = { Enable = false, Name = 'No Blip', Coords = { x = 1, y = 2, z = 3 } },
    },
}

function GetResourceState(name)
    assert(name == 'ef_businesses')
    return resourceState
end

exports = {
    ef_businesses = {
        GetBusinesses = function(_, includeStorefront)
            assert(includeStorefront == true)
            return liveBusinesses
        end,
    },
}

package.preload['configs.config'] = function()
    return {
        Services = {
            EmergencyCompanies = { 'police', 'ambulance' },
            DirectoryOverrides = {},
            Companies = {
                { job = 'police', label = 'Police', emergency = true, coords = { x = 10, y = 20, z = 30 } },
                { job = 'ambulance', label = 'Ambulance', emergency = true, coords = { x = 40, y = 50, z = 60 } },
            },
        },
    }
end

package.preload['server.services.msgstore'] = function()
    return {
        newId = function() return 'message-' .. tostring(#messages + 1) end,
        insert = function(message) messages[#messages + 1] = message end,
        personalUnread = function() return {} end,
        jobUnread = function() return {} end,
        citizenThreads = function(number)
            local threads = {}
            for _, message in ipairs(messages) do
                if message.citizenNumber == number then
                    threads[message.job] = {
                        job = message.job,
                        last_body = message.body,
                        created_at = message.createdAt,
                    }
                end
            end
            local result = {}
            for _, thread in pairs(threads) do result[#result + 1] = thread end
            return result
        end,
        jobThreads = function(jobName)
            local threads = {}
            for _, message in ipairs(messages) do
                if message.job == jobName then
                    threads[message.citizenNumber] = {
                        citizen_number = message.citizenNumber,
                        citizen_name = message.citizenName,
                        last_body = message.body,
                        created_at = message.createdAt,
                    }
                end
            end
            local result = {}
            for _, thread in pairs(threads) do result[#result + 1] = thread end
            return result
        end,
        citizenThreadMessages = function() return {} end,
        jobThreadMessages = function() return {} end,
        threadMessages = function(jobName, number)
            local result = {}
            for _, message in ipairs(messages) do
                if message.job == jobName and message.citizenNumber == number then
                    result[#result + 1] = {
                        id = message.id,
                        sender = message.sender,
                        staff_name = message.staffName,
                        citizen_name = message.citizenName,
                        body = message.body,
                        kind = message.kind,
                        meta = message.meta,
                        created_at = message.createdAt,
                    }
                end
            end
            return result
        end,
        threadExists = function(jobName, number)
            for _, message in ipairs(messages) do
                if message.job == jobName and message.citizenNumber == number then return true end
            end
            return false
        end,
        markRead = function() end,
    }
end
package.preload['server.settings.store'] = function()
    return {
        ensurePhoneNumber = function() return '5550100' end,
        getPhoneNumber = function() return '5550100' end,
        getCitizenByNumber = function(number) return number == '5550100' and 'customer' or nil end,
    }
end
package.preload['server.calls.actions'] = function()
    return {
        isBusy = function() return false end,
        callGroup = function(_, targets, _, identity)
            callTargets = targets
            return { success = true, data = { number = identity } }
        end,
    }
end
package.preload['bridge.server.job'] = function()
    return {
        getDuty = function(source) return duty[source] == true end,
        getName = function(source) return activeJobs[source] end,
        getLabel = function(name) return name end,
    }
end
package.preload['bridge.server.player'] = function()
    return {
        onlineCidMap = function() return { staff = 7, offduty = 8, customer = 9 } end,
        getIdentifier = function(source) return source == 9 and 'customer' or 'staff-' .. tostring(source) end,
        getName = function(source) return source == 9 and 'Customer' or 'Staff ' .. tostring(source) end,
        getAnySourceByIdentifier = function(identifier) return identifier == 'customer' and 9 or nil end,
    }
end
package.preload['server.util'] = function()
    return {
        ok = function(data) return { success = true, data = data } end,
        fail = function(message) return { success = false, message = message } end,
        digits = function(value) return tostring(value or ''):gsub('%D', '') end,
        trim = function(value) return tostring(value or '') end,
        cooldown = function() return true end,
        rateLimit = function() return true end,
    }
end

TriggerClientEvent = function(name, source, payload)
    clientEvents[#clientEvents + 1] = { name = name, source = source, payload = payload }
end
TriggerEvent = function() end

local businesses = require 'server.services.businesses'

local available = businesses.directory()
assert(available.success == true)
assert(#available.data.companies == 3, 'two emergency entries and one public business expected')

local byId = {}
for _, company in ipairs(available.data.companies) do byId[company.id] = company end
assert(byId.police.emergency == true)
assert(byId.ambulance.emergency == true)
assert(byId.beanmachine.name == 'Bean Machine')
assert(byId.beanmachine.category == 'Food')
assert(byId.beanmachine.status == 'open')
assert(byId.beanmachine.coords.x == 12 and byId.beanmachine.coords.y == 34)
assert(byId.hidden == nil)
assert(byId.no_blip == nil)

local called = businesses.call(9, { job = 'beanmachine' })
assert(called.success == true)
assert(called.data.number == 'business:beanmachine')
assert(#callTargets == 1 and callTargets[1].src == 7, 'only online, on-duty staff should ring')

local sent = businesses.message(9, { job = 'beanmachine', body = 'Are you open?' })
assert(sent.success == true)
assert(#messages == 1 and messages[1].sender == 'citizen')
local notifiedOnDuty, notifiedOffDuty = false, false
for _, event in ipairs(clientEvents) do
    if event.name == 'sd-phone:client:notify' then
        notifiedOnDuty = notifiedOnDuty or event.source == 7
        notifiedOffDuty = notifiedOffDuty or event.source == 8
    end
end
assert(notifiedOnDuty and not notifiedOffDuty, 'business notifications must only reach on-duty staff')

local staffInbox = businesses.inbox(7)
assert(staffInbox.success == true and staffInbox.data.hasJob == true)
assert(#staffInbox.data.job == 1 and staffInbox.data.job[1].key == '5550100')

activeJobs[7] = 'unemployed'
assert(businesses.inbox(7).data.hasJob == false, 'inactive/saved jobs must not grant inbox access')
assert(businesses.reply(7, { citizen = '5550100', body = 'No access' }).success == false)

activeJobs[8] = 'beanmachine'
local replied = businesses.reply(8, { citizen = '5550100', body = 'We can help.' })
assert(replied.success == true, 'matching active staff may reply even while off duty')
assert(#messages == 2 and messages[2].sender == 'staff')

resourceState = 'stopped'
local unavailable = businesses.directory()
assert(unavailable.success == false)
assert(unavailable.message == 'Businesses are unavailable right now.')

resourceState = 'started'
liveBusinesses.new_shop = {
    Enabled = true,
    Type = 'vendor',
    Blip = { Enable = true, Name = 'New Shop', Coords = { x = 90, y = 80, z = 70 } },
}
local retried = businesses.directory()
assert(retried.success == true)
assert(#retried.data.companies == 4, 'an unavailable response must not cache an empty directory')

print('businesses_spec: ok')
