---@type table sd-phone configuration root.
local config = require 'configs.config'
---@type table Company inbox persistence.
local msgstore = require 'server.services.msgstore'
---@type table Current-job and duty authority.
local job = require 'bridge.server.job'
---@type table Player identity and online-source authority.
local player = require 'bridge.server.player'
---@type table Phone-number ownership persistence.
local settings = require 'server.settings.store'
---@type table Group-call session authority.
local calls = require 'server.calls.actions'
---@type table Shared response, input, and rate-limit helpers.
local util = require 'server.util'

local servicesConfig = config.Services or {}
local overrides = servicesConfig.DirectoryOverrides or {}

local emergencyJobs = {}
for _, name in ipairs(servicesConfig.EmergencyCompanies or {}) do
    emergencyJobs[name] = true
end

local configuredEmergency = {}
for _, entry in ipairs(servicesConfig.Companies or {}) do
    if emergencyJobs[entry.job] or entry.emergency == true then
        configuredEmergency[#configuredEmergency + 1] = entry
    end
end

local categoryStyles = {
    general = { label = 'Business', color = '#64748B', emoji = '🏪' },
    restaurant = { label = 'Food', color = '#C86E32', emoji = '🍴' },
    nightlife = { label = 'Nightlife', color = '#8A4F7D', emoji = '🎶' },
    vendor = { label = 'Vendor', color = '#4C8B73', emoji = '🛒' },
    mechanic = { label = 'Automotive', color = '#59636E', emoji = '🔧' },
    industrial = { label = 'Industrial', color = '#8A6B3F', emoji = '🏭' },
    event = { label = 'Event', color = '#7B5EA7', emoji = '🎫' },
    security = { label = 'Security', color = '#3F5F78', emoji = '🛡️' },
    public_service = { label = 'Public Service', color = '#3B6E8F', emoji = '🏛️' },
}

local ok = util.ok
local fail = util.fail
local digits = util.digits
local trim = util.trim

local MSG_WINDOW = 60000
local MSG_MAX = 25
local REPLY_MAX = 30
local READ_MAX = 90
local THREAD_MESSAGES = 100

local businesses = {}

---@param value any
---@return table|nil
local function normalizeCoords(value)
    if not value then return nil end
    local x = tonumber(value.x or value[1])
    local y = tonumber(value.y or value[2])
    local z = tonumber(value.z or value[3]) or 0
    if not x or not y then return nil end
    return { x = x, y = y, z = z }
end

---@return table<string, boolean>
local function onDutyJobs()
    local result = {}
    for _, source in pairs(player.onlineCidMap()) do
        if job.getDuty(source) == true then
            local jobName = job.getName(source)
            if jobName then result[jobName] = true end
        end
    end
    return result
end

---@param entry table
---@param duty table<string, boolean>
---@return table
local function emergencyEntry(entry, duty)
    return {
        id = entry.job,
        name = entry.label,
        category = 'Emergency',
        location = entry.location or 'Emergency Services',
        color = entry.color or '#C0392B',
        emoji = entry.emoji or '🚨',
        status = duty[entry.job] and 'open' or 'closed',
        onDuty = duty[entry.job] == true,
        canCall = entry.canCall ~= false,
        canMessage = true,
        emergency = true,
        coords = normalizeCoords(entry.coords),
    }
end

---@param businessId string
---@param business table
---@param duty table<string, boolean>
---@return table|nil
local function directoryEntry(businessId, business, duty)
    if business.Enabled == false then return nil end
    local blip = business.Blip
    if type(blip) ~= 'table' or blip.Enable ~= true then return nil end

    local override = overrides[businessId] or {}
    if override.hidden == true then return nil end

    local categoryKey = tostring(business.Type or 'general')
    local style = categoryStyles[categoryKey] or categoryStyles.general
    local name = override.label or business.Name or blip.Name or job.getLabel(businessId) or businessId
    local storefront = business.Storefront or {}
    local advertisement = storefront.Advertisement or {}

    return {
        id = businessId,
        name = name,
        category = style.label,
        location = override.location or style.label,
        color = override.color or style.color,
        emoji = override.emoji or style.emoji,
        iconUrl = override.iconUrl or advertisement.Icon or storefront.ImageUrl,
        status = duty[businessId] and 'open' or 'closed',
        onDuty = duty[businessId] == true,
        canCall = override.canCall ~= false,
        canMessage = override.canMessage ~= false,
        emergency = false,
        coords = normalizeCoords(override.coords or blip.Coords),
    }
end

---@return table[]|nil entries
---@return table<string, table>|string byJobOrError
local function liveDirectory()
    if GetResourceState('ef_businesses') ~= 'started' then
        return nil, 'Businesses are unavailable right now.'
    end

    local succeeded, sourceBusinesses = pcall(function()
        return exports.ef_businesses:GetBusinesses(true)
    end)
    if not succeeded or type(sourceBusinesses) ~= 'table' then
        return nil, 'Businesses are unavailable right now.'
    end

    local duty = onDutyJobs()
    local entries = {}
    local byJob = {}

    for _, entry in ipairs(configuredEmergency) do
        local normalized = emergencyEntry(entry, duty)
        entries[#entries + 1] = normalized
        byJob[normalized.id] = normalized
    end

    for businessId, business in pairs(sourceBusinesses) do
        if type(businessId) == 'string' and type(business) == 'table' and not byJob[businessId] then
            local normalized = directoryEntry(businessId, business, duty)
            if normalized then
                entries[#entries + 1] = normalized
                byJob[businessId] = normalized
            end
        end
    end

    table.sort(entries, function(a, b)
        if a.emergency ~= b.emergency then return a.emergency == true end
        if a.category ~= b.category then return a.category < b.category end
        return a.name < b.name
    end)

    return entries, byJob
end

---@return table[]
function businesses.companyList()
    local entries = liveDirectory()
    return entries or {}
end

---@return table
function businesses.directory()
    local entries, byJobOrError = liveDirectory()
    if not entries then return fail(byJobOrError) end
    return ok({ companies = entries })
end

---@param payload table
---@return string|nil kind
---@return string body
---@return string|nil meta
local function parseDraft(payload)
    local kind = tostring(payload.kind or 'text')
    if kind == 'image' then
        local url = trim(payload.mediaUrl):sub(1, 512)
        if url == '' then return nil, 'No image' end
        return 'image', '📷 Photo', json.encode({ mediaUrl = url })
    end
    if kind == 'location' then
        local waypoint = trim(payload.wpCode):sub(1, 256)
        if waypoint == '' then return nil, 'No location' end
        local meta = { wpCode = waypoint }
        local subtitle = trim(payload.wpSub):sub(1, 128)
        if subtitle ~= '' then meta.wpSub = subtitle end
        return 'location', '📍 Location', json.encode(meta)
    end

    local body = trim(payload.body)
    if body == '' then return nil, 'Empty message' end
    return 'text', body:sub(1, 300), nil
end

---@param rows table[]
---@param viewerKind 'citizen'|'staff'
---@return table[]
local function serializeInbox(rows, viewerKind)
    local result = {}
    for _, row in ipairs(rows) do
        local mine = (viewerKind == 'citizen' and row.sender == 'citizen')
            or (viewerKind == 'staff' and row.sender == 'staff')
        local message = {
            id = row.id,
            from = mine and 'me' or 'them',
            name = row.sender == 'staff' and (row.staff_name or 'Staff') or (row.citizen_name or ''),
            body = row.body or '',
            kind = row.kind or 'text',
            ts = (tonumber(row.created_at) or 0) * 1000,
        }
        if row.meta and row.meta ~= '' then
            local decodedOk, decoded = pcall(json.decode, row.meta)
            if decodedOk and type(decoded) == 'table' then
                message.mediaUrl = decoded.mediaUrl
                message.wpCode = decoded.wpCode
                message.wpSub = decoded.wpSub
            end
        end
        result[#result + 1] = message
    end
    return result
end

---@param threads table[]
---@param field string
---@return string[]
local function threadKeys(threads, field)
    local result = {}
    for index = 1, #threads do
        local value = threads[index][field]
        if value ~= nil then result[#result + 1] = value end
    end
    return result
end

---@param source number
---@return table
function businesses.inbox(source)
    local citizenId = player.getIdentifier(source)
    if not citizenId then return fail('Player not found') end

    local _, byJob = liveDirectory()
    if type(byJob) ~= 'table' then byJob = {} end

    local phoneNumber = digits(settings.getPhoneNumber(citizenId) or '')
    local personal = {}
    if phoneNumber ~= '' then
        local unread = msgstore.personalUnread(citizenId, phoneNumber)
        local threads = msgstore.citizenThreads(phoneNumber)
        local batch = msgstore.citizenThreadMessages(phoneNumber, threadKeys(threads, 'job'), THREAD_MESSAGES)
        for _, thread in ipairs(threads) do
            local entry = byJob[thread.job]
            personal[#personal + 1] = {
                key = thread.job,
                name = entry and entry.name or job.getLabel(thread.job) or thread.job,
                color = entry and entry.color or '#64748B',
                emoji = entry and entry.emoji or '💬',
                preview = thread.last_body or '',
                ts = (tonumber(thread.created_at) or 0) * 1000,
                unread = unread[thread.job] or 0,
                messages = serializeInbox(batch[thread.job]
                    or msgstore.threadMessages(thread.job, phoneNumber, THREAD_MESSAGES), 'citizen'),
            }
        end
    end

    local activeJob = job.getName(source)
    local staffEntry = activeJob and byJob[activeJob]
    local staffThreads = {}
    if staffEntry then
        local unread = msgstore.jobUnread(citizenId, activeJob)
        local threads = msgstore.jobThreads(activeJob)
        local batch = msgstore.jobThreadMessages(activeJob, threadKeys(threads, 'citizen_number'), THREAD_MESSAGES)
        for _, thread in ipairs(threads) do
            staffThreads[#staffThreads + 1] = {
                key = thread.citizen_number,
                name = (thread.citizen_name and thread.citizen_name ~= '') and thread.citizen_name or thread.citizen_number,
                color = staffEntry.color,
                emoji = staffEntry.emoji,
                preview = thread.last_body or '',
                ts = (tonumber(thread.created_at) or 0) * 1000,
                unread = unread[thread.citizen_number] or 0,
                messages = serializeInbox(batch[thread.citizen_number]
                    or msgstore.threadMessages(activeJob, thread.citizen_number, THREAD_MESSAGES), 'staff'),
            }
        end
    end

    return ok({ personal = personal, job = staffThreads, hasJob = staffEntry ~= nil })
end

---@param source number
---@param payload table
---@return table
function businesses.call(source, payload)
    payload = type(payload) == 'table' and payload or {}
    local _, byJobOrError = liveDirectory()
    if type(byJobOrError) ~= 'table' then return fail(byJobOrError) end
    local entry = byJobOrError[tostring(payload.job or '')]
    if not entry then return fail('Unknown business') end
    if not entry.canCall then return fail("You can't call this business") end

    local citizenId = player.getIdentifier(source)
    if not citizenId then return fail('Player not found') end
    if job.getName(source) == entry.id then return fail("You can't call the business you work for") end
    if calls.isBusy(source) then return fail('You are already on a call') end
    if not util.cooldown(citizenId, 'businesses:call', 3000) then return fail('Please wait a moment') end

    local targets = {}
    for targetCitizenId, targetSource in pairs(player.onlineCidMap()) do
        if targetSource ~= source and job.getName(targetSource) == entry.id and job.getDuty(targetSource) == true then
            targets[#targets + 1] = { src = targetSource, cid = targetCitizenId }
        end
    end
    if #targets == 0 then return fail('No one is on duty right now') end

    return calls.callGroup(source, targets, entry.name, 'business:' .. entry.id)
end

---@param jobName string
---@param title string
---@param body string
---@param thread string
local function notifyStaff(jobName, title, body, thread)
    for _, source in pairs(player.onlineCidMap()) do
        if job.getName(source) == jobName and job.getDuty(source) == true then
            TriggerClientEvent('sd-phone:client:notify', source, {
                app = 'services',
                appId = 'services',
                title = title,
                body = body,
                time = 'now',
                quietInApp = true,
            })
            TriggerClientEvent('sd-phone:client:services:inbox', source, {
                job = jobName,
                thread = thread,
            })
        end
    end
end

---@param source number
---@param payload table
---@return table
function businesses.message(source, payload)
    payload = type(payload) == 'table' and payload or {}
    local _, byJobOrError = liveDirectory()
    if type(byJobOrError) ~= 'table' then return fail(byJobOrError) end
    local entry = byJobOrError[tostring(payload.job or '')]
    if not entry then return fail('Unknown business') end
    if not entry.canMessage then return fail("You can't message this business") end

    local citizenId = player.getIdentifier(source)
    if not citizenId then return fail('Player not found') end
    if not util.cooldown(citizenId, 'businesses:message', 1000)
        or not util.rateLimit(citizenId, 'businesses:message', MSG_WINDOW, MSG_MAX)
    then
        return fail('Please wait a moment')
    end

    local kind, body, meta = parseDraft(payload)
    if not kind then return fail(body) end
    local phoneNumber = digits(settings.ensurePhoneNumber(citizenId) or '')
    if phoneNumber == '' then return fail('No phone number') end
    local playerName = player.getName(source)

    msgstore.insert({
        id = msgstore.newId(),
        job = entry.id,
        citizenNumber = phoneNumber,
        citizenName = playerName,
        sender = 'citizen',
        body = body,
        kind = kind,
        meta = meta,
        createdAt = os.time(),
    })
    notifyStaff(entry.id, entry.name, playerName .. ': ' .. body, phoneNumber)
    TriggerEvent('sd-phone:server:services:message', {
        source = source,
        citizenid = citizenId,
        job = entry.id,
        label = entry.name,
        number = phoneNumber,
        name = playerName,
        kind = kind,
        body = body,
        meta = meta,
    })
    return ok({ inbox = businesses.inbox(source).data })
end

---@param source number
---@param payload table
---@return table
function businesses.reply(source, payload)
    payload = type(payload) == 'table' and payload or {}
    local citizenId = player.getIdentifier(source)
    if not citizenId then return fail('Player not found') end

    local activeJob = job.getName(source)
    local _, byJob = liveDirectory()
    local entry = type(byJob) == 'table' and activeJob and byJob[activeJob]
    if not entry then return fail("You're not in a listed business") end
    if not util.cooldown(citizenId, 'businesses:reply', 1000)
        or not util.rateLimit(citizenId, 'businesses:reply', MSG_WINDOW, REPLY_MAX)
    then
        return fail('Please wait a moment')
    end

    local phoneNumber = digits(payload.citizen):sub(1, 32)
    if phoneNumber == '' or not msgstore.threadExists(activeJob, phoneNumber) then
        return fail('Missing thread')
    end
    local kind, body, meta = parseDraft(payload)
    if not kind then return fail(body) end
    local staffName = player.getName(source)

    msgstore.insert({
        id = msgstore.newId(),
        job = activeJob,
        citizenNumber = phoneNumber,
        sender = 'staff',
        staffCid = citizenId,
        staffName = staffName,
        body = body,
        kind = kind,
        meta = meta,
        createdAt = os.time(),
    })

    local targetCitizenId = settings.getCitizenByNumber(phoneNumber)
    local targetSource = targetCitizenId and player.getAnySourceByIdentifier(targetCitizenId)
    if targetSource then
        TriggerClientEvent('sd-phone:client:notify', targetSource, {
            app = 'services',
            appId = 'services',
            title = entry.name,
            body = body,
            time = 'now',
            quietInApp = true,
        })
        TriggerClientEvent('sd-phone:client:services:inbox', targetSource, {
            job = activeJob,
            thread = phoneNumber,
        })
    end
    TriggerClientEvent('sd-phone:client:services:inbox', source, {
        job = activeJob,
        thread = phoneNumber,
    })
    return ok({ inbox = businesses.inbox(source).data })
end

---@param source number
---@param payload table
---@return table
function businesses.markRead(source, payload)
    payload = type(payload) == 'table' and payload or {}
    local citizenId = player.getIdentifier(source)
    if not citizenId then return fail('Player not found') end
    if not util.rateLimit(citizenId, 'businesses:markRead', MSG_WINDOW, READ_MAX) then
        return fail('Please wait a moment')
    end

    local key = tostring(payload.key or '')
    if key == '' then return fail('Missing thread') end
    if payload.scope == 'job' then
        local activeJob = job.getName(source)
        local _, byJob = liveDirectory()
        if type(byJob) ~= 'table' or not activeJob or not byJob[activeJob] then return fail('Missing thread') end
        local phoneNumber = digits(key):sub(1, 32)
        if not msgstore.threadExists(activeJob, phoneNumber) then return fail('Missing thread') end
        msgstore.markRead(citizenId, activeJob, phoneNumber, os.time())
        return ok()
    end

    local ownNumber = digits(settings.getPhoneNumber(citizenId) or '')
    local businessId = key:sub(1, 64)
    if ownNumber == '' or not msgstore.threadExists(businessId, ownNumber) then return fail('Missing thread') end
    msgstore.markRead(citizenId, businessId, ownNumber, os.time())
    return ok()
end

return businesses
