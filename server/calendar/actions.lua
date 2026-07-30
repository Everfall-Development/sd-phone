---@type table Calendar persistence layer (server.calendar.store).
local store = require 'server.calendar.store'
---@type table Player bridge. Calendar is character-owned, so it deliberately uses the real
---framework identifier rather than a swappable SIM identity.
local player = require 'bridge.server.player'
---@type table Shared server helpers for envelopes and linear-time trimming.
local util = require 'server.util'

local actions = {}

local EVENT_CAP <const> = 1000
local MAX_TITLE <const> = 100
local MAX_LOCATION <const> = 160
local MAX_NOTES <const> = 2000
local MAX_DAY_NOTE <const> = 4000
local DEFAULT_COLOR <const> = '#ff453a'

---@param src integer
---@return string|nil citizenid
local function citizenidOf(src)
    return player.getRealIdentifier(src)
end

---@param value any
---@param maximum integer
---@return string
local function cleanText(value, maximum)
    if type(value) ~= 'string' then return '' end
    if #value > maximum then return value:sub(1, maximum) end
    return value
end

---@param year integer
---@return boolean
local function leapYear(year)
    return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

---@param value any
---@return string|nil
local function validDayKey(value)
    if type(value) ~= 'string' then return nil end
    local year, month, day = value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    if not year or not month or not day or year < 1900 or year > 2200 or month < 1 or month > 12 then
        return nil
    end
    local days = { 31, leapYear(year) and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if day < 1 or day > days[month] then return nil end
    return value
end

---@param value any
---@return string|nil
local function validTime(value)
    if type(value) ~= 'string' then return nil end
    local hour, minute = value:match('^(%d%d):(%d%d)$')
    hour, minute = tonumber(hour), tonumber(minute)
    if not hour or not minute or hour > 23 or minute > 59 then return nil end
    return value
end

---@param payload any
---@return table|nil event
---@return string|nil error
local function sanitizeEvent(payload)
    if type(payload) ~= 'table' then return nil, 'Invalid event' end
    local id = payload.id
    if type(id) ~= 'string' or id == '' or #id > 40 or not id:match('^[%w_%-]+$') then
        return nil, 'Invalid event id'
    end
    local dayKey = validDayKey(payload.dayKey)
    if not dayKey then return nil, 'Invalid event date' end
    local title = util.trim(payload.title)
    if title == '' then return nil, 'Event title is required' end
    if #title > MAX_TITLE then title = title:sub(1, MAX_TITLE) end

    local allDay = payload.allDay == true
    local startTime, endTime
    if not allDay then
        startTime = validTime(payload.start)
        endTime = validTime(payload['end'])
        if not startTime or not endTime then return nil, 'Invalid event time' end
    end

    local color = type(payload.color) == 'string' and payload.color:match('^#%x%x%x%x%x%x$')
        and payload.color or DEFAULT_COLOR
    return {
        id = id,
        dayKey = dayKey,
        title = title,
        allDay = allDay,
        start = startTime,
        ['end'] = endTime,
        location = cleanText(payload.location, MAX_LOCATION),
        notes = cleanText(payload.notes, MAX_NOTES),
        color = color,
    }
end

---@param row table database row
---@return table event
local function eventFromRow(row)
    return {
        id = row.id,
        dayKey = row.day_key,
        title = row.title,
        allDay = util.truthy(row.all_day),
        start = row.start_time,
        ['end'] = row.end_time,
        location = row.location or '',
        notes = row.notes or '',
        color = row.color or DEFAULT_COLOR,
    }
end

---@param src integer
---@param change table
local function notifyChanged(src, change)
    TriggerClientEvent('sd-phone:client:calendar:changed', src, change)
    TriggerClientEvent('sd-phone:client:device:dataChanged', src, {
        domain = 'calendar', operation = change.operation, id = change.id, dayKey = change.dayKey,
    })
end

---Lists the canonical Calendar state for the calling character.
---@param src integer
---@return table
function actions.list(src)
    local citizenid = citizenidOf(src)
    if not citizenid then return util.fail('Player not found') end

    local events = {}
    for _, row in ipairs(store.listEvents(citizenid)) do
        events[#events + 1] = eventFromRow(row)
    end
    local dayNotes = {}
    for _, row in ipairs(store.listDayNotes(citizenid)) do
        dayNotes[row.day_key] = row.note
    end
    return util.ok({ events = events, dayNotes = dayNotes })
end

---Saves one canonical event. New ids respect the per-character cap; updates remain allowed at
---the cap. Every lookup and write uses the caller's citizenid.
---@param src integer
---@param payload any
---@return table
function actions.save(src, payload)
    local citizenid = citizenidOf(src)
    if not citizenid then return util.fail('Player not found') end
    local event, err = sanitizeEvent(payload)
    if not event then
        lib.print.debug(('[sd-phone] Calendar rejected save source=%s reason=%s'):format(src, err))
        return util.fail(err or 'Invalid event')
    end
    if not store.eventExists(citizenid, event.id) and store.eventCount(citizenid) >= EVENT_CAP then
        return util.fail('Calendar event limit reached')
    end

    store.upsertEvent(citizenid, event, os.time())
    notifyChanged(src, { operation = 'upsert', id = event.id, event = event })
    lib.print.debug(('[sd-phone] Calendar event saved source=%s id=%s'):format(src, event.id))
    return util.ok(event)
end

---Deletes one owned event by id. A caller cannot address another citizen's row because the store
---always includes citizenid in the predicate.
---@param src integer
---@param payload any
---@return table
function actions.delete(src, payload)
    local citizenid = citizenidOf(src)
    if not citizenid then return util.fail('Player not found') end
    local id = type(payload) == 'table' and payload.id or nil
    if type(id) ~= 'string' or id == '' or #id > 40 or not id:match('^[%w_%-]+$') then
        return util.fail('Invalid event id')
    end
    store.deleteEvent(citizenid, id)
    notifyChanged(src, { operation = 'delete', id = id })
    lib.print.debug(('[sd-phone] Calendar event deleted source=%s id=%s'):format(src, id))
    return util.ok({ id = id })
end

---Saves or clears one day note. Day keys are validated calendar dates and note text is bounded.
---@param src integer
---@param payload any
---@return table
function actions.saveDayNote(src, payload)
    local citizenid = citizenidOf(src)
    if not citizenid then return util.fail('Player not found') end
    local dayKey = validDayKey(type(payload) == 'table' and payload.dayKey or nil)
    if not dayKey then return util.fail('Invalid note date') end
    local note = cleanText(type(payload) == 'table' and payload.note or nil, MAX_DAY_NOTE)
    store.saveDayNote(citizenid, dayKey, note, os.time())
    notifyChanged(src, { operation = 'note', dayKey = dayKey, note = note })
    lib.print.debug(('[sd-phone] Calendar day note saved source=%s day=%s'):format(src, dayKey))
    return util.ok({ dayKey = dayKey, note = note })
end

return actions
