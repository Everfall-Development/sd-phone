---@type table Sessions porter (server.migrate.port.sessions). Turns lb-phone's logged-in accounts
---into accounts-engine sessions so migrated players stay signed in. Mail and Birdy are excluded:
---their domain porters own their login state.
local M = {}

---@type table Migration data layer (server.migrate.store).
local store = require 'server.migrate.store'

---@type table<string, string> lb app name -> sd app name, keyed lowercase. lb-phone stores these
---capitalised ('Instagram', 'Twitter'), so the lookup lowercases first; matching the raw value
---silently skipped every login row and signed nobody in.
local APPS = { instagram = 'photogram' }

---The sd-phone app a migrated login belongs to, or nil when sd-phone has no counterpart.
---@param app any lb app name, any casing
---@return string|nil
local function appFor(app)
    return APPS[tostring(app or ''):lower()]
end

local function digits(s) return (tostring(s or ''):gsub('%D', '')) end

---@param ctx table migration context (numberToCid, dryRun)
---@return { written: number, skipped: number }
function M.run(ctx)
    local rows, written, skipped = {}, 0, 0
    if not store.lbSource('logged_in_accounts') then
        return { written = 0, skipped = 0 }
    end

    for _, l in ipairs(store.lbLoggedIn()) do
        local app = appFor(l.app)
        local cid = ctx.numberToCid[digits(l.phone_number)]
        if not app or not cid then
            skipped = skipped + 1
        else
            rows[#rows + 1] = { app, cid, l.username }
            written = written + 1
        end
    end

    local orphan, created = 0, 0
    if not ctx.dryRun then
        -- Judge on `linked`, not on rows inserted: a re-run finds every session already present and
        -- inserts nothing, which is success. Only a failure to resolve any account at all means the
        -- accounts are missing, so raise and leave the domain unmarked to retry rather than record a
        -- success that signed nobody in.
        local linked, inserted = store.insertPgSessions(rows)
        linked, inserted = linked or 0, inserted or 0
        if linked == 0 and #rows > 0 then
            error(('no app accounts found to link %d session(s); photogram may have failed'):format(#rows), 0)
        end
        orphan, written, created = written - linked, linked, inserted
    end
    return {
        written = written, created = created, skipped = skipped, orphan = orphan,
    }
end

return M
