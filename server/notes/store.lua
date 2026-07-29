---@type table Store module; the table returned at end of file. One row per note, scoped to a
---citizenid (PK citizenid+id); every statement filters by citizenid. Sketches and images are
---stored inline as JSON arrays, timestamps as the client's ISO strings.
local store = {}

---@type table Shared server helpers (server.util): legacy-table rescue.
local util = require 'server.util'

---Creates the phone_notes table if it doesn't exist, and back-fills shared-device columns. Runs
---once at boot. lb-phone uses the same table name with a different shape; such a table is moved
---aside first so the CREATE below builds the real sd-phone one.
function store.ensureSchema()
    util.rescueLegacyTable('phone_notes', 'citizenid')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `phone_notes` (
            `citizenid`  VARCHAR(60) NOT NULL,
            `id`         VARCHAR(40) NOT NULL,
            `title`      VARCHAR(128) NOT NULL DEFAULT '',
            `body`       MEDIUMTEXT  NOT NULL,
            `color`      VARCHAR(16) NULL,
            `sketches`   MEDIUMTEXT  NOT NULL,
            `images`     MEDIUMTEXT  NULL,
            `created_at` VARCHAR(40) NOT NULL,
            `updated_at` VARCHAR(40) NOT NULL,
            PRIMARY KEY (`citizenid`, `id`),
            KEY `updated` (`citizenid`, `updated_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    local hasImages = MySQL.scalar.await([[
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'phone_notes' AND COLUMN_NAME = 'images' LIMIT 1
    ]])
    if not hasImages then
        MySQL.query.await('ALTER TABLE `phone_notes` ADD COLUMN `images` MEDIUMTEXT NULL AFTER `sketches`')
    end

    local hasTitle = MySQL.scalar.await([[
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'phone_notes' AND COLUMN_NAME = 'title' LIMIT 1
    ]])
    if not hasTitle then
        MySQL.query.await("ALTER TABLE `phone_notes` ADD COLUMN `title` VARCHAR(128) NOT NULL DEFAULT '' AFTER `id`")
    end

    local hasColor = MySQL.scalar.await([[
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'phone_notes' AND COLUMN_NAME = 'color' LIMIT 1
    ]])
    if not hasColor then
        MySQL.query.await('ALTER TABLE `phone_notes` ADD COLUMN `color` VARCHAR(16) NULL AFTER `body`')
    end
end

---@type integer Ceiling on one read of a player's notes. Each row carries a body plus sketch and
---image JSON, so an uncapped read is heavy per row as well as unbounded in count.
local NOTES_CAP <const> = 300

---A player's notes, newest-edited first, capped. Read-only.
---@param cid string owner citizenid
---@return table[] rows note rows, empty when none
function store.forPlayer(cid)
    return MySQL.query.await(([[
        SELECT id, title, body, color, sketches, images, created_at, updated_at
        FROM `phone_notes` WHERE citizenid = ? ORDER BY updated_at DESC
        LIMIT %d
    ]]):format(NOTES_CAP), { cid }) or {}
end

---Inserts or updates a note. `created_at` is only set on first insert.
---@param cid string owner citizenid
---@param id string note id (client-generated, <= 40 chars)
---@param title string note title
---@param body string note body without the title line
---@param color string|nil optional shared-device colour
---@param sketches string JSON array of sketch data URLs
---@param images string JSON array of image URLs
---@param createdAt string ISO timestamp
---@param updatedAt string ISO timestamp
function store.upsert(cid, id, title, body, color, sketches, images, createdAt, updatedAt)
    MySQL.query.await([[
        INSERT INTO `phone_notes` (citizenid, id, title, body, color, sketches, images, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            title      = VALUES(title),
            body       = VALUES(body),
            color      = VALUES(color),
            sketches   = VALUES(sketches),
            images     = VALUES(images),
            updated_at = VALUES(updated_at)
    ]], { cid, id, title, body, color, sketches, images, createdAt, updatedAt })
end

---Deletes a note, scoped to its owner. Idempotent.
---@param cid string owner citizenid
---@param id string note id
function store.delete(cid, id)
    MySQL.query.await('DELETE FROM `phone_notes` WHERE citizenid = ? AND id = ?', { cid, id })
end

---Whether this player already has a note with this id (a primary-key lookup). Read-only.
---@param cid string owner citizenid
---@param id string note id
---@return boolean exists
function store.exists(cid, id)
    return MySQL.scalar.await('SELECT 1 FROM `phone_notes` WHERE citizenid = ? AND id = ? LIMIT 1', { cid, id }) ~= nil
end

---How many notes this player has (drives the per-player cap). Read-only.
---@param cid string owner citizenid
---@return integer count
function store.countFor(cid)
    return MySQL.scalar.await('SELECT COUNT(*) FROM `phone_notes` WHERE citizenid = ?', { cid }) or 0
end

---Whether the player already has a note with this exact body (idempotent saves). Read-only.
---@param cid string owner citizenid
---@param body string
---@return boolean
function store.hasBody(cid, body)
    return MySQL.scalar.await(
        'SELECT 1 FROM `phone_notes` WHERE citizenid = ? AND body = ? LIMIT 1', { cid, body }) ~= nil
end

return store
