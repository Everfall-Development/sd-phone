---@type table Calendar persistence module. Every row is owned by a real character citizenid;
---events and day notes are normalized so concurrent phone/tablet edits cannot overwrite unrelated
---calendar data.
local store = {}

---@type integer Maximum rows returned for one character. The action layer enforces the same cap
---for new records, keeping reads and storage bounded.
local EVENT_CAP <const> = 1000
local NOTE_CAP <const> = 730

---Creates the authoritative shared Calendar tables. This module is new in v0.9.4, so existing
---servers need only the idempotent CREATE TABLE path; there are no prior columns to back-fill.
function store.ensureSchema()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `phone_calendar_events` (
            `citizenid`  VARCHAR(60)  NOT NULL,
            `id`         VARCHAR(40)  NOT NULL,
            `day_key`    CHAR(10)     NOT NULL,
            `title`      VARCHAR(100) NOT NULL,
            `all_day`    TINYINT(1)   NOT NULL DEFAULT 0,
            `start_time` CHAR(5)      NULL,
            `end_time`   CHAR(5)      NULL,
            `location`   VARCHAR(160) NOT NULL DEFAULT '',
            `notes`      TEXT         NOT NULL,
            `color`      CHAR(7)      NOT NULL,
            `created_at` BIGINT UNSIGNED NOT NULL,
            `updated_at` BIGINT UNSIGNED NOT NULL,
            PRIMARY KEY (`citizenid`, `id`),
            KEY `calendar_day` (`citizenid`, `day_key`, `all_day`, `start_time`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `phone_calendar_day_notes` (
            `citizenid` VARCHAR(60) NOT NULL,
            `day_key`   CHAR(10)    NOT NULL,
            `note`      TEXT        NOT NULL,
            `updated_at` BIGINT UNSIGNED NOT NULL,
            PRIMARY KEY (`citizenid`, `day_key`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

---Lists the caller's events in calendar order. Read-only and citizen-scoped.
---@param citizenid string real framework character id
---@return table[] events
function store.listEvents(citizenid)
    return MySQL.query.await(([[
        SELECT id, day_key, title, all_day, start_time, end_time, location, notes, color
        FROM `phone_calendar_events`
        WHERE citizenid = ?
        ORDER BY day_key ASC, all_day DESC, start_time ASC, id ASC
        LIMIT %d
    ]]):format(EVENT_CAP), { citizenid }) or {}
end

---Lists day notes as rows. Read-only and citizen-scoped.
---@param citizenid string real framework character id
---@return table[] notes
function store.listDayNotes(citizenid)
    return MySQL.query.await(([[
        SELECT day_key, note
        FROM `phone_calendar_day_notes`
        WHERE citizenid = ?
        ORDER BY day_key ASC
        LIMIT %d
    ]]):format(NOTE_CAP), { citizenid }) or {}
end

---Whether a specific owned event already exists.
---@param citizenid string
---@param id string
---@return boolean
function store.eventExists(citizenid, id)
    return MySQL.scalar.await([[
        SELECT 1 FROM `phone_calendar_events`
        WHERE citizenid = ? AND id = ? LIMIT 1
    ]], { citizenid, id }) ~= nil
end

---Owned event count used only when inserting a brand-new id.
---@param citizenid string
---@return integer
function store.eventCount(citizenid)
    return tonumber(MySQL.scalar.await(
        'SELECT COUNT(*) FROM `phone_calendar_events` WHERE citizenid = ?', { citizenid }
    )) or 0
end

---Inserts or updates one owned event. The compound primary key is the final ownership guard even
---if two characters choose the same client-generated id.
---@param citizenid string
---@param event table sanitized canonical event
---@param now integer unix time
function store.upsertEvent(citizenid, event, now)
    MySQL.query.await([[
        INSERT INTO `phone_calendar_events`
            (citizenid, id, day_key, title, all_day, start_time, end_time, location, notes,
             color, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            day_key = VALUES(day_key),
            title = VALUES(title),
            all_day = VALUES(all_day),
            start_time = VALUES(start_time),
            end_time = VALUES(end_time),
            location = VALUES(location),
            notes = VALUES(notes),
            color = VALUES(color),
            updated_at = VALUES(updated_at)
    ]], {
        citizenid, event.id, event.dayKey, event.title, event.allDay and 1 or 0,
        event.start, event['end'], event.location, event.notes, event.color, now, now,
    })
end

---Deletes one event only when both id and owner match. Idempotent.
---@param citizenid string
---@param id string
function store.deleteEvent(citizenid, id)
    MySQL.update.await(
        'DELETE FROM `phone_calendar_events` WHERE citizenid = ? AND id = ?',
        { citizenid, id }
    )
end

---Upserts one owned day note, or deletes the row for an empty note.
---@param citizenid string
---@param dayKey string
---@param note string
---@param now integer unix time
function store.saveDayNote(citizenid, dayKey, note, now)
    if note == '' then
        MySQL.update.await(
            'DELETE FROM `phone_calendar_day_notes` WHERE citizenid = ? AND day_key = ?',
            { citizenid, dayKey }
        )
        return
    end

    MySQL.query.await([[
        INSERT INTO `phone_calendar_day_notes` (citizenid, day_key, note, updated_at)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE note = VALUES(note), updated_at = VALUES(updated_at)
    ]], { citizenid, dayKey, note, now })
end

return store
