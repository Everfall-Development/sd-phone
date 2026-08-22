package.path = './?.lua;./?/init.lua;' .. package.path

local resourceState = 'started'
local activeJobs = { [7] = 'beanmachine', [8] = 'beanmachine', [9] = 'unemployed' }
local duty = { [7] = true, [8] = false, [9] = false }
local messages = {}
local clientEvents = {}
local serverEvents = {}
local callTargets
local callSharesDisplayIdentity
local directoryCalls = 0
local blockedRateKeys = {}
local rateCalls = {}

local function read(path)
    local file = assert(io.open(path, 'r'))
    local source = file:read('*a')
    file:close()
    return source
end
local liveBusinesses = {
    lspd = {
        Enabled = true,
        Type = 'public_service',
        Blip = { Enable = true, Name = 'Police', Coords = { x = 10, y = 20, z = 30 } },
    },
    hospital = {
        Enabled = true,
        Type = 'public_service',
        Blip = { Enable = true, Name = 'Ambulance', Coords = { x = 40, y = 50, z = 60 } },
    },
    realestate = {
        Enabled = true,
        Type = 'general',
        Blip = { Enable = true, Name = 'Dynasty 8 Real Estate', Coords = { x = 67, y = -260, z = 48 } },
    },
    beanmachine = {
        Enabled = true,
        Type = 'restaurant',
        Advertisement = { Icon = 'https://cdn.example/bean-machine.png' },
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
    mechanic_shop = {
        Enabled = true,
        Type = 'mechanic',
        Blip = { Enable = false, Name = 'Pitstop Garage', Coords = { x = 90, y = 91, z = 92 } },
    },
    taxi_tuggers = {
        Enabled = true,
        Type = 'restaurant',
        Blip = { Enable = true, Name = "Tugger's Taxis", Coords = { x = 95, y = 96, z = 97 } },
    },
    logistics_irontrail = {
        Enabled = true,
        Type = 'mechanic',
        Blip = { Enable = false, Name = 'Irontrail Logistics', Coords = { x = 98, y = 99, z = 100 } },
    },
    factories_reprocessing_grapeseed = {
        Enabled = true,
        Blip = { Enable = true, Name = 'Grapeseed Factory', Coords = { x = 93, y = 94, z = 95 } },
    },
}

function GetResourceState(name)
    assert(name == 'ef_businesses')
    return resourceState
end

exports = {
    ef_businesses = {
        GetBusinesses = function(_, includeStorefront)
            assert(includeStorefront == nil, 'directory provider must wait for initialization')
            directoryCalls = directoryCalls + 1
            return liveBusinesses
        end,
    },
    ['sd-phone'] = {
        hasPhone = function(first, second)
            local source = second or first
            return (source == 7 or source == 8 or source == 9) and 'black' or nil
        end,
    },
}

lib = {
    string = {
        startsWith = function(value, prefix)
            return value:sub(1, #prefix) == prefix
        end,
    },
}

json = {
    encode = function(value) return value.mediaUrl or value.wpCode or '' end,
    decode = function(value) return { mediaUrl = value } end,
}

package.preload['configs.config'] = function()
    return {
        Services = {
            MessageImageHosts = { 'cdn.example' },
            DirectoryVisibility = {
                AlwaysIncludeTypes = { 'mechanic' },
                ExcludeTypes = { 'industrial', 'public_service' },
                ExcludeJobPrefixes = { 'factories_' },
            },
            DirectoryOverrides = {
                police = { visible = false },
                ambulance = { visible = false },
                realestate = {
                    label = 'Dynasty 8 Real Estate',
                    iconUrl = './dynasty8-logo.png',
                    canMessage = false,
                },
                beanmachine = { label = '', location = '', color = '', iconUrl = '' },
                mechanic_shop = { canLocate = false },
                taxi_tuggers = { category = 'Transportation', emoji = '🚕' },
                logistics_irontrail = { category = 'Logistics', emoji = '🚚' },
            },
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
        callGroup = function(source, targets, _, identity, shareDisplayIdentity)
            if exports['sd-phone'].hasPhone(source) == nil then
                return { success = false, message = 'You need a phone to make calls' }
            end
            callTargets = targets
            callSharesDisplayIdentity = shareDisplayIdentity
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
        limitedString = function(value, max)
            local text = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
            if text == '' then return nil end
            return text:sub(1, max)
        end,
        cooldown = function() return true end,
        rateLimit = function(_, key)
            rateCalls[#rateCalls + 1] = key
            return blockedRateKeys[key] ~= true
        end,
    }
end

TriggerClientEvent = function(name, source, payload)
    clientEvents[#clientEvents + 1] = { name = name, source = source, payload = payload }
end
TriggerEvent = function(name, payload)
    serverEvents[#serverEvents + 1] = { name = name, payload = payload }
end

local businesses = require 'server.services.businesses'

assert(businesses.directory(10).success == false, 'directory callbacks must require a phone item')
local available = businesses.directory(9)
assert(available.success == true)
assert(#available.data.companies == 5, 'expected configured customer-facing businesses')

local byId = {}
for _, company in ipairs(available.data.companies) do byId[company.id] = company end
assert(byId.police == nil and byId.ambulance == nil, 'emergency services must not be injected into Businesses')
assert(byId.lspd == nil and byId.hospital == nil, 'live public-service entries must not appear in Businesses')
assert(byId.realestate.name == 'Dynasty 8 Real Estate')
assert(byId.realestate.iconUrl == './dynasty8-logo.png')
assert(byId.realestate.canMessage == false, 'directory overrides must disable messaging')
assert(byId.beanmachine.name == 'Bean Machine', 'empty override must preserve the source name fallback')
assert(byId.beanmachine.category == 'Food')
assert(byId.beanmachine.location == 'Food', 'empty override must preserve the category location fallback')
assert(byId.beanmachine.status == 'open')
assert(byId.beanmachine.coords.x == 12 and byId.beanmachine.coords.y == 34)
assert(byId.hidden == nil)
assert(byId.no_blip == nil)
assert(byId.mechanic_shop.name == 'Pitstop Garage')
assert(byId.mechanic_shop.category == 'Automotive')
assert(byId.mechanic_shop.coords == nil, 'directory overrides must disable location actions')
assert(byId.taxi_tuggers.category == 'Transportation', 'phone categories must override source business types')
assert(byId.taxi_tuggers.emoji == '🚕')
assert(byId.logistics_irontrail.category == 'Logistics', 'logistics must not inherit the mechanic label')
assert(byId.logistics_irontrail.emoji == '🚚')
assert(byId.factories_reprocessing_grapeseed == nil, 'factory jobs without a Type must not appear as businesses')
assert(
    businesses.message(9, { job = 'realestate', kind = 'text', body = 'Hello' }).success == false,
    'disabled business messaging must be enforced on the server'
)

blockedRateKeys['businesses:directory'] = true
assert(businesses.directory(9).success == false, 'directory reads must be rate limited')
blockedRateKeys['businesses:directory'] = nil
blockedRateKeys['businesses:inbox'] = true
assert(businesses.inbox(9).success == false, 'inbox reads must be rate limited')
blockedRateKeys['businesses:inbox'] = nil

local source = read('server/calls/actions.lua')
assert(source:find("if not reachable(source) then return fail('You need a phone to make calls') end", 1, true))
assert(source:find("if myNumber == '' then return fail('You need a phone number to make calls') end", 1, true))
assert(source:find("moderation.guard(cid, 'calls')", 1, true), 'group calls must share call moderation')
local servicesInitSource = read('server/services/init.lua')
assert(servicesInitSource:find("AddEventHandler('QBCore:Server:SetDuty'", 1, true), 'duty changes must refresh open directories')
local storeSource = read('server/services/msgstore.lua')
assert(storeSource:find('ROW_NUMBER() OVER (PARTITION BY', 1, true))
assert(storeSource:find('ORDER BY created_at DESC, id DESC', 1, true))

local called = businesses.call(9, { job = 'beanmachine' })
assert(called.success == true)
assert(called.data.number == 'business:beanmachine')
assert(#callTargets == 1 and callTargets[1].src == 7, 'only online, on-duty staff should ring')
assert(callSharesDisplayIdentity == false, 'business staff must see the customer caller ID, not the business identity')
assert(businesses.call(10, { job = 'beanmachine' }).success == false, 'callGroup must reject callers without a phone')

local invalidImage = businesses.message(9, {
    job = 'beanmachine',
    kind = 'image',
    mediaUrl = 'data:text/html,<script>alert(1)</script>',
})
assert(invalidImage.success == false and #messages == 0, 'unsafe image schemes must be rejected before persistence')

local untrustedImage = businesses.message(9, {
    job = 'beanmachine',
    kind = 'image',
    mediaUrl = 'https://127.0.0.1/private.png',
})
assert(untrustedImage.success == false and #messages == 0, 'message images must use a trusted configured host')

local invalidLocation = businesses.message(9, {
    job = 'beanmachine',
    kind = 'location',
    wpCode = 'not-a-waypoint',
})
assert(invalidLocation.success == false and #messages == 0, 'location messages must use the shared waypoint format')

local userinfoImage = businesses.message(9, {
    job = 'beanmachine',
    kind = 'image',
    mediaUrl = 'https://cdn.example:80@127.0.0.1/private.png',
})
assert(userinfoImage.success == false and #messages == 0, 'message image userinfo must not bypass the trusted host check')

local tooManyDrafts = {}
for index = 1, 9 do tooManyDrafts[index] = { kind = 'text', body = 'Draft ' .. index } end
local rateBeforeTooMany = #rateCalls
local tooMany = businesses.message(9, { job = 'beanmachine', drafts = tooManyDrafts })
assert(tooMany.success == false and #messages == 0, 'oversized batches must be rejected before persistence')
assert(#rateCalls == rateBeforeTooMany, 'rejected batches must not consume a rate token')

local rateBeforeBatch = #rateCalls
local directoryBeforeBatch = directoryCalls
local sent = businesses.message(9, {
    job = 'beanmachine',
    drafts = {
        { kind = 'image', mediaUrl = 'http://cdn.example/photo.jpg' },
        { kind = 'text', body = 'Are you open?' },
    },
})
assert(sent.success == true)
assert(#messages == 2 and messages[1].sender == 'citizen' and messages[2].body == 'Are you open?')
assert(#rateCalls == rateBeforeBatch + 1, 'a batch must consume one rate-limit request')
assert(directoryCalls == directoryBeforeBatch + 1, 'the post-write inbox must reuse its authorized directory snapshot')
local messageEvents = 0
for _, event in ipairs(serverEvents) do
    if event.name == 'sd-phone:server:services:message' then messageEvents = messageEvents + 1 end
end
assert(messageEvents == 2, 'each persisted draft must emit its compatibility event')
local notifiedOnDuty, notifiedOffDuty = false, false
local staffNotificationLink
local batchNotifications, batchInvalidations = 0, 0
for _, event in ipairs(clientEvents) do
    if event.name == 'sd-phone:client:notify' then
        notifiedOnDuty = notifiedOnDuty or event.source == 7
        notifiedOffDuty = notifiedOffDuty or event.source == 8
        if event.source == 7 then
            batchNotifications = batchNotifications + 1
            staffNotificationLink = event.payload.link
            assert(event.payload.body:find('Are you open?', 1, true), 'batch notification should prefer the final text')
        end
    elseif event.name == 'sd-phone:client:services:inbox' and event.source == 7 then
        batchInvalidations = batchInvalidations + 1
    end
end
assert(notifiedOnDuty and not notifiedOffDuty, 'business notifications must only reach on-duty staff')
assert(batchNotifications == 1 and batchInvalidations == 1, 'a batch must notify and invalidate the staff inbox once')
assert(staffNotificationLink and staffNotificationLink.services.scope == 'job')
assert(staffNotificationLink.services.thread == '5550100')

local staffInbox = businesses.inbox(7)
assert(staffInbox.success == true and staffInbox.data.hasJob == true)
assert(#staffInbox.data.job == 1 and staffInbox.data.job[1].key == '5550100')
assert(staffInbox.data.job[1].iconUrl == byId.beanmachine.iconUrl)

activeJobs[7] = 'unemployed'
assert(businesses.inbox(7).data.hasJob == false, 'inactive/saved jobs must not grant inbox access')
assert(businesses.reply(7, { citizen = '5550100', body = 'No access' }).success == false)

activeJobs[8] = 'beanmachine'
local replied = businesses.reply(8, { citizen = '5550100', body = 'We can help.' })
assert(replied.success == true, 'matching active staff may reply even while off duty')
assert(#messages == 3 and messages[3].sender == 'staff')
local staffReply = replied.data.inbox.job[1].messages[#replied.data.inbox.job[1].messages]
assert(staffReply.name == 'Staff 8', 'staff inboxes may retain employee attribution')
local customerNotificationLink
for _, event in ipairs(clientEvents) do
    if event.name == 'sd-phone:client:notify' and event.source == 9 then
        customerNotificationLink = event.payload.link
    end
end
assert(customerNotificationLink and customerNotificationLink.services.scope == 'personal')
assert(customerNotificationLink.services.thread == 'beanmachine')
local customerInbox = businesses.inbox(9)
assert(customerInbox.success == true and customerInbox.data.personal[1].iconUrl == byId.beanmachine.iconUrl)
local customerReply = customerInbox.data.personal[1].messages[#customerInbox.data.personal[1].messages]
assert(customerReply.from == 'them' and customerReply.name == 'Bean Machine')
assert(customerReply.name ~= 'Staff 8', 'customer inboxes must not expose the employee name')

resourceState = 'stopped'
local unavailable = businesses.directory(9)
assert(unavailable.success == false)
assert(unavailable.message == 'Businesses are unavailable right now.')
local companyList, companyListError = businesses.companyList()
assert(companyList == nil and companyListError == 'Businesses are unavailable right now.')

resourceState = 'started'
liveBusinesses.new_shop = {
    Enabled = true,
    Type = 'vendor',
    Blip = { Enable = true, Name = 'New Shop', Coords = { x = 90, y = 80, z = 70 } },
}
local retried = businesses.directory(9)
assert(retried.success == true)
assert(#retried.data.companies == 6, 'an unavailable response must not cache an empty directory')

print('businesses_spec: ok')
