---@type table Data layer for the lb-phone import (server.migrate.store): probes whether lb-phone's
---tables exist, reads lb-phone rows, and runs the chunked INSERT IGNORE writers into sd-phone's own
---tables. Table names are built from a validated prefix; every value is bound as a ? parameter.
local store = {}

local config   = require 'configs.config'
local settings = require 'server.settings.store'
local util     = require 'server.util'

---@type string Validated lb-phone table prefix. Falls back to the default when the configured
---value is not a plain identifier.
local PREFIX = (config.Migrate and config.Migrate.sourcePrefix) or 'phone_'
if type(PREFIX) ~= 'string' or not PREFIX:match('^[%w_]*$') then PREFIX = 'phone_' end

---An lb-phone table name for `name`, prefixed. Callers pass literal suffixes only. When the
---name collides with an sd-phone table (notes, photos, photo_albums, mail_accounts, ...), the
---schema bootstrap renames the lb-phone original to `<name>_lb` (util.rescueLegacyTable);
---prefer that rescued copy whenever it exists so the importer still reads the lb-phone data.
---@param name string suffix, e.g. 'phones'
---@return string full table name
local function lbt(name)
    local full = PREFIX .. name
    local rescued = full .. '_lb'
    local n = MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema = DATABASE() AND table_name = ? AND table_type = 'BASE TABLE'
    ]], { rescued })
    if (tonumber(n) or 0) > 0 then return rescued end
    return full
end

store.lbTable = lbt

---@type string Session-scoped table holding the phone numbers that resolved to a character, so the
---readers can filter in SQL instead of hauling whole tables into Lua and discarding them.
---Declared here, above every reader: a local defined later in the file is not in scope for functions
---defined earlier, and they would silently see a nil global instead.
local OWNED = '_sdphone_migrate_owned'

---Rows fetched per migration read. oxmysql warns at 1,000 rows by default; keeping these one-off
---catalog scans below that threshold avoids a giant bridge result without changing the import.
local READ_CHUNK_SIZE = 500

---Resolves an lb-phone source table, or nil when this database has no lb data for it.
---
---Checking only that `phone_<name>` exists is not enough: for the names lb-phone and sd-phone share
---(photos, notes, photo_albums, mail_accounts, message_reactions) the bare name is sd-phone's OWN
---table once the schema bootstrap has run, and querying it with lb-phone's column names throws.
---`markerColumn` is a column only the lb-phone shape has, so a porter reads the bare table only when
---it really is lb-phone's.
---@param name string suffix, e.g. 'mail_accounts'
---@param markerColumn string|nil column unique to the lb-phone shape
---@return string|nil table name to read from
function store.lbSource(name, markerColumn)
    local full = PREFIX .. name
    local rescued = full .. '_lb'
    if store.tableExists(rescued) then return rescued end
    if not store.tableExists(full) then return nil end
    if markerColumn and not store.tableHasColumn(full, markerColumn) then return nil end
    return full
end

---True if a base table with this exact name exists in the current schema. Read-only.
---@param name string table name
---@return boolean
function store.tableExists(name)
    local n = MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema = DATABASE() AND table_name = ? AND table_type = 'BASE TABLE'
    ]], { name })
    return (tonumber(n) or 0) > 0
end

---True if the table has the given column. Read-only.
---@param name string table name
---@param column string column name
---@return boolean
function store.tableHasColumn(name, column)
    local n = MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.columns
        WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?
    ]], { name, column })
    return (tonumber(n) or 0) > 0
end

---Blocks until every target exists, or gives up after `tries` polls. A target is either a plain
---table name or `{ name, marker }`; with a marker the table must also carry that column — the
---names lb-phone shares with sd-phone exist from the start in the foreign shape, and only grow
---the marker once the schema bootstrap has moved the foreign table aside and rebuilt sd-phone's.
---@param targets (string|{ [1]: string, [2]: string })[] table names, optionally with a marker column
---@param tries integer max polls
---@param delayMs integer wait between polls
---@return boolean ready
function store.waitForTables(targets, tries, delayMs)
    for _ = 1, tries do
        local allThere = true
        for _, t in ipairs(targets) do
            local name   = type(t) == 'table' and t[1] or t
            local marker = type(t) == 'table' and t[2] or nil
            if not store.tableExists(name) or (marker and not store.tableHasColumn(name, marker)) then
                allThere = false
                break
            end
        end
        if allThere then return true end
        Wait(delayMs)
    end
    return false
end

