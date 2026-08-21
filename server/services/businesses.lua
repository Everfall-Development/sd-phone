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
local overrides = type(servicesConfig.DirectoryOverrides) == 'table'
    and servicesConfig.DirectoryOverrides or {}
local visibility = type(servicesConfig.DirectoryVisibility) == 'table'
    and servicesConfig.DirectoryVisibility or {}

local function stringSet(values)
    local result = {}
    if type(values) ~= 'table' then return result end
    for _, value in ipairs(values) do
        if type(value) == 'string' and value ~= '' then result[value] = true end
    end
    return result
end

local alwaysIncludeTypes = stringSet(visibility.AlwaysIncludeTypes)
local excludedTypes = stringSet(visibility.ExcludeTypes)
local excludedJobPrefixes = type(visibility.ExcludeJobPrefixes) == 'table'
    and visibility.ExcludeJobPrefixes or {}

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
local DIRECTORY_MAX = 30
local INBOX_MAX = 30
local MAX_THREADS = 50
local MAX_DRAFTS = 8
local THREAD_MESSAGES = 100
local messageImageHosts = type(servicesConfig.MessageImageHosts) == 'table'
    and servicesConfig.MessageImageHosts or {}

local businesses = {}

---@param source number
---@return boolean
local function hasPhone(source)
    local succeeded, color = pcall(function()
        return exports['sd-phone']:hasPhone(source)
    end)
    return succeeded and type(color) == 'string' and color ~= ''
end

---@param source number
---@return table|nil
local function requirePhone(source)
    if hasPhone(source) then return nil end
    return fail('You need a phone to use Businesses')
end

---@param ... any
---@return string|nil
local function firstNonEmpty(...)
    for index = 1, select('#', ...) do
        local value = select(index, ...)
        if type(value) == 'string' then
            local text = trim(value)
            if text ~= '' then return text end
        end
    end
    return nil
end

---@param host string lowercased hostname
---@param entries table
---@return boolean
local function hostAllowed(host, entries)
    for _, raw in ipairs(entries) do
        local entry = type(raw) == 'string' and trim(raw):lower() or ''
        if entry:sub(1, 2) == '*.' then
            local suffix = entry:sub(2)
            if host == entry:sub(3) or host:sub(-#suffix) == suffix then return true end
        elseif entry ~= '' and host == entry then
            return true
        end
    end
    return false
end

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

---@param businessId string
---@param business table
---@param duty table<string, boolean>
---@return table|nil
local function directoryEntry(businessId, business, duty)
    for _, prefix in ipairs(excludedJobPrefixes) do
        if type(prefix) == 'string' and prefix ~= '' and lib.string.startsWith(businessId, prefix) then return nil end
    end

    if business.Enabled == false then return nil end
    local blip = business.Blip
    if type(blip) ~= 'table' then return nil end

    local configured = overrides[businessId]
    local override = type(configured) == 'table' and configured or {}

    local categoryKey = tostring(business.Type or 'general')
    local visible = blip.Enable == true
    if alwaysIncludeTypes[categoryKey] then visible = true end
    if excludedTypes[categoryKey] then visible = false end
    if override.visible ~= nil then visible = override.visible == true end
    if override.hidden == true then visible = false end
    if not visible then return nil end

    local style = categoryStyles[categoryKey] or categoryStyles.general
    local name = firstNonEmpty(override.label, business.Name, blip.Name, job.getLabel(businessId), businessId)
    local storefront = business.Storefront or {}
    local advertisement = storefront.Advertisement or {}

    local location = firstNonEmpty(
        override.location,
        business.Location,
        business.Address,
        blip.Location,
        style.label
    )

    return {
        id = businessId,
        name = name,
        category = style.label,
        location = location or style.label,
        color = firstNonEmpty(override.color, style.color),
        emoji = firstNonEmpty(override.emoji, style.emoji),
        iconUrl = firstNonEmpty(override.iconUrl, advertisement.Icon, storefront.ImageUrl),
        status = duty[businessId] and 'open' or 'closed',
        onDuty = duty[businessId] == true,
        canCall = override.canCall ~= false,
        canMessage = override.canMessage ~= false,
        emergency = false,
        coords = normalizeCoords(override.coords or blip.Coords or business.Coords),
    }
end

---@return table[]|nil entries
---@return table<string, table>|string byJobOrError
local function liveDirectory()
    if GetResourceState('ef_businesses') ~= 'started' then
        return nil, 'Businesses are unavailable right now.'
    end

    local succeeded, sourceBusinesses = pcall(function()
        return exports.ef_businesses:GetBusinesses()
    end)
    if not succeeded or type(sourceBusinesses) ~= 'table' then
        if not succeeded and lib.print and lib.print.error then
            lib.print.error(('[sd-phone] Businesses directory provider failed: %s'):format(tostring(sourceBusinesses)))
        end
        return nil, 'Businesses are unavailable right now.'
    end

    local duty = onDutyJobs()
    local entries = {}
    local byJob = {}

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
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)

    return entries, byJob
