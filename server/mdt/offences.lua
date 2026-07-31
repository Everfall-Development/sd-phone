---@type table sd-phone config root (configs/config.lua); read for the charge-line cap.
local config = require 'configs.config'
---@type table Shared server helpers (server.util): envelopes, clamping, string caps.
local util   = require 'server.util'
---@type table MDT persistence (server.mdt.store): the penal-code read.
local store  = require 'server.mdt.store'
---@type table MDT permissions (server.mdt.access): the read gate and the audited write wrapper.
local access = require 'server.mdt.access'

---@type table Offences module; the table returned at end of file. The penal code, and the single
---place a sentence or a fine is ever calculated.
local offences = {}

---@type table<string, boolean> Valid charge classes; mirrors the ChargeClass union.
local CLASSES = { felony = true, misdemeanor = true, infraction = true }

---@type integer Highest count one charge line may carry.
local MAX_COUNT = 99

---@type integer Highest month value an offence may be worth.
local MAX_MONTHS = 600

---@type integer Highest fine an offence may carry.
local MAX_FINE = 1000000

---@type integer Charge lines one record may carry.
local MAX_LINES = math.floor(tonumber(((config.Mdt or {}).Limits or {}).Charges) or 40)

---@type table|nil Cached catalog: { rows = Offence[], byCode = table<string, Offence> }. Dropped
---on every write, so a management edit is visible on the next read.
local cache

---Reads the catalog into memory, or returns the cached copy.
---@return table catalog { rows: table[], byCode: table<string, table> }
local function load()
    if cache then return cache end

    local rows = store.offences()
    local byCode = {}
    for i = 1, #rows do byCode[rows[i].code] = rows[i] end

    cache = { rows = rows, byCode = byCode }
    return cache
end

---Drops the cached catalog so the next read hits the table.
function offences.invalidate()
    cache = nil
end

---Every offence, felonies first then by code.
---@return table[] rows
function offences.all()
    return load().rows
end

---One offence by code, or nil when it is not in the catalog.
---@param code any
---@return table|nil offence
function offences.byCode(code)
    if type(code) ~= 'string' then return nil end
    return load().byCode[code]
end

---Resolves charge lines against the catalog and totals them. Months and fine are ALWAYS looked up
---here, never taken from the caller, so every screen quotes the same sentence. Line figures stay
---per unit; the totals are what multiply by count.
---@param charges any list of { code: string, count?: number, citizenid?: string }
---@return table[] lines resolved lines { code, label, class, citizenid, count, months, fine }
---@return integer months total months across every line
---@return integer fine total fine across every line
function offences.totalFor(charges)
    local lines, months, fine = {}, 0, 0
    if type(charges) ~= 'table' then return lines, 0, 0 end

    local byCode = load().byCode
    for i = 1, #charges do
        local c = charges[i]
        if type(c) == 'table' and #lines < MAX_LINES then
            local offence = byCode[type(c.code) == 'string' and c.code or '']
            if offence then
                local count = math.floor(tonumber(c.count) or 1)
                if count < 1 then count = 1 end
                if count > MAX_COUNT then count = MAX_COUNT end

                lines[#lines + 1] = {
                    code      = offence.code,
                    label     = offence.label,
                    class     = offence.class,
                    citizenid = (type(c.citizenid) == 'string' and c.citizenid ~= '') and c.citizenid or nil,
                    count     = count,
                    months    = offence.months,
                    fine      = offence.fine,
                }
                months = months + (offence.months * count)
                fine   = fine + (offence.fine * count)
            end
        end
    end

    return lines, months, fine
end

---Class counters for a resolved charge list, as a warrant row stores them.
---@param lines table[] resolved charge lines
---@return integer felonies
---@return integer misdemeanors
---@return integer infractions
function offences.countByClass(lines)
    local felonies, misdemeanors, infractions = 0, 0, 0
    for i = 1, #lines do
        local line = lines[i]
        if line.class == 'felony' then felonies = felonies + line.count
        elseif line.class == 'misdemeanor' then misdemeanors = misdemeanors + line.count
        else infractions = infractions + line.count end
    end
    return felonies, misdemeanors, infractions
end

---The whole penal code. Read by the charge picker, every report total and the jail quote.
offences.list = access.gated('offences.view', function()
    return util.ok({ rows = offences.all() })
end)

---Creates or replaces one offence, keyed on its code.
offences.save = access.audited('offences.manage', function(_, payload)
    local code = util.limitedString(payload.code, 16)
    if not code then return util.fail('A code is required') end

    local label = util.limitedString(payload.label, 120)
    if not label then return util.fail('A label is required') end

    local class = type(payload.class) == 'string' and payload.class or ''
    if not CLASSES[class] then return util.fail('Pick a valid class') end

    local months = util.wholeAmount(payload.months)
    if months > MAX_MONTHS then months = MAX_MONTHS end

    local fine = util.wholeAmount(payload.fine)
    if fine > MAX_FINE then fine = MAX_FINE end

    local description = util.limitedString(payload.description, 255) or ''

    MySQL.query.await([[
        INSERT INTO phone_mdt_offences (`code`, `label`, `class`, `months`, `fine`, `description`)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            `label`       = VALUES(`label`),
            `class`       = VALUES(`class`),
            `months`      = VALUES(`months`),
            `fine`        = VALUES(`fine`),
            `description` = VALUES(`description`)
    ]], { code, label, class, months, fine, description })

    offences.invalidate()
    return util.ok({ offence = offences.byCode(code) }),
        { entityType = 'offence', entityId = code, details = { label = label, class = class } }
end)

---Removes one offence. Charge lines already filed keep the label and figures they were stamped
---with, so deleting a code never rewrites history.
offences.delete = access.audited('offences.delete', function(_, payload)
    local code = util.limitedString(payload.code, 16)
    if not code or not offences.byCode(code) then return util.fail('That offence no longer exists') end

    MySQL.update.await('DELETE FROM phone_mdt_offences WHERE `code` = ?', { code })
    offences.invalidate()
    return util.ok({ code = code }), { entityType = 'offence', entityId = code }
end)

return offences