---Creates the phone_migrations bookkeeping table if absent; one row per completed migration.
function store.ensureMarkerTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_migrations (
            name       VARCHAR(64) NOT NULL,
            applied_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
            stats      JSON        NULL,
            PRIMARY KEY (name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

---True if the named migration has already been recorded as done. Read-only.
---@param name string migration name
---@return boolean
function store.migrationDone(name)
    local hit = MySQL.scalar.await('SELECT 1 FROM phone_migrations WHERE name = ? LIMIT 1', { name })
    return hit ~= nil
end

---Records a migration as complete, stamping the per-domain stats as JSON. Idempotent (INSERT IGNORE).
---@param name string migration name
---@param stats table per-domain counts
function store.recordMigration(name, stats)
    MySQL.query.await(
        'INSERT IGNORE INTO phone_migrations (name, stats) VALUES (?, ?)',
        { name, json.encode(stats or {}) }
    )
end

---@type string Marker-row prefix for a single completed domain.
local DOMAIN_MARKER = 'lbphone:'

---The set of domain keys already imported. Gating per domain (rather than one marker for the whole
---import) is what lets a server that ran an earlier version pick up only the domains added since.
---@return table<string, boolean>
function store.completedDomains()
    local rows = MySQL.query.await(
        'SELECT name FROM phone_migrations WHERE name LIKE ?', { DOMAIN_MARKER .. '%' }) or {}
    local set = {}
    for _, r in ipairs(rows) do
        local key = tostring(r.name):sub(#DOMAIN_MARKER + 1)
        if key ~= '' then set[key] = true end
    end
    return set
end

---Marks one domain as imported, stamping its counts. Idempotent (INSERT IGNORE).
---@param key string domain key
---@param stats table counts returned by the porter
function store.recordDomain(key, stats)
    MySQL.query.await(
        'INSERT IGNORE INTO phone_migrations (name, stats) VALUES (?, ?)',
        { DOMAIN_MARKER .. key, json.encode(stats or {}) }
    )
end

---Backfills domain markers for an install that completed the pre-domain-marker import, so those
---domains are not needlessly re-run. Returns true when the legacy marker was found.
---@param legacyName string old whole-import marker name
---@param keys string[] domain keys that marker covered
---@return boolean backfilled
function store.backfillLegacyDomains(legacyName, keys)
    if not store.migrationDone(legacyName) then return false end
    local done = store.completedDomains()
    for _, key in ipairs(keys) do
        if not done[key] then store.recordDomain(key, { backfilled = true }) end
    end
    return true
end

---Loads the framework's persistent character roster. Current QBox normalizes account identifiers
---into `users` and links characters through `players.userId`; legacy QBCore keeps the license on
---`players`, while ESX uses `users.identifier`. A non-standard schema logs the query error and
---degrades to empty maps so the migration can abort without writing partial ownership data.
---@param frameworkName 'qbx'|'qb'|'esx'
---@return { cids: table<string, boolean>, licenseToCids: table<string, string[]> }
function store.loadRoster(frameworkName)
    local cids, licenseToCids = {}, {}

    local function addLicense(cid, license)
        if not license or license == '' then return end
        local bucket = licenseToCids[license]
        if not bucket then
            bucket = {}
            licenseToCids[license] = bucket
        end
        bucket[#bucket + 1] = cid
    end

    local ok, err = pcall(function()
        local lastCid = ''

        while true do
            local rows
            if frameworkName == 'esx' then
                rows = MySQL.query.await(([[
                    SELECT identifier AS citizenid, NULL AS license, NULL AS license2
                    FROM users
                    WHERE identifier > ?
                    ORDER BY identifier
                    LIMIT %d
                ]]):format(READ_CHUNK_SIZE), { lastCid }) or {}
            elseif frameworkName == 'qbx' then
                rows = MySQL.query.await(([[
                    SELECT p.citizenid, u.license, u.license2
                    FROM players p
                    LEFT JOIN users u ON u.userId = p.userId
                    WHERE p.citizenid > ?
                    ORDER BY p.citizenid
                    LIMIT %d
                ]]):format(READ_CHUNK_SIZE), { lastCid }) or {}
            else
                rows = MySQL.query.await(([[
                    SELECT citizenid, license, NULL AS license2
                    FROM players
                    WHERE citizenid > ?
                    ORDER BY citizenid
                    LIMIT %d
                ]]):format(READ_CHUNK_SIZE), { lastCid }) or {}
            end

            for _, r in ipairs(rows) do
                local cid = r.citizenid
                if cid and cid ~= '' then
                    cids[cid] = true
                    addLicense(cid, r.license)
                    if r.license2 ~= r.license then addLicense(cid, r.license2) end
                end
            end

            if #rows < READ_CHUNK_SIZE then break end
            lastCid = rows[#rows].citizenid
        end
    end)

    if not ok then
        print(('^1[sd-phone:migrate] failed to load the character roster: %s^0'):format(tostring(err)))
        return { cids = {}, licenseToCids = {} }
    end

    return { cids = cids, licenseToCids = licenseToCids }
end

---Every lb-phone phone: its owner id, number and lock pin. Read-only and paged so a large archive
---does not cross oxmysql's oversized-result warning threshold in a single query.
---@return { id: any, owner_id: string, phone_number: string, pin: string|nil }[]
function store.lbPhones()
    local tableName = lbt('phones')
    local phones, lastId = {}, ''

    while true do
        local rows = MySQL.query.await(([[
            SELECT id, owner_id, phone_number, pin
            FROM %s
            WHERE id > ?
            ORDER BY id
            LIMIT %d
        ]]):format(tableName, READ_CHUNK_SIZE), { lastId }) or {}

        for _, row in ipairs(rows) do phones[#phones + 1] = row end
        if #rows < READ_CHUNK_SIZE then break end
        lastId = rows[#rows].id
    end

    return phones
end

---Every lb-phone contact, tagged with its owner's number (`phone_number`). Read-only.
---@return table[]
function store.lbContacts()
    return MySQL.query.await(([[
        SELECT c.contact_phone_number, c.firstname, c.lastname, c.profile_image, c.email, c.address,
               c.favourite, c.phone_number
        FROM %s c JOIN `%s` o ON o.number = c.phone_number
    ]]):format(lbt('phone_contacts'), OWNED)) or {}
end

---Every lb-phone blocked-number pair (owner number -> blocked number). Read-only.
---@return { phone_number: string, blocked_number: string }[]
function store.lbBlocked()
    return MySQL.query.await(
        ('SELECT phone_number, blocked_number FROM %s'):format(lbt('phone_blocked_numbers'))) or {}
end

---Every lb-phone call, with the timestamp pre-converted to a unix epoch in SECONDS (sd-phone's
---called_at contract). Read-only. The two scalar ownership probes are deliberately separate: the
---single `owner = caller OR owner = callee` subquery makes MariaDB scan the entire owned-number
---table once per call. Each probe is instead a primary-key lookup, and keyset pages keep the result
---below oxmysql's warning threshold.
---@return { id: any, caller: string, callee: string, duration: number, answered: any, ts: number }[]
function store.lbCalls()
    local tableName = lbt('phone_calls')
    local calls, lastId = {}, 0

    while true do
        local rows = MySQL.query.await(([[
            SELECT c.id, c.caller, c.callee, c.duration, c.answered,
                   UNIX_TIMESTAMP(c.timestamp) AS ts
            FROM %s c
            WHERE c.id > ?
              AND ((SELECT o1.number FROM `%s` o1 WHERE o1.number = c.caller LIMIT 1) IS NOT NULL
                   OR (SELECT o2.number FROM `%s` o2 WHERE o2.number = c.callee LIMIT 1) IS NOT NULL)
            ORDER BY c.id
            LIMIT %d
        ]]):format(tableName, OWNED, OWNED, READ_CHUNK_SIZE), { lastId }) or {}

        for _, row in ipairs(rows) do calls[#calls + 1] = row end
        if #rows < READ_CHUNK_SIZE then break end
        lastId = rows[#rows].id
    end

    return calls
end

---Every lb-phone message channel, newest-activity epoch as `created_at` (seconds). Read-only.
---@return { id: any, is_group: any, name: string|nil, created_at: number }[]
function store.lbChannels()
    return MySQL.query.await(([[
        SELECT id, is_group, name, UNIX_TIMESTAMP(last_message_timestamp) AS created_at
        FROM %s
    ]]):format(lbt('message_channels'))) or {}
end

---Every lb-phone channel membership row. Grouped by the porter. Read-only.
---@return { channel_id: any, phone_number: string, is_owner: any }[]
function store.lbChannelMembers()
    return MySQL.query.await(
        ('SELECT channel_id, phone_number, is_owner FROM %s'):format(lbt('message_members'))) or {}
end

---Every lb-phone message, oldest-first within each channel, timestamp as a unix epoch in seconds.
---Loaded in one pass and grouped by channel in Lua. Read-only.
---@return { id: any, channel_id: any, sender: string, content: string|nil, attachments: string|nil, ts: number }[]
---Only messages in channels an owned number belongs to; the rest can never be attributed.
function store.lbMessages()
    return MySQL.query.await(([[
        SELECT m.id, m.channel_id, m.sender, m.content, m.attachments,
               UNIX_TIMESTAMP(m.timestamp) AS ts
        FROM %s m
        WHERE m.channel_id IN (
            SELECT mm.channel_id FROM %s mm JOIN `%s` o ON o.number = mm.phone_number
        )
        ORDER BY m.channel_id ASC, m.timestamp ASC
    ]]):format(lbt('message_messages'), lbt('message_members'), OWNED)) or {}
end

---Every lb-phone photo; `created_at` is kept as the raw datetime string. Read-only.
---@return { id: any, phone_number: string, link: string, is_favourite: any, created_at: string }[]
function store.lbPhotos()
    -- The timestamp comes back as unix seconds: oxmysql hands TIMESTAMP columns to Lua as
    -- millisecond numbers, which a TIMESTAMP insert then coerces to a zero date. The porter
    -- formats these seconds back into a DATETIME literal.
    return MySQL.query.await(([[
        SELECT p.id, p.phone_number, p.link, p.is_favourite, UNIX_TIMESTAMP(p.`timestamp`) AS created_ts
        FROM %s p JOIN `%s` o ON o.number = p.phone_number
    ]]):format(lbt('photos'), OWNED)) or {}
end

---Every lb-phone photo album. Read-only.
---@return { id: any, phone_number: string, title: string }[]
function store.lbAlbums()
    return MySQL.query.await(
        ('SELECT id, phone_number, title FROM %s'):format(lbt('photo_albums'))) or {}
end

---Every lb-phone album<->photo link. Read-only.
---@return { album_id: any, photo_id: any }[]
function store.lbAlbumPhotos()
    return MySQL.query.await(
        ('SELECT album_id, photo_id FROM %s'):format(lbt('photo_album_photos'))) or {}
end

---Every lb-phone note, timestamp pre-formatted as an ISO string. Read-only.
---@return { id: any, phone_number: string, title: string|nil, content: string|nil, created_iso: string }[]
function store.lbNotes()
    return MySQL.query.await(([[
        SELECT id, phone_number, title, content,
               DATE_FORMAT(timestamp, '%%Y-%%m-%%dT%%H:%%i:%%s.000Z') AS created_iso
        FROM %s
    ]]):format(lbt('notes'))) or {}
end

---Runs a chunked multi-row INSERT IGNORE. `prefixSql` ends at the word VALUES; one placeholder
---group is appended per row, nil columns emit a literal NULL, and an empty batch is a no-op.
---`suffixSql` is appended after the groups, for an ON DUPLICATE KEY UPDATE tail.
---@param prefixSql string 'INSERT IGNORE INTO ... (cols) VALUES'
---@param cols integer columns per row
---@param rows any[][] one parameter array per row
---@param suffixSql string|nil trailing clause appended after the value groups
local function insertMulti(prefixSql, cols, rows, suffixSql)
    if type(rows) ~= 'table' or #rows == 0 then return end
    local total = #rows
    for i = 1, total, 300 do
        local last = math.min(i + 299, total)
        local groups, params, k = {}, {}, 0
        for j = i, last do
            local r = rows[j]
            local cells = {}
            for c = 1, cols do
                local v = r[c]
                if v == nil then
                    cells[c] = 'NULL'
                else
                    k = k + 1
                    params[k] = v
                    cells[c] = '?'
                end
            end
            groups[#groups + 1] = '(' .. table.concat(cells, ',') .. ')'
        end
        local sql = prefixSql .. ' ' .. table.concat(groups, ',')
        if suffixSql then sql = sql .. ' ' .. suffixSql end
        MySQL.query.await(sql, params)
    end
end

---@type fun(prefixSql: string, cols: integer, rows: any[][], suffixSql?: string) Public alias for porters.
store.insertMulti = insertMulti

---Adopts a player's lb-phone number (and lock passcode) as their sd-phone number. Returns 'set'
---when it wrote, 'skip' when already onboarded, 'conflict' when the number belongs to someone else.
---@param cid string citizenid
---@param number string bare digits
---@param pin string|nil 4-6 digit lock code, or nil
---@param dryRun boolean
---@return 'set'|'skip'|'conflict'
function store.adoptNumber(cid, number, pin, dryRun)
    if not cid or cid == '' or number == '' then return 'skip' end

    local existing = settings.getPhoneNumber(cid)
    if existing and existing ~= '' then return 'skip' end

    local owner = settings.getCitizenByNumber(number)
    if owner and owner ~= cid then return 'conflict' end

    if dryRun then return 'set' end

    MySQL.update.await([[
        INSERT INTO phone_settings (citizenid, phone_number, passcode) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE
            phone_number = IF(phone_number IS NULL OR phone_number = '', VALUES(phone_number), phone_number),
            passcode     = IF(passcode IS NULL OR passcode = '', VALUES(passcode), passcode)
    ]], { cid, number, pin })
    return 'set'
end

---The set of `citizenid|phone` keys already present in phone_contacts. Read-only.
---@return table<string, boolean>
function store.existingContactKeys()
    local rows = MySQL.query.await('SELECT citizenid, phone FROM phone_contacts') or {}
    local set = {}
    for _, r in ipairs(rows) do
        set[('%s|%s'):format(r.citizenid, (tostring(r.phone or ''):gsub('%D', '')))] = true
    end
    return set
end

---Insert a batch of contacts. rows: { id, citizenid, name, phone, email, address, color, avatar, favorite }.
---@param rows any[][]
function store.insertContacts(rows)
    insertMulti('INSERT IGNORE INTO phone_contacts (id, citizenid, name, phone, email, address, color, avatar, favorite) VALUES', 9, rows)
end

---Insert a batch of blocked numbers. rows: { citizenid, number }.
---@param rows any[][]
function store.insertBlocked(rows)
    insertMulti('INSERT IGNORE INTO phone_blocked (citizenid, number) VALUES', 2, rows)
end

---Insert a batch of call-log rows. rows: { id, citizenid, number, name, direction, duration, seen, called_at }.
---@param rows any[][]
function store.insertCalls(rows)
    insertMulti('INSERT IGNORE INTO phone_calls (id, citizenid, `number`, name, direction, duration, seen, called_at) VALUES', 8, rows)
end

---Insert a batch of group threads. rows: { id, name, owner_cid, created_at }.
---@param rows any[][]
function store.insertGroups(rows)
    insertMulti('INSERT IGNORE INTO phone_message_groups (id, name, owner_cid, created_at) VALUES', 4, rows)
end

---Insert a batch of group members. rows: { group_id, citizenid, number, name }.
---@param rows any[][]
function store.insertGroupMembers(rows)
    insertMulti('INSERT IGNORE INTO phone_message_group_members (group_id, citizenid, number, name) VALUES', 4, rows)
end

---Insert a batch of message mailbox copies. rows:
---{ id, mid, citizenid, conversation, sender, direction, kind, body, meta, is_read, withheld, created_at }.
---@param rows any[][]
function store.insertMessages(rows)
    insertMulti('INSERT IGNORE INTO phone_messages (id, mid, citizenid, conversation, sender, direction, kind, body, meta, is_read, withheld, created_at) VALUES', 12, rows)
end

---Insert a batch of photos. rows: { id, citizenid, url, favorite, created_at }.
---@param rows any[][]
function store.insertPhotos(rows)
    insertMulti('INSERT IGNORE INTO phone_photos (id, citizenid, url, favorite, created_at) VALUES', 5, rows)
end

---Insert a batch of albums. rows: { id, citizenid, name }.
---@param rows any[][]
function store.insertAlbums(rows)
    insertMulti('INSERT IGNORE INTO phone_photo_albums (id, citizenid, name) VALUES', 3, rows)
end

---Insert a batch of album<->photo links. rows: { album_id, photo_id }.
---@param rows any[][]
function store.insertAlbumItems(rows)
    insertMulti('INSERT IGNORE INTO phone_photo_album_items (album_id, photo_id) VALUES', 2, rows)
end

---Insert a batch of notes. rows: { citizenid, id, body, sketches, images, created_at, updated_at }.
---@param rows any[][]
function store.insertNotes(rows)
    insertMulti('INSERT IGNORE INTO phone_notes (citizenid, id, body, sketches, images, created_at, updated_at) VALUES', 7, rows)
end

---Every lb-phone phone that carries a settings blob. Read-only.
---@return { phone_number: string, settings: string }[]
function store.lbPhoneSettings()
    return MySQL.query.await(
        ('SELECT phone_number, settings FROM %s WHERE settings IS NOT NULL'):format(lbt('phones'))) or {}
end

---Fill-only settings merge. rows: { citizenid, wallpaper, blur_lock, blur_home, theme, brightness,
---phone_scale, hour24, ringtone, notification_tone, ringtone_volume, call_volume }.
---@param rows any[][]
function store.fillSettings(rows)
    insertMulti([[
        INSERT INTO phone_settings
            (citizenid, wallpaper, blur_lock, blur_home, theme, brightness, phone_scale, hour24,
             ringtone, notification_tone, ringtone_volume, call_volume)
        VALUES
    ]], 12, rows, [[
        ON DUPLICATE KEY UPDATE
            wallpaper         = IF(wallpaper IS NULL, VALUES(wallpaper), wallpaper),
            blur_lock         = IF(blur_lock IS NULL, VALUES(blur_lock), blur_lock),
            blur_home         = IF(blur_home IS NULL, VALUES(blur_home), blur_home),
            theme             = IF(theme IS NULL, VALUES(theme), theme),
            brightness        = IF(brightness IS NULL, VALUES(brightness), brightness),
            phone_scale       = IF(phone_scale IS NULL, VALUES(phone_scale), phone_scale),
            hour24            = IF(hour24 IS NULL, VALUES(hour24), hour24),
            ringtone          = IF(ringtone IS NULL, VALUES(ringtone), ringtone),
            notification_tone = IF(notification_tone IS NULL, VALUES(notification_tone), notification_tone),
            ringtone_volume   = IF(ringtone_volume IS NULL, VALUES(ringtone_volume), ringtone_volume),
            call_volume       = IF(call_volume IS NULL, VALUES(call_volume), call_volume)
    ]])
end

---@return table[]
function store.lbWallet()
    return MySQL.query.await(([[
        SELECT w.id, w.phone_number, w.amount, w.company, UNIX_TIMESTAMP(w.`timestamp`) AS ts
        FROM %s w JOIN `%s` o ON o.number = w.phone_number
    ]]):format(lbt('wallet_transactions'), OWNED)) or {}
end

---@param rows any[][] { citizenid, label, amount, category, created_at, src_id }
function store.insertBankTx(rows)
    insertMulti('INSERT IGNORE INTO phone_bank_transactions (citizenid, label, amount, category, created_at, src_id) VALUES', 6, rows)
end

---@return { message_id: any, phone_number: string, reaction: string }[]
function store.lbReactions()
    return MySQL.query.await(([[
        SELECT r.message_id, r.phone_number, r.reaction
        FROM %s r JOIN `%s` o ON o.number = r.phone_number
    ]]):format(lbt('message_reactions'), OWNED)) or {}
end

---Which of these mids exist in phone_messages, queried in chunks. A reaction whose message was not
---migrated can never render, so the porter drops it rather than importing junk.
---@param mids string[]
---@return table<string, boolean>
function store.existingMids(mids)
    local set = {}
    for i = 1, #mids, 500 do
        local last = math.min(i + 499, #mids)
        local holes, params = {}, {}
        for j = i, last do
            holes[#holes + 1] = '?'
            params[#params + 1] = mids[j]
        end
        local rows = MySQL.query.await(
            ('SELECT DISTINCT mid FROM phone_messages WHERE mid IN (%s)'):format(table.concat(holes, ',')),
            params) or {}
        for _, r in ipairs(rows) do set[r.mid] = true end
    end
    return set
end

---@param rows any[][] { mid, citizenid, emoji, created_at }
function store.insertReactions(rows)
    insertMulti('INSERT IGNORE INTO phone_message_reactions (mid, citizenid, emoji, created_at) VALUES', 4, rows)
end

---@return table[]
function store.lbVoiceMemos()
    return MySQL.query.await(([[
        SELECT id, phone_number, file_name, file_url, file_length,
               UNIX_TIMESTAMP(created_at) AS ts
        FROM %s
    ]]):format(lbt('voice_memos_recordings'))) or {}
end

---@param rows any[][] { citizenid, name, url, duration, created_at, src_id }
function store.insertVoiceMemos(rows)
    insertMulti('INSERT IGNORE INTO phone_voice_memos (citizenid, name, url, duration, created_at, src_id) VALUES', 6, rows)
end

---@return { address: string, password: string }[]
function store.lbMailAccounts()
    return MySQL.query.await(('SELECT address, password FROM %s'):format(lbt('mail_accounts'))) or {}
end

---@return table[]
function store.lbMailMessages()
    return MySQL.query.await(([[
        SELECT id, recipient, sender, subject, content, attachments, actions, `read`,
               UNIX_TIMESTAMP(`timestamp`) AS ts
        FROM %s ORDER BY `timestamp` ASC
    ]]):format(lbt('mail_messages'))) or {}
end

---@return { phone_number: string, app: string, username: string }[] Active app logins only.
function store.lbLoggedIn()
    local tableName = lbt('logged_in_accounts')
    local accounts = {}
    local lastPhone, lastApp, lastUsername = '', '', ''
    local activeWhere = store.tableHasColumn(tableName, 'active') and 'active = 1 AND' or ''

    while true do
        local rows = MySQL.query.await(([[
            SELECT phone_number, app, username
            FROM %s
            WHERE %s (phone_number, app, username) > (?, ?, ?)
            ORDER BY phone_number, app, username
            LIMIT %d
        ]]):format(tableName, activeWhere, READ_CHUNK_SIZE), { lastPhone, lastApp, lastUsername }) or {}

        for _, row in ipairs(rows) do accounts[#accounts + 1] = row end
        if #rows < READ_CHUNK_SIZE then break end

        local last = rows[#rows]
        lastPhone, lastApp, lastUsername = last.phone_number, last.app, last.username
    end

    return accounts
end

---Every legacy Twitter account, paged by its unique username.
---@return table[]
function store.lbTwitterAccounts()
    local tableName = store.lbSource('twitter_accounts')
    if not tableName then return {} end

    local accounts, lastUsername = {}, ''
    while true do
        local rows = MySQL.query.await(([[
            SELECT username, display_name, password, phone_number, bio, profile_image,
                   profile_header, verified, private, UNIX_TIMESTAMP(date_joined) AS ts
            FROM %s
            WHERE username > ?
            ORDER BY username
            LIMIT %d
        ]]):format(tableName, READ_CHUNK_SIZE), { lastUsername }) or {}

        for _, row in ipairs(rows) do accounts[#accounts + 1] = row end
        if #rows < READ_CHUNK_SIZE then break end
        lastUsername = rows[#rows].username
    end

    return accounts
end

---Existing Birdy identities and account handles, used to keep a forced import from claiming a
---live profile or attaching migrated content to the wrong account.
---@return { profiles: table[], handles: table<string, string|true>, sessions: table<string, boolean> }
function store.existingBirdyIdentities()
    local out = { profiles = {}, handles = {}, sessions = {} }
    local profiles = MySQL.query.await([[
        SELECT p.citizenid, p.handle, a.phone, UNIX_TIMESTAMP(p.created_at) AS created_ts
        FROM phone_birdy_profiles p
        LEFT JOIN phone_app_accounts a ON a.app = 'birdy' AND a.username = p.handle
    ]]) or {}
    for _, profile in ipairs(profiles) do
        out.profiles[#out.profiles + 1] = profile
        out.handles[profile.handle] = profile.citizenid
    end

    local accounts = MySQL.query.await("SELECT username FROM phone_app_accounts WHERE app = 'birdy'") or {}
    for _, account in ipairs(accounts) do
        if out.handles[account.username] == nil then out.handles[account.username] = true end
    end

    local sessions = MySQL.query.await([[
        SELECT DISTINCT s.citizenid
        FROM phone_app_sessions s
        JOIN phone_app_accounts a ON a.id = s.account_id
        WHERE s.app = 'birdy' AND a.app = 'birdy'
    ]]) or {}
    for _, session in ipairs(sessions) do out.sessions[session.citizenid] = true end
    return out
end

---@param rows any[][] { email, password_hash, display_name, messages, logged_in_citizens }
function store.insertMailAccounts(rows)
    insertMulti('INSERT IGNORE INTO phone_mail_accounts (email, password_hash, display_name, messages, logged_in_citizens) VALUES', 5, rows)
end

---Usernames already present in Photogram, so a migrated account never overwrites a live one.
---@return table<string, boolean>
function store.existingPhotogramUsernames()
    local rows = MySQL.query.await([[
        SELECT a.username, UNIX_TIMESTAMP(p.created_at) AS created_ts
        FROM phone_app_accounts a
        LEFT JOIN phone_photogram_profiles p ON p.username = a.username
        WHERE a.app = 'photogram'
        UNION
        SELECT p.username, UNIX_TIMESTAMP(p.created_at) AS created_ts
        FROM phone_photogram_profiles p
    ]]) or {}
    local set = {}
    for _, r in ipairs(rows) do set[r.username] = r end
    return set
end

---@return table[]
function store.lbIgAccounts()
    return MySQL.query.await(([[
        SELECT username, display_name, password, bio, profile_image, private, verified,
               phone_number, UNIX_TIMESTAMP(date_joined) AS ts
        FROM %s
    ]]):format(lbt('instagram_accounts'))) or {}
end

---@return table[]
function store.lbIgPosts()
    return MySQL.query.await(([[
        SELECT id, username, media, caption, location, UNIX_TIMESTAMP(`timestamp`) AS ts FROM %s
    ]]):format(lbt('instagram_posts'))) or {}
end

---@return table[]
function store.lbIgComments()
    return MySQL.query.await(([[
        SELECT id, post_id, username, comment, UNIX_TIMESTAMP(`timestamp`) AS ts FROM %s
    ]]):format(lbt('instagram_comments'))) or {}
end

---@return table[]
function store.lbIgLikes()
    return MySQL.query.await(
        ('SELECT id, username, is_comment FROM %s'):format(lbt('instagram_likes'))) or {}
end

---@return table[]
function store.lbIgFollows()
    return MySQL.query.await(
        ('SELECT followed, follower FROM %s'):format(lbt('instagram_follows'))) or {}
end

---@return table[]
function store.lbIgRequests()
    return MySQL.query.await(([[
        SELECT requester, requestee, UNIX_TIMESTAMP(`timestamp`) AS ts FROM %s
    ]]):format(lbt('instagram_follow_requests'))) or {}
end

---@return table[]
function store.lbIgStories()
    return MySQL.query.await(([[
        SELECT id, username, image, UNIX_TIMESTAMP(`timestamp`) AS ts FROM %s
    ]]):format(lbt('instagram_stories'))) or {}
end

---The viewer column is `viewer` here, not `username` as on every other instagram table.
---@return table[]
function store.lbIgStoryViews()
    return MySQL.query.await(([[
        SELECT story_id, viewer AS username, UNIX_TIMESTAMP(`timestamp`) AS ts FROM %s
    ]]):format(lbt('instagram_stories_views'))) or {}
end

---@return table[]
function store.lbIgMessages()
    return MySQL.query.await(([[
        SELECT id, sender, recipient, content, attachments, UNIX_TIMESTAMP(`timestamp`) AS ts FROM %s
    ]]):format(lbt('instagram_messages'))) or {}
end

---@return table[]
function store.lbIgNotifications()
    return MySQL.query.await(([[
        SELECT id, username, `from` AS from_user, `type`, post_id, UNIX_TIMESTAMP(`timestamp`) AS ts
        FROM %s
    ]]):format(lbt('instagram_notifications'))) or {}
end

---@param rows any[][] { username, display_name, bio, avatar, is_private, verified, created_at }
function store.insertPgProfiles(rows)
    insertMulti('INSERT IGNORE INTO phone_photogram_profiles (username, display_name, bio, avatar, is_private, verified, created_at) VALUES', 7, rows)
end

---@param rows any[][] { id, author, images, caption, location, created_at }
function store.insertPgPosts(rows)
    insertMulti('INSERT IGNORE INTO phone_photogram_posts (id, author, images, caption, location, created_at) VALUES', 6, rows)
end

---@param rows any[][] { id, post_id, author, body, gif_url, created_at }
function store.insertPgComments(rows)
    insertMulti('INSERT IGNORE INTO phone_photogram_comments (id, post_id, author, body, gif_url, created_at) VALUES', 6, rows)
end

---@param rows any[][] { post_id, username, created_at }
function store.insertPgLikes(rows)
    insertMulti('INSERT IGNORE INTO phone_photogram_likes (post_id, username, created_at) VALUES', 3, rows)
end

---@param rows any[][] { comment_id, username, created_at }
function store.insertPgCommentLikes(rows)
    insertMulti('INSERT IGNORE INTO phone_photogram_comment_likes (comment_id, username, created_at) VALUES', 3, rows)
end

---@param rows any[][] { follower, target, status, created_at }
function store.insertPgFollows(rows)
    insertMulti('INSERT IGNORE INTO phone_photogram_follows (follower, target, status, created_at) VALUES', 4, rows)
end

---@param rows any[][] { id, author, image, created_at }
function store.insertPgStories(rows)
    insertMulti('INSERT IGNORE INTO phone_photogram_stories (id, author, image, created_at) VALUES', 4, rows)
end

---@param rows any[][] { story_id, username, created_at }
function store.insertPgStoryViews(rows)
    insertMulti('INSERT IGNORE INTO phone_photogram_story_views (story_id, username, created_at) VALUES', 3, rows)
end

---@param rows any[][] { id, from_user, to_user, body, kind, meta, reactions, read_flag, created_at }
function store.insertPgDms(rows)
    insertMulti('INSERT IGNORE INTO phone_photogram_dms (id, from_user, to_user, body, kind, meta, reactions, read_flag, created_at) VALUES', 9, rows)
end

---@param rows any[][] { id, recipient, kind, actor, post_id, seen, created_at }
function store.insertPgNotifications(rows)
    insertMulti('INSERT IGNORE INTO phone_photogram_notifications (id, recipient, kind, actor, post_id, seen, created_at) VALUES', 7, rows)
end

---@type string[] Scratch tables used by the set-based Twitter -> Birdy import.
local BIRDY_STAGES = {
    '_sdphone_migrate_birdy_profiles',
    '_sdphone_migrate_birdy_posts',
}

local function dropBirdyStages()
    for _, tableName in ipairs(BIRDY_STAGES) do
        MySQL.query.await(('DROP TABLE IF EXISTS `%s`'):format(tableName))
    end
end

---Copies the selected legacy Twitter graph into Birdy. Profile selection happens in the porter;
---this function stages that identity map and moves the large content tables with set-based SQL so
---hundreds of thousands of rows never cross the Lua bridge.
---@param profiles any[][] { legacy username, citizenid, final Birdy handle, logged in }
---@param dryRun boolean
---@return table counts
function store.migrateBirdy(profiles, dryRun)
    local out = {
        profiles = 0, accounts = 0, posts = 0, likes = 0, reposts = 0,
        follows = 0, dms = 0, notifications = 0, skipped = 0, orphan = 0,
    }
    local accountsTable = store.lbSource('twitter_accounts')
    if not accountsTable or #profiles == 0 then return out end

    local tweetsTable = store.lbSource('twitter_tweets')
    local likesTable = store.lbSource('twitter_likes')
    local repostsTable = store.lbSource('twitter_retweets')
    local followsTable = store.lbSource('twitter_follows')
    local dmsTable = store.lbSource('twitter_messages')
    local notificationsTable = store.lbSource('twitter_notifications')
    local profileStage, postStage = BIRDY_STAGES[1], BIRDY_STAGES[2]

    dropBirdyStages()
    local ok, result = xpcall(function()
    MySQL.query.await(([=[
        CREATE TABLE `%s` (
            source_username VARCHAR(20) NOT NULL,
            citizenid VARCHAR(64) NOT NULL,
            handle VARCHAR(32) NOT NULL,
            logged_in TINYINT(1) NOT NULL DEFAULT 0,
            PRIMARY KEY (source_username),
            UNIQUE KEY uq_birdy_stage_handle (handle)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]=]):format(profileStage))
    insertMulti(
        ('INSERT IGNORE INTO `%s` (source_username, citizenid, handle, logged_in) VALUES'):format(profileStage),
        4,
        profiles
    )

    MySQL.query.await(([=[
        CREATE TABLE `%s` (
            source_id VARCHAR(50) NOT NULL,
            post_id VARCHAR(16) NOT NULL,
            PRIMARY KEY (source_id),
            UNIQUE KEY uq_birdy_stage_post (post_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]=]):format(postStage))

    if tweetsTable then
        MySQL.query.await(([=[
            INSERT IGNORE INTO `%s` (source_id, post_id)
            SELECT t.id, CONCAT('tw', t.id)
            FROM %s t
            JOIN `%s` author ON author.source_username = t.username
            WHERE t.reply_to IS NULL OR t.reply_to = ''
        ]=]):format(postStage, tweetsTable, profileStage))

        while true do
            local inserted = tonumber(MySQL.update.await(([=[
                INSERT IGNORE INTO `%s` (source_id, post_id)
                SELECT t.id, CONCAT('tw', t.id)
                FROM %s t
                JOIN `%s` author ON author.source_username = t.username
                JOIN `%s` parent ON parent.source_id = t.reply_to
                WHERE t.reply_to IS NOT NULL AND t.reply_to <> ''
            ]=]):format(postStage, tweetsTable, profileStage, postStage))) or 0
            if inserted == 0 then break end
        end
    end

    local function count(sql)
        return tonumber(MySQL.scalar.await(sql)) or 0
    end

    out.profiles = count(('SELECT COUNT(*) FROM `%s`'):format(profileStage))
    out.accounts = out.profiles
    out.skipped = math.max(0, count(('SELECT COUNT(*) FROM %s'):format(accountsTable)) - out.profiles)
    out.posts = count(('SELECT COUNT(*) FROM `%s`'):format(postStage))
    if tweetsTable then
        local selectedTweets = count(([=[
            SELECT COUNT(*) FROM %s t
            JOIN `%s` author ON author.source_username = t.username
        ]=]):format(tweetsTable, profileStage))
        out.orphan = math.max(0, selectedTweets - out.posts)
    end

    if likesTable and tweetsTable then
        out.likes = count(([=[
            SELECT COUNT(*) FROM %s l
            JOIN `%s` actor ON actor.source_username = l.username
            JOIN `%s` post ON post.source_id = l.tweet_id
        ]=]):format(likesTable, profileStage, postStage))
    end
    if repostsTable and tweetsTable then
        out.reposts = count(([=[
            SELECT COUNT(*) FROM %s r
            JOIN `%s` actor ON actor.source_username = r.username
            JOIN `%s` post ON post.source_id = r.tweet_id
        ]=]):format(repostsTable, profileStage, postStage))
    end
    if followsTable then
        out.follows = count(([=[
            SELECT COUNT(*) FROM %s f
            JOIN `%s` follower ON follower.source_username = f.follower
            JOIN `%s` target ON target.source_username = f.followed
            WHERE follower.handle <> target.handle
        ]=]):format(followsTable, profileStage, profileStage))
    end
    if dmsTable then
        out.dms = count(([=[
            SELECT COUNT(*) FROM %s d
            JOIN `%s` sender ON sender.source_username = d.sender
            JOIN `%s` recipient ON recipient.source_username = d.recipient
        ]=]):format(dmsTable, profileStage, profileStage))
    end
    if notificationsTable then
        out.notifications = count(([=[
            SELECT COUNT(*) FROM %s n
            JOIN `%s` recipient ON recipient.source_username = n.username
            JOIN `%s` actor ON actor.source_username = n.`from`
            LEFT JOIN `%s` post ON post.source_id = n.tweet_id
            WHERE n.type = 'follow' OR post.source_id IS NOT NULL
        ]=]):format(notificationsTable, profileStage, profileStage, postStage))
    end

    if not dryRun then
        MySQL.query.await(([=[
            INSERT IGNORE INTO phone_birdy_profiles
                (citizenid, handle, display_name, password, bio, verified, logged_in,
                 join_label, protected, created_at, avatar, banner)
            SELECT m.citizenid, m.handle,
                   COALESCE(NULLIF(LEFT(a.display_name, 32), ''), m.handle), LEFT(a.password, 64),
                   LEFT(COALESCE(a.bio, ''), 160), IF(a.verified = 1, 1, 0), m.logged_in,
                   DATE_FORMAT(a.date_joined, '%%M %%Y'), IF(a.private = 1, 1, 0),
                   a.date_joined, LEFT(a.profile_image, 512), LEFT(a.profile_header, 512)
            FROM `%s` m
            JOIN %s a ON a.username = m.source_username
        ]=]):format(profileStage, accountsTable))

        MySQL.query.await(([=[
            INSERT IGNORE INTO phone_app_accounts
                (app, username, display_name, password_hash, phone, created_at)
            SELECT 'birdy', m.handle,
                   COALESCE(NULLIF(LEFT(a.display_name, 50), ''), m.handle), LEFT(a.password, 64),
                   REGEXP_REPLACE(a.phone_number, '[^0-9]', ''), a.date_joined
            FROM `%s` m
            JOIN %s a ON a.username = m.source_username
        ]=]):format(profileStage, accountsTable))

        if tweetsTable then
            MySQL.query.await(([=[
                INSERT IGNORE INTO phone_birdy_posts
                    (id, author, body, parent_id, images, views, created_at)
                SELECT staged.post_id, author.handle, LEFT(COALESCE(t.content, ''), 280),
                       parent.post_id,
                       CASE WHEN JSON_VALID(t.attachments) = 1 AND JSON_LENGTH(t.attachments) > 0
                            THEN t.attachments ELSE NULL END,
                       0, t.`timestamp`
                FROM `%s` staged
                JOIN %s t ON t.id = staged.source_id
                JOIN `%s` author ON author.source_username = t.username
                LEFT JOIN `%s` parent ON parent.source_id = t.reply_to
                JOIN phone_birdy_profiles profile
                  ON profile.citizenid = author.citizenid AND profile.handle = author.handle
            ]=]):format(postStage, tweetsTable, profileStage, postStage))
        end

        if likesTable then
            MySQL.query.await(([=[
                INSERT IGNORE INTO phone_birdy_likes (post_id, handle, created_at)
                SELECT post.post_id, actor.handle, l.`timestamp`
                FROM %s l
                JOIN `%s` actor ON actor.source_username = l.username
                JOIN `%s` post ON post.source_id = l.tweet_id
                JOIN phone_birdy_posts p ON p.id = post.post_id
            ]=]):format(likesTable, profileStage, postStage))
        end

        if repostsTable then
            MySQL.query.await(([=[
                INSERT IGNORE INTO phone_birdy_reposts (post_id, handle, created_at)
                SELECT post.post_id, actor.handle, r.`timestamp`
                FROM %s r
                JOIN `%s` actor ON actor.source_username = r.username
                JOIN `%s` post ON post.source_id = r.tweet_id
                JOIN phone_birdy_posts p ON p.id = post.post_id
            ]=]):format(repostsTable, profileStage, postStage))
        end

        if followsTable then
            MySQL.query.await(([=[
                INSERT IGNORE INTO phone_birdy_follows (follower, target, created_at)
                SELECT follower.handle, target.handle,
                       GREATEST(followerAccount.date_joined, targetAccount.date_joined)
                FROM %s f
                JOIN `%s` follower ON follower.source_username = f.follower
                JOIN `%s` target ON target.source_username = f.followed
                JOIN %s followerAccount ON followerAccount.username = f.follower
                JOIN %s targetAccount ON targetAccount.username = f.followed
                WHERE follower.handle <> target.handle
            ]=]):format(followsTable, profileStage, profileStage, accountsTable, accountsTable))
        end

        if dmsTable then
            MySQL.query.await(([=[
                INSERT IGNORE INTO phone_birdy_dms
                    (id, from_handle, to_handle, body, kind, meta, reactions, read_flag, created_at)
                SELECT CONCAT('tw', d.id), sender.handle, recipient.handle,
                       COALESCE(d.content, ''),
                       CASE WHEN JSON_VALID(d.attachments) = 1 AND JSON_LENGTH(d.attachments) > 0
                            THEN 'image' ELSE 'text' END,
                       CASE WHEN JSON_VALID(d.attachments) = 1 AND JSON_LENGTH(d.attachments) > 0
                            THEN JSON_OBJECT(
                                'gifUrl', JSON_UNQUOTE(JSON_EXTRACT(d.attachments, '$[0]')),
                                'attachments', JSON_EXTRACT(d.attachments, '$')
                            ) ELSE NULL END,
                       NULL, 1, d.`timestamp`
                FROM %s d
                JOIN `%s` sender ON sender.source_username = d.sender
                JOIN `%s` recipient ON recipient.source_username = d.recipient
            ]=]):format(dmsTable, profileStage, profileStage))
        end

        if notificationsTable then
            MySQL.query.await(([=[
                INSERT IGNORE INTO phone_birdy_notifications
                    (id, recipient, kind, actor, post_id, seen, created_at)
                SELECT CONCAT('tw', n.id), recipient.handle,
                       CASE n.type WHEN 'tweet' THEN 'post' WHEN 'retweet' THEN 'repost'
                            ELSE LEFT(n.type, 16) END,
                       actor.handle, post.post_id, 1, n.`timestamp`
                FROM %s n
                JOIN `%s` recipient ON recipient.source_username = n.username
                JOIN `%s` actor ON actor.source_username = n.`from`
                LEFT JOIN `%s` post ON post.source_id = n.tweet_id
                WHERE n.type = 'follow' OR post.source_id IS NOT NULL
            ]=]):format(notificationsTable, profileStage, profileStage, postStage))
        end
    end

    return out
    end, debug.traceback)
    dropBirdyStages()
    if not ok then error(result, 0) end
    return result
end

---Accounts-engine rows for migrated app accounts.
---@param rows any[][] { app, username, display_name, password_hash }
function store.insertPgAccounts(rows)
    insertMulti('INSERT IGNORE INTO phone_app_accounts (app, username, display_name, password_hash) VALUES', 4, rows)
end

---@type string Alphabet for generated passwords; no look-alike characters, so a player can read one
---off the Passwords app and type it without ambiguity.
local PW_CHARS = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'

---A fresh readable password.
---@return string
local function newPassword()
    local out = {}
    for i = 1, 12 do
        local n = math.random(1, #PW_CHARS)
        out[i] = PW_CHARS:sub(n, n)
    end
    return table.concat(out)
end

---@type boolean True after migration-owned credential columns have been checked this resource run.
local loginColumnWidthsReady = false

---Guarantees every destination touched by the login grant can hold current scrypt/encrypted data.
---Their normal schema bootstraps run in separate threads and may not have finished widening an old
---install when the migration's table-existence gate opens.
local function ensureLoginColumnWidths()
    if loginColumnWidthsReady then return end
    util.ensureColumnWidth(
        'phone_app_accounts',
        'password_hash',
        'password_hash VARCHAR(255) NOT NULL',
        255
    )
    util.ensureColumnWidth(
        'phone_passwords',
        'password',
        'password VARCHAR(255) NOT NULL',
        255
    )
    util.ensureColumnWidth(
        'phone_birdy_profiles',
        'password',
        "password VARCHAR(255) NOT NULL DEFAULT ''",
        255
    )
    loginColumnWidthsReady = true
end

---True when a target account already holds one of the engine's own password formats. Without a
---verified vault value, a forced migration must preserve it rather than manufacture a replacement.
---@param value any stored password hash
---@return boolean current
local function isEnginePasswordHash(value)
    if type(value) ~= 'string' then return false end
    if value:sub(1, 7) == 'scrypt$' then return true end
    return #value == 24 and value:match('^[0-9a-fA-F]+$') ~= nil
end

---Gives migrated accounts a login their owner can actually use.
---
---lb-phone hashes passwords with bcrypt, which sd-phone cannot verify and cannot reverse, so a
---migrated account is unreachable the moment its owner signs out. Each account with a resolved
---owner therefore gets a readable password stored as the engine hash on the account and written to
---the owner's vault. A rerun reuses that saved credential instead of silently rotating it.
---
---Accounts with no resolved owner keep whatever hash they came with. Nobody can sign into them, but
---there is also no one to hand a password to.
---@param entries { app: string, username: string, cid: string, email: string|nil }[]
---@return integer granted, integer deferred
function store.grantMigratedLogins(entries)
    if #entries == 0 then return 0, 0 end
    local accounts = require 'server.accounts.store'

    local targets, appNames, seenApps = {}, {}, {}
    for i = 1, #entries do
        local entry = entries[i]
        targets[entry.app .. '\0' .. entry.username] = true
        if not seenApps[entry.app] then
            seenApps[entry.app] = true
            appNames[#appNames + 1] = entry.app
        end
    end
    table.sort(appNames)

    ensureLoginColumnWidths()

    -- Reuse a saved credential for an account whenever one exists. Read the vault in bounded
    -- primary-key pages: a full server can hold tens of thousands of rows, and bridging all of
    -- them to Lua in one result both trips oxmysql's warning and delays the scheduler heartbeat.
    local savedByAccount, unreadable = {}, {}
    local appPlaceholders = {}
    for i = 1, #appNames do appPlaceholders[i] = '?' end

    -- Record current engine hashes separately from the vault. A player can delete a saved Passwords
    -- entry without changing their actual account password; a forced migration must not treat that
    -- missing convenience copy as permission to rotate a working account.
    local existingHashes = {}
    local lastAccountId = 0
    while true do
        local params = { lastAccountId }
        for i = 1, #appNames do params[#params + 1] = appNames[i] end
        local rows = MySQL.query.await(([=[
            SELECT id, app, username, password_hash
            FROM phone_app_accounts
            WHERE id > ? AND app IN (%s)
            ORDER BY id ASC
            LIMIT %d
        ]=]):format(table.concat(appPlaceholders, ','), READ_CHUNK_SIZE), params) or {}

        for i = 1, #rows do
            local row = rows[i]
            local key = row.app .. '\0' .. row.username
            if targets[key] then existingHashes[key] = row.password_hash end
        end

        if #rows == 0 then break end
        lastAccountId = rows[#rows].id
        Wait(0)
        if #rows < READ_CHUNK_SIZE then break end
    end

    local lastVaultId = 0
    while true do
        local params = { lastVaultId }
        for i = 1, #appNames do params[#params + 1] = appNames[i] end
        local rows = MySQL.query.await(([=[
            SELECT p.id, p.app, p.username, p.password, a.password_hash
            FROM phone_passwords p
            JOIN phone_app_accounts a ON a.app = p.app AND a.username = p.username
            WHERE p.id > ? AND p.app IN (%s)
            ORDER BY p.id ASC
            LIMIT %d
        ]=]):format(table.concat(appPlaceholders, ','), READ_CHUNK_SIZE), params) or {}

        for i = 1, #rows do
            local row = rows[i]
            local key = row.app .. '\0' .. row.username
            if targets[key] then
                local plain = accounts.openImportedVaultSecret(row.password)
                if plain then
                    local saved = savedByAccount[key]
                    if not saved then
                        saved = { hash = row.password_hash, candidates = {}, seen = {} }
                        savedByAccount[key] = saved
                    end
                    if not saved.seen[plain] then
                        saved.seen[plain] = true
                        saved.candidates[#saved.candidates + 1] = plain
                    end
                elseif type(row.password) == 'string' and row.password:sub(1, 3) == 'v1$' then
                    unreadable[key] = true
                end
            end
        end

        if #rows == 0 then break end
        lastVaultId = rows[#rows].id
        Wait(0)
        if #rows < READ_CHUNK_SIZE then break end
    end

    -- Verify saved credentials instead of hashing and comparing them: salted scrypt hashes are
    -- deliberately different on every invocation. Each expensive scrypt check yields afterward.
    -- Current engine accounts with no verified value stay untouched; foreign source hashes still
    -- receive a fresh usable credential. Unreadable encryption is deferred for a later retry.
    local credentials, blocked, deferred = {}, {}, {}
    for key, saved in pairs(savedByAccount) do
        local selected
        local isScrypt = type(saved.hash) == 'string' and saved.hash:sub(1, 7) == 'scrypt$'
        if accounts.canVerifyImportedPasswordHash(saved.hash) then
            for i = 1, #saved.candidates do
                local candidate = saved.candidates[i]
                local verified = accounts.verifyPassword(candidate, saved.hash)
                if isScrypt then Wait(0) end
                if verified then
                    selected = candidate
                    break
                end
            end
        else
            blocked[key] = true
            deferred[key] = true
        end
        if selected then
            credentials[key] = { plain = selected, hash = saved.hash }
        elseif not deferred[key] and isEnginePasswordHash(saved.hash) then
            blocked[key] = true
        end
    end
    for key in pairs(unreadable) do
        if not credentials[key] then
            blocked[key] = true
            deferred[key] = true
        end
    end
    for key, hash in pairs(existingHashes) do
        if not credentials[key] and not blocked[key] and isEnginePasswordHash(hash) then
            blocked[key] = true
        end
    end

    local blockedCount, deferredCount = 0, 0
    for key in pairs(blocked) do
        if targets[key] then blockedCount = blockedCount + 1 end
    end
    for key in pairs(deferred) do
        if targets[key] then deferredCount = deferredCount + 1 end
    end
    if blockedCount > 0 then
        print(('^3[sd-phone:migrate]^0 left %d existing login%s unchanged because no verified saved password was available.')
            :format(blockedCount, blockedCount == 1 and '' or 's'))
    end

    -- Staged and joined rather than two queries per account: row-by-row took 47s on a full dump.
    local tmp = '_sdphone_migrate_logins'
    MySQL.query.await(('DROP TABLE IF EXISTS `%s`'):format(tmp))
    MySQL.query.await(([[
        CREATE TABLE `%s` (
            app VARCHAR(24) NOT NULL, username VARCHAR(64) NOT NULL, citizenid VARCHAR(64) NOT NULL,
            stored VARCHAR(255) NOT NULL, hash VARCHAR(255) NOT NULL, email VARCHAR(120) NULL,
            PRIMARY KEY (app, username, citizenid)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]]):format(tmp))

    for i = 1, #entries, 300 do
        local last = math.min(i + 299, #entries)
        local groups, params = {}, {}
        for j = i, last do
            local entry = entries[j]
            local key = entry.app .. '\0' .. entry.username
            local credential = credentials[key]
            if not credential and not blocked[key] then
                local plain = newPassword()
                credential = {
                    plain = plain,
                    hash = accounts.hashImportedPassword(plain),
                }
                credentials[key] = credential
            end
            if credential then
                params[#params + 1] = entry.app
                params[#params + 1] = entry.username
                params[#params + 1] = entry.cid
                params[#params + 1] = accounts.sealImportedVaultSecret(credential.plain)
                params[#params + 1] = credential.hash
                if entry.email then
                    params[#params + 1] = entry.email
                    groups[#groups + 1] = '(?,?,?,?,?,?)'
                else
                    groups[#groups + 1] = '(?,?,?,?,?,NULL)'
                end
            end
        end
        if #groups > 0 then
            MySQL.query.await(([[
                INSERT IGNORE INTO `%s` (app, username, citizenid, stored, hash, email) VALUES %s
            ]]):format(tmp, table.concat(groups, ',')), params)
        end
    end

    -- Only accounts that exist get a password, and only those get a vault entry, so the vault never
    -- lists a login that cannot be used.
    local granted = tonumber(MySQL.scalar.await(([[
        SELECT COUNT(DISTINCT t.app, t.username) FROM `%s` t
        JOIN phone_app_accounts a ON a.app = t.app AND a.username = t.username
    ]]):format(tmp))) or 0

    MySQL.update.await(([[
        UPDATE phone_app_accounts a JOIN `%s` t ON t.app = a.app AND t.username = a.username
        SET a.password_hash = t.hash
    ]]):format(tmp))

    -- Birdy keeps a compatibility password hash on the profile as well as in the shared accounts
    -- engine. Keep both copies aligned so any later legacy-account reconciliation cannot revive the
    -- unusable lb-phone bcrypt value.
    MySQL.update.await(([[
        UPDATE phone_birdy_profiles p JOIN `%s` t
          ON t.app = 'birdy' AND t.username = p.handle
        SET p.password = t.hash
    ]]):format(tmp))

    MySQL.query.await(([[
        INSERT INTO phone_passwords (citizenid, app, username, password, email)
        SELECT t.citizenid, t.app, t.username, t.stored, t.email FROM `%s` t
        JOIN phone_app_accounts a ON a.app = t.app AND a.username = t.username
        ON DUPLICATE KEY UPDATE password = VALUES(password), email = VALUES(email)
    ]]):format(tmp))

    MySQL.query.await(('DROP TABLE IF EXISTS `%s`'):format(tmp))
    return granted, deferredCount
end

---Sessions for migrated app accounts. `linked` counts rows whose account exists and now has a
---session; `inserted` counts only the new ones. They differ on a re-run, where every session is
---already present and INSERT IGNORE affects no rows: that is success, not failure, so callers must
---judge on `linked`.
---@param rows any[][] { app, citizenid, username, active }
---@return integer linked, integer inserted
function store.insertPgSessions(rows)
    if #rows == 0 then return 0, 0 end

    -- Set-based, not row-by-row: the previous loop ran two queries per session and took 23s on a
    -- full dump. Staging the pairs and joining once turns that into a handful of statements.
    local tmp = '_sdphone_migrate_sessions'
    MySQL.query.await(('DROP TABLE IF EXISTS `%s`'):format(tmp))
    MySQL.query.await(([[
        CREATE TABLE `%s` (
            app VARCHAR(24) NOT NULL, citizenid VARCHAR(64) NOT NULL, username VARCHAR(64) NOT NULL,
            active TINYINT(1) NOT NULL DEFAULT 0,
            PRIMARY KEY (app, citizenid, username)
        ) ENGINE=MEMORY DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]]):format(tmp))

    for i = 1, #rows, 300 do
        local last = math.min(i + 299, #rows)
        local groups, params = {}, {}
        for j = i, last do
            groups[#groups + 1] = '(?,?,?,?)'
            params[#params + 1] = rows[j][1]
            params[#params + 1] = rows[j][2]
            params[#params + 1] = rows[j][3]
            params[#params + 1] = rows[j][4] or 0
        end
        MySQL.query.await(
            ('INSERT IGNORE INTO `%s` (app, citizenid, username, active) VALUES %s'):format(tmp, table.concat(groups, ',')),
            params)
    end

    local linked = tonumber(MySQL.scalar.await(([[
        SELECT COUNT(*) FROM `%s` t
        JOIN phone_app_accounts a ON a.app = t.app AND a.username = t.username
    ]]):format(tmp))) or 0

    local inserted = tonumber(MySQL.update.await(([[
        INSERT IGNORE INTO phone_app_sessions (app, citizenid, account_id, last_used)
        SELECT t.app, t.citizenid, a.id,
               IF(t.active = 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP - INTERVAL 1 SECOND)
        FROM `%s` t
        JOIN phone_app_accounts a ON a.app = t.app AND a.username = t.username
    ]]):format(tmp))) or 0

    MySQL.update.await(([=[
        UPDATE phone_app_sessions s
        JOIN `%s` t ON t.app = s.app AND t.citizenid = s.citizenid AND t.active = 1
        JOIN phone_app_accounts a ON a.id = s.account_id AND a.app = t.app AND a.username = t.username
        SET s.last_used = CURRENT_TIMESTAMP
    ]=]):format(tmp))

    MySQL.query.await(('DROP TABLE IF EXISTS `%s`'):format(tmp))
    return linked, inserted
end

---@type table<string, string> Names sd-phone and lb-phone both use, mapped to a column only the
---sd-phone shape has. Before the schema bootstrap has run, the bare name still holds lb-phone's
---table, and dropping it would destroy the importer's source. Mirrors util.rescueLegacyTable.
local SHARED_NAMES = {
    phone_photos            = 'citizenid',
    phone_notes             = 'citizenid',
    phone_photo_albums      = 'citizenid',
    phone_messages          = 'citizenid',
    phone_documents         = 'citizenid',
    phone_document_folders  = 'citizenid',
    phone_mail_accounts     = 'password_hash',
    phone_message_reactions = 'mid',
}

---Drops the tables sd-phone owns, leaving lb-phone's alone so a re-import still has a source.
---
---A name both systems use is only dropped once it carries sd-phone's marker column: on a database
---that has not booted sd-phone yet, that name still belongs to lb-phone.
---@param owned string[] table names from server.admin.tables
---@return integer dropped, integer skipped
function store.dropOwnedTables(owned)
    local dropped, skipped = 0, 0
    MySQL.query.await('SET FOREIGN_KEY_CHECKS = 0')
    for _, tbl in ipairs(owned) do
        if store.tableExists(tbl) then
            local marker = SHARED_NAMES[tbl]
            if marker and not store.tableHasColumn(tbl, marker) then
                skipped = skipped + 1
            elseif pcall(MySQL.query.await, ('DROP TABLE IF EXISTS `%s`'):format(tbl)) then
                dropped = dropped + 1
            else
                skipped = skipped + 1
            end
        end
    end
    MySQL.query.await('SET FOREIGN_KEY_CHECKS = 1')
    return dropped, skipped
end

---Publishes the resolved numbers for the readers to join against.
---
---Without this each porter selected an entire lb table and dropped 99% of it in Lua: 1.3M call rows
---to keep 11k, over a bridge that serialises every row. Filtering in SQL keeps the reads
---proportional to what is actually imported, and lets MySQL use its indexes.
---@param numbers string[] bare-digit phone numbers
function store.publishOwnedNumbers(numbers)
    MySQL.query.await(('DROP TABLE IF EXISTS `%s`'):format(OWNED))
    MySQL.query.await(([[
        CREATE TABLE `%s` (
            number VARCHAR(15) NOT NULL,
            PRIMARY KEY (number)
        ) ENGINE=MEMORY DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]]):format(OWNED))
    if #numbers == 0 then return end

    for i = 1, #numbers, 500 do
        local last = math.min(i + 499, #numbers)
        local holes, params = {}, {}
        for j = i, last do
            holes[#holes + 1] = '(?)'
            params[#params + 1] = numbers[j]
        end
        MySQL.query.await(
            ('INSERT IGNORE INTO `%s` (number) VALUES %s'):format(OWNED, table.concat(holes, ',')),
            params)
    end
end

---The owned-numbers table name, for readers that join against it.
---@return string
function store.ownedTable() return OWNED end

---Drops the owned-numbers table once the import is done.
function store.clearOwnedNumbers()
    MySQL.query.await(('DROP TABLE IF EXISTS `%s`'):format(OWNED))
end

---Rows waiting in a set of lb-phone source tables. Absent tables count zero, so a partial lb
---database is not an error.
---@param names string[] lb table suffixes, e.g. { 'phone_contacts' }
---@return integer rows
function store.lbRowCount(names)
    local total = 0
    for _, name in ipairs(names) do
        local tbl = store.lbSource(name)
        if tbl then
            total = total + (tonumber(MySQL.scalar.await(('SELECT COUNT(*) FROM `%s`'):format(tbl))) or 0)
        end
    end
    return total
end

---Decodes a JSON column value; accepts strings or already-decoded tables and returns {} for
---anything absent or invalid.
---@param value any
---@return table
function store.decodeJson(value)
    if value == nil then return {} end
    if type(value) == 'table' then return value end
    if type(value) == 'string' then
        local ok, decoded = pcall(json.decode, value)
        if ok and type(decoded) == 'table' then return decoded end
    end
    return {}
end

---Encodes a table for a JSON column; empty or absent tables map to nil.
---@param tbl table|nil
---@return string|nil
function store.encodeJson(tbl)
    if not tbl or next(tbl) == nil then return nil end
    return json.encode(tbl)
end

return store
