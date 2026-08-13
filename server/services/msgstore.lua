---@type table Company inbox store module; the table returned at end of file.
local store = {}

---Creates the company-inbox tables: one flat message table keyed by (job, citizen_number) and a
---per-(viewer, thread) read-state table.
function store.ensureSchema()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_service_messages (
            id             VARCHAR(64)  NOT NULL,
            job            VARCHAR(64)  NOT NULL,
            citizen_number VARCHAR(32)  NOT NULL,
            citizen_name   VARCHAR(128) DEFAULT NULL,
            sender         VARCHAR(8)   NOT NULL,          -- 'citizen' | 'staff'
            staff_cid      VARCHAR(64)  DEFAULT NULL,
            staff_name     VARCHAR(128) DEFAULT NULL,
            body           TEXT         NOT NULL,
            created_at     INT          NOT NULL,
            PRIMARY KEY (id),
            INDEX idx_job (job, citizen_number, created_at),
            INDEX idx_cit (citizen_number, created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    MySQL.query.await([[
        ALTER TABLE phone_service_messages
            ADD COLUMN IF NOT EXISTS kind VARCHAR(16) NOT NULL DEFAULT 'text',
            ADD COLUMN IF NOT EXISTS meta TEXT NULL
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_service_msg_reads (
            viewer         VARCHAR(64) NOT NULL,
            job            VARCHAR(64) NOT NULL,
            citizen_number VARCHAR(32) NOT NULL,
            last_read      INT         NOT NULL DEFAULT 0,
            PRIMARY KEY (viewer, job, citizen_number)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

local util = require 'server.util'
local function newId() return util.newId(7) end
store.newId = newId

local DEFAULT_THREAD_LIMIT = 100
local MAX_THREAD_LIMIT = 100
local DEFAULT_INBOX_LIMIT = 50
local MAX_INBOX_LIMIT = 50
local MAX_BATCH_KEYS = 50

---@param value any
---@param fallback integer
---@param maximum integer
---@return integer
local function boundedLimit(value, fallback, maximum)
    local numeric = tonumber(value)
    if not util.finite(numeric) then return fallback end
    local limit = math.floor(numeric)
    if limit < 1 then return fallback end
    return math.min(limit, maximum)
end

---Appends one message to a (job, citizen) thread.
---@param rec { id: string, job: string, citizenNumber: string, citizenName?: string, sender: string, staffCid?: string, staffName?: string, body: string, kind?: string, meta?: string, createdAt: number }
function store.insert(rec)
    MySQL.insert.await([[
        INSERT INTO phone_service_messages
            (id, job, citizen_number, citizen_name, sender, staff_cid, staff_name, body, kind, meta, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        rec.id, rec.job, rec.citizenNumber, rec.citizenName,
        rec.sender, rec.staffCid, rec.staffName, rec.body,
        rec.kind or 'text', rec.meta, rec.createdAt,
    })
end

---The newest rows in a (job, citizen) thread, returned oldest first for display. Read-only.
---@param job string
---@param citizenNumber string
---@param limit? number row cap (default 100)
---@return table[]
function store.threadMessages(job, citizenNumber, limit)
    local rowLimit = boundedLimit(limit, DEFAULT_THREAD_LIMIT, MAX_THREAD_LIMIT)
    return MySQL.query.await([[
        SELECT id, sender, staff_cid, staff_name, citizen_name, body, kind, meta, created_at
        FROM (
            SELECT id, sender, staff_cid, staff_name, citizen_name, body, kind, meta, created_at
            FROM phone_service_messages
            WHERE job = ? AND citizen_number = ?
            ORDER BY created_at DESC, id DESC
            LIMIT ?
        ) recent
        ORDER BY created_at ASC, id ASC
    ]], { job, citizenNumber, rowLimit }) or {}
end

---The newest rows of several threads at once, returned oldest first per thread, so an inbox rebuild
---costs one round trip instead of one per thread. `fixedCol`/`inCol` are file constants, never
---client input. A key missing from the result is the caller's cue to read that one thread itself.
---@param fixedCol string column pinned to one value
---@param fixedValue string
---@param inCol string column the thread set is keyed by, and the returned map's key
---@param values string[] thread keys
---@param limit number per-thread row cap, matching threadMessages
---@return table<string, table[]> byKey threads this covers; keys it could not cover are absent
local function batchThreads(fixedCol, fixedValue, inCol, values, limit)
    if type(values) ~= 'table' then return {} end

    local rowLimit = boundedLimit(limit, DEFAULT_THREAD_LIMIT, MAX_THREAD_LIMIT)
    local keys, seen = {}, {}
    for index = 1, math.min(#values, MAX_BATCH_KEYS) do
        local value = values[index]
        if type(value) == 'string' and value ~= '' and not seen[value] then
            seen[value] = true
            keys[#keys + 1] = value
        end
    end

    local n = #keys
    if n == 0 then return {} end

    local args = { fixedValue }
    for i = 1, n do args[i + 1] = keys[i] end
    args[#args + 1] = rowLimit

    local rows = MySQL.query.await(([[
        SELECT %s, id, sender, staff_cid, staff_name, citizen_name, body, kind, meta, created_at
        FROM (
            SELECT %s, id, sender, staff_cid, staff_name, citizen_name, body, kind, meta, created_at,
                   ROW_NUMBER() OVER (PARTITION BY %s ORDER BY created_at DESC, id DESC) AS row_num
            FROM phone_service_messages
            WHERE %s = ? AND %s IN (%s)
        ) recent
        WHERE row_num <= ?
        ORDER BY %s ASC, created_at ASC, id ASC
    ]]):format(inCol, inCol, inCol, fixedCol, inCol, string.rep('?', n, ','), inCol), args) or {}

    local out = {}
    for i = 1, #rows do
        local row = rows[i]
        local key = row[inCol]
        if key ~= nil then
            local list = out[key]
            if not list then list = {}; out[key] = list end
            list[#list + 1] = row
        end
    end

    return out
end

---Messages for many customer threads of one job. Keys the batch could not cover are absent.
---@param job string
---@param citizenNumbers string[]
---@param limit number
---@return table<string, table[]> byCitizenNumber
function store.jobThreadMessages(job, citizenNumbers, limit)
    return batchThreads('job', job, 'citizen_number', citizenNumbers, limit)
end

---Messages for many company threads of one customer. Keys the batch could not cover are absent.
---@param citizenNumber string
---@param jobs string[]
---@param limit number
---@return table<string, table[]> byJob
function store.citizenThreadMessages(citizenNumber, jobs, limit)
    return batchThreads('citizen_number', citizenNumber, 'job', jobs, limit)
end

---True when a (job, citizen) thread already has at least one message. Staff replies are gated on
---this: without it a client-chosen number mints a brand-new thread per call. Read-only.
---@param job string
---@param citizenNumber string
---@return boolean
function store.threadExists(job, citizenNumber)
    if not job or job == '' or not citizenNumber or citizenNumber == '' then return false end
    return MySQL.scalar.await(
        'SELECT 1 FROM phone_service_messages WHERE job = ? AND citizen_number = ? LIMIT 1',
        { job, citizenNumber }) ~= nil
end

---Distinct customer threads for a job (one row per customer, newest first), each carrying the
---latest body + the customer's most recent known display name. Read-only.
---@param job string
---@param limit? number thread cap (default 50); the inbox runs one query per thread returned
---@return { citizen_number: string, citizen_name?: string, last_body?: string, created_at: number }[]
function store.jobThreads(job, limit)
    local threadLimit = boundedLimit(limit, DEFAULT_INBOX_LIMIT, MAX_INBOX_LIMIT)
    return MySQL.query.await([[
        SELECT t.citizen_number, t.created_at,
               (SELECT body FROM phone_service_messages
                  WHERE job = ? AND citizen_number = t.citizen_number
                  ORDER BY created_at DESC, id DESC LIMIT 1) AS last_body,
               (SELECT citizen_name FROM phone_service_messages
                  WHERE job = ? AND citizen_number = t.citizen_number AND citizen_name IS NOT NULL
                  ORDER BY created_at DESC LIMIT 1) AS citizen_name
        FROM (
            SELECT citizen_number, MAX(created_at) AS created_at
            FROM phone_service_messages WHERE job = ?
            GROUP BY citizen_number
        ) t
        ORDER BY t.created_at DESC
        LIMIT ?
    ]], { job, job, job, threadLimit }) or {}
end

---Marks a (viewer, job, citizen) thread read up to `ts`; the stored timestamp never moves
---backwards.
---@param viewer string
---@param job string
---@param citizenNumber string
---@param ts number
function store.markRead(viewer, job, citizenNumber, ts)
    if not viewer or viewer == '' or not job or job == '' or not citizenNumber or citizenNumber == '' then return end
    MySQL.update.await([[
        INSERT INTO phone_service_msg_reads (viewer, job, citizen_number, last_read) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE last_read = GREATEST(last_read, VALUES(last_read))
    ]], { viewer, job, citizenNumber, ts or 0 })
end

---Unread customer messages per thread for a STAFF viewer of `job` (citizen_number -> count).
---Only counts messages from the customer side. Read-only.
---@param viewer string
---@param job string
---@param limit? number
---@return table<string, number>
function store.jobUnread(viewer, job, limit)
    local rowLimit = boundedLimit(limit, DEFAULT_INBOX_LIMIT, MAX_INBOX_LIMIT)
    local rows = MySQL.query.await([[
        SELECT m.citizen_number AS k, COUNT(*) AS unread
        FROM phone_service_messages m
        LEFT JOIN phone_service_msg_reads r
            ON r.viewer = ? AND r.job = m.job AND r.citizen_number = m.citizen_number
        WHERE m.job = ? AND m.sender = 'citizen' AND m.created_at > COALESCE(r.last_read, 0)
        GROUP BY m.citizen_number
        ORDER BY MAX(m.created_at) DESC
        LIMIT ?
    ]], { viewer, job, rowLimit }) or {}
    local map = {}
    for _, row in ipairs(rows) do map[row.k] = tonumber(row.unread) or 0 end
    return map
end

---Unread company replies per thread for a CUSTOMER viewer (job -> count). Only counts messages
---from the staff side. Read-only.
---@param viewer string
---@param citizenNumber string
---@param limit? number
---@return table<string, number>
function store.personalUnread(viewer, citizenNumber, limit)
    local rowLimit = boundedLimit(limit, DEFAULT_INBOX_LIMIT, MAX_INBOX_LIMIT)
    local rows = MySQL.query.await([[
        SELECT m.job AS k, COUNT(*) AS unread
        FROM phone_service_messages m
        LEFT JOIN phone_service_msg_reads r
            ON r.viewer = ? AND r.job = m.job AND r.citizen_number = m.citizen_number
        WHERE m.citizen_number = ? AND m.sender = 'staff' AND m.created_at > COALESCE(r.last_read, 0)
        GROUP BY m.job
        ORDER BY MAX(m.created_at) DESC
        LIMIT ?
    ]], { viewer, citizenNumber, rowLimit }) or {}
    local map = {}
    for _, row in ipairs(rows) do map[row.k] = tonumber(row.unread) or 0 end
    return map
end

---Distinct company threads for a customer (one row per job, newest first), each carrying the
---latest body. Read-only.
---@param citizenNumber string
---@param limit? number
---@return { job: string, last_body?: string, created_at: number }[]
function store.citizenThreads(citizenNumber, limit)
    local threadLimit = boundedLimit(limit, DEFAULT_INBOX_LIMIT, MAX_INBOX_LIMIT)
    return MySQL.query.await([[
        SELECT t.job, t.created_at,
               (SELECT body FROM phone_service_messages
                  WHERE citizen_number = ? AND job = t.job
                  ORDER BY created_at DESC, id DESC LIMIT 1) AS last_body
        FROM (
            SELECT job, MAX(created_at) AS created_at
            FROM phone_service_messages WHERE citizen_number = ?
            GROUP BY job
        ) t
        ORDER BY t.created_at DESC
        LIMIT ?
    ]], { citizenNumber, citizenNumber, threadLimit }) or {}
end

return store