end

---@return table[]|nil entries
---@return string|nil error
function businesses.companyList()
    local entries, errorMessage = liveDirectory()
    return entries, errorMessage
end

---@param source number
---@return table
function businesses.directory(source)
    local phoneError = requirePhone(source)
    if phoneError then return phoneError end
    local citizenId = player.getIdentifier(source)
    if not citizenId then return fail('Player not found') end
    if not util.rateLimit(citizenId, 'businesses:directory', MSG_WINDOW, DIRECTORY_MAX) then
        return fail('Please wait a moment')
    end

    local entries, byJobOrError = liveDirectory()
    if not entries then return fail(byJobOrError) end
    return ok({ companies = entries })
end

---@param value any
---@return string|nil
local function normalizeMediaUrl(value)
    if type(value) ~= 'string' then return nil end
    local url = trim(value):sub(1, 512)
    local isHttp = lib.string.startsWith(url, 'http://')
        or lib.string.startsWith(url, 'https://')
    local authority = url:lower():match('^https?://([^/%?#]+)')
    if authority and authority:find('@', 1, true) then return nil end
    local host = authority and (authority:match('^([%w%.%-]+)$')
        or authority:match('^([%w%.%-]+):%d+$'))
    if url == '' or not isHttp or url:find('[%c%s]') or not host or not hostAllowed(host, messageImageHosts) then
        return nil
    end
    return url
end

---@param payload table
---@return string|nil kind
---@return string body
---@return string|nil meta
local function parseDraft(payload)
    if type(payload) ~= 'table' then return nil, 'Invalid message' end
    local kind = tostring(payload.kind or 'text')
    if kind == 'image' then
        local url = normalizeMediaUrl(payload.mediaUrl)
        if not url then return nil, 'Invalid image' end
        return 'image', '📷 Photo', json.encode({ mediaUrl = url })
    end
    if kind == 'location' then
        local waypoint = util.limitedString(payload.wpCode, 256)
        if not waypoint or not lib.string.startsWith(waypoint, 'SDW1:') then return nil, 'Invalid location' end
        local meta = { wpCode = waypoint }
        local subtitle = util.limitedString(payload.wpSub, 128)
        if subtitle then meta.wpSub = subtitle end
        return 'location', '📍 Location', json.encode(meta)
    end

    local body = util.limitedString(payload.body, 300)
    if not body then return nil, 'Empty message' end
    return 'text', body, nil
end

---@param payload table
---@return table[]|nil drafts
---@return string|nil error
local function parseDrafts(payload)
    if type(payload) ~= 'table' then return nil, 'Invalid message' end
    if payload.drafts == nil then
        local kind, body, meta = parseDraft(payload)
        if not kind then return nil, body end
        return { { kind = kind, body = body, meta = meta } }
    end

    if type(payload.drafts) ~= 'table' or #payload.drafts < 1 then
        return nil, 'Invalid message batch'
    end
    if #payload.drafts > MAX_DRAFTS then
        return nil, 'Too many messages'
    end

    local drafts = {}
    for index = 1, #payload.drafts do
        local kind, body, meta = parseDraft(payload.drafts[index])
        if not kind then return nil, body end
        drafts[#drafts + 1] = { kind = kind, body = body, meta = meta }
    end
    return drafts
end

local function notificationBody(drafts)
    for index = #drafts, 1, -1 do
        if drafts[index].kind == 'text' then return drafts[index].body end
    end
    return drafts[1].body
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
                message.mediaUrl = normalizeMediaUrl(decoded.mediaUrl)
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
    for index = 1, math.min(#threads, MAX_THREADS) do
        local value = threads[index][field]
        if value ~= nil and value ~= '' then result[#result + 1] = value end
    end
    return result
end

---@param source number
---@param byJob table<string, table> authorized directory snapshot
---@return table|nil data
---@return string|nil error
local function buildInbox(source, byJob)
    local citizenId = player.getIdentifier(source)
    if not citizenId then return nil, 'Player not found' end

    local phoneNumber = digits(settings.getPhoneNumber(citizenId) or '')
    local personal = {}
    if phoneNumber ~= '' then
        local unread = msgstore.personalUnread(citizenId, phoneNumber, MAX_THREADS)
        local threads = msgstore.citizenThreads(phoneNumber, MAX_THREADS)
        local batch = msgstore.citizenThreadMessages(phoneNumber, threadKeys(threads, 'job'), THREAD_MESSAGES)
        for _, thread in ipairs(threads) do
            local entry = byJob[thread.job]
            personal[#personal + 1] = {
                key = thread.job,
                name = entry and entry.name or job.getLabel(thread.job) or thread.job,
                color = entry and entry.color or '#64748B',
                emoji = entry and entry.emoji or '💬',
                iconUrl = entry and entry.iconUrl or nil,
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
        local unread = msgstore.jobUnread(citizenId, activeJob, MAX_THREADS)
        local threads = msgstore.jobThreads(activeJob, MAX_THREADS)
        local batch = msgstore.jobThreadMessages(activeJob, threadKeys(threads, 'citizen_number'), THREAD_MESSAGES)
        for _, thread in ipairs(threads) do
            staffThreads[#staffThreads + 1] = {
                key = thread.citizen_number,
                name = (thread.citizen_name and thread.citizen_name ~= '') and thread.citizen_name or thread.citizen_number,
                color = staffEntry.color,
                emoji = staffEntry.emoji,
                iconUrl = staffEntry.iconUrl,
                preview = thread.last_body or '',
                ts = (tonumber(thread.created_at) or 0) * 1000,
                unread = unread[thread.citizen_number] or 0,
                messages = serializeInbox(batch[thread.citizen_number]
                    or msgstore.threadMessages(activeJob, thread.citizen_number, THREAD_MESSAGES), 'staff'),
            }
        end
    end

    return {
        personal = personal,
        job = staffThreads,
        hasJob = staffEntry ~= nil,
    }
end

---@param source number
---@return table
function businesses.inbox(source)
    local phoneError = requirePhone(source)
    if phoneError then return phoneError end
    local citizenId = player.getIdentifier(source)
    if not citizenId then return fail('Player not found') end
    if not util.rateLimit(citizenId, 'businesses:inbox', MSG_WINDOW, INBOX_MAX) then
        return fail('Please wait a moment')
    end

    local _, byJobOrError = liveDirectory()
    if type(byJobOrError) ~= 'table' then return fail(byJobOrError) end

    local data, errorMessage = buildInbox(source, byJobOrError)
    if not data then return fail(errorMessage) end
    return ok(data)
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
                link = { services = { scope = 'job', thread = thread } },
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
    local phoneError = requirePhone(source)
    if phoneError then return phoneError end
    payload = type(payload) == 'table' and payload or {}
    local _, byJobOrError = liveDirectory()
    if type(byJobOrError) ~= 'table' then return fail(byJobOrError) end
    local entry = byJobOrError[tostring(payload.job or '')]
    if not entry then return fail('Unknown business') end
    if not entry.canMessage then return fail("You can't message this business") end

    local citizenId = player.getIdentifier(source)
    if not citizenId then return fail('Player not found') end
    local drafts, draftError = parseDrafts(payload)
    if not drafts then return fail(draftError) end
    if not util.cooldown(citizenId, 'businesses:message', 1000)
        or not util.rateLimit(citizenId, 'businesses:message', MSG_WINDOW, MSG_MAX)
    then
        return fail('Please wait a moment')
    end

    local phoneNumber = digits(settings.ensurePhoneNumber(citizenId) or '')
    if phoneNumber == '' then return fail('No phone number') end
    local playerName = player.getName(source)
    local batchId = msgstore.newId()

    for index, draft in ipairs(drafts) do
        msgstore.insert({
            id = ('%s-%02d'):format(batchId, index),
            job = entry.id,
            citizenNumber = phoneNumber,
            citizenName = playerName,
            sender = 'citizen',
            body = draft.body,
            kind = draft.kind,
            meta = draft.meta,
            createdAt = os.time(),
        })
        TriggerEvent('sd-phone:server:services:message', {
            source = source,
            citizenid = citizenId,
            job = entry.id,
            label = entry.name,
            number = phoneNumber,
            name = playerName,
            kind = draft.kind,
            body = draft.body,
            meta = draft.meta,
        })
    end
    notifyStaff(entry.id, entry.name, playerName .. ': ' .. notificationBody(drafts), phoneNumber)

    local inbox = buildInbox(source, byJobOrError)
    return ok({ inbox = inbox or {} })
end

---@param source number
---@param payload table
---@return table
function businesses.reply(source, payload)
    local phoneError = requirePhone(source)
    if phoneError then return phoneError end
    payload = type(payload) == 'table' and payload or {}
    local citizenId = player.getIdentifier(source)
    if not citizenId then return fail('Player not found') end

    local activeJob = job.getName(source)
    local _, byJobOrError = liveDirectory()
    if type(byJobOrError) ~= 'table' then return fail(byJobOrError) end
    local entry = activeJob and byJobOrError[activeJob]
    if not entry then return fail("You're not in a listed business") end
    if entry.canMessage == false then return fail("You can't message this business") end
    local drafts, draftError = parseDrafts(payload)
    if not drafts then return fail(draftError) end
    if not util.cooldown(citizenId, 'businesses:reply', 1000)
        or not util.rateLimit(citizenId, 'businesses:reply', MSG_WINDOW, REPLY_MAX)
    then
        return fail('Please wait a moment')
    end

    local phoneNumber = digits(payload.citizen):sub(1, 32)
    if phoneNumber == '' or not msgstore.threadExists(activeJob, phoneNumber) then
        return fail('Missing thread')
    end
    local staffName = player.getName(source)
    local batchId = msgstore.newId()

    for index, draft in ipairs(drafts) do
        msgstore.insert({
            id = ('%s-%02d'):format(batchId, index),
            job = activeJob,
            citizenNumber = phoneNumber,
            sender = 'staff',
            staffCid = citizenId,
            staffName = staffName,
            body = draft.body,
            kind = draft.kind,
            meta = draft.meta,
            createdAt = os.time(),
        })
    end

    local targetCitizenId = settings.getCitizenByNumber(phoneNumber)
    local targetSource = targetCitizenId and player.getAnySourceByIdentifier(targetCitizenId)
    if targetSource then
        TriggerClientEvent('sd-phone:client:notify', targetSource, {
            app = 'services',
            appId = 'services',
            title = entry.name,
            body = notificationBody(drafts),
            link = { services = { scope = 'personal', thread = activeJob } },
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
    local inbox = buildInbox(source, byJobOrError)
    return ok({ inbox = inbox or {} })
end

---@param source number
---@param payload table
---@return table
function businesses.markRead(source, payload)
    local phoneError = requirePhone(source)
    if phoneError then return phoneError end
    payload = type(payload) == 'table' and payload or {}
    local citizenId = player.getIdentifier(source)
    if not citizenId then return fail('Player not found') end
    if not util.rateLimit(citizenId, 'businesses:markRead', MSG_WINDOW, READ_MAX) then
        return fail('Please wait a moment')
    end

    local key = tostring(payload.key or '')
    if key == '' then return fail('Missing thread') end
    if payload.scope ~= 'job' and payload.scope ~= 'personal' then
        return fail('Missing thread')
    end

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
