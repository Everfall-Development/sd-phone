---@type table Birdy porter (server.migrate.port.birdy). Copies lb-phone's Twitter graph into
---Birdy and restores the active account for each resolved character.
local M = {}

---@type table Migration data layer (server.migrate.store).
local store = require 'server.migrate.store'

local HANDLE_MAX = 15

local function digits(value)
    return (tostring(value or ''):gsub('%D', ''))
end

local function hash(value)
    local result = 2166136261
    local text = tostring(value or '')
    for index = 1, #text do
        result = ((result ~ text:byte(index)) * 16777619) & 0xffffffff
    end
    return ('%08x'):format(result)
end

local function normalizedHandle(value)
    local handle = tostring(value or ''):lower():gsub('[^a-z0-9_]', '')
    if #handle < 2 then handle = 'user_' .. hash(value):sub(1, 8) end
    return handle:sub(1, HANDLE_MAX)
end

---Claims a stable Birdy handle without taking an existing player's name.
---@param source string legacy Twitter username
---@param cid string character id
---@param used table<string, boolean>
---@return string
local function claimHandle(source, cid, used)
    local base = normalizedHandle(source)
    if not used[base] then
        used[base] = true
        return base
    end

    local salt = 0
    while true do
        local suffix = hash(('%s:%s:%d'):format(source, cid, salt)):sub(1, 8)
        local candidate = base:sub(1, HANDLE_MAX - #suffix - 1) .. '_' .. suffix
        if not used[candidate] then
            used[candidate] = true
            return candidate
        end
        salt = salt + 1
    end
end

local function accountOrder(left, right)
    if left.active ~= right.active then return left.active end

    local leftTimestamp = tonumber(left.account.ts) or 0
    local rightTimestamp = tonumber(right.account.ts) or 0
    if leftTimestamp ~= rightTimestamp then return leftTimestamp < rightTimestamp end

    return tostring(left.account.username) < tostring(right.account.username)
end

---Birdy has one profile per character while lb-phone allowed several Twitter accounts per phone.
---Choose the account active on that character's own phone; if none is active, keep the oldest one.
---Unresolved owners and additional accounts cannot be represented without assigning their content
---to the wrong character, so their rows are reported and left untouched in the lb-phone archive.
---@param ctx table migration context (numberToCid, dryRun)
---@return table counts
function M.run(ctx)
    local out = {
        profiles = 0, accounts = 0, posts = 0, likes = 0, reposts = 0,
        follows = 0, dms = 0, notifications = 0, sessions = 0, logins = 0,
        skipped = 0, orphan = 0, unresolved = 0, alternate = 0, occupied = 0,
        sessionOrphan = 0,
    }
    if not store.lbSource('twitter_accounts') then return out end

    local twitterLogins = {}
    local activeByPhone = {}
    if store.lbSource('logged_in_accounts') then
        for _, login in ipairs(store.lbLoggedIn()) do
            if tostring(login.app or ''):lower() == 'twitter' then
                local number = digits(login.phone_number)
                local cid = ctx.numberToCid[number]
                twitterLogins[#twitterLogins + 1] = {
                    username = tostring(login.username or ''),
                    cid = cid,
                }
                activeByPhone[number] = tostring(login.username or ''):lower()
            end
        end
    end

    local groups = {}
    for _, account in ipairs(store.lbTwitterAccounts()) do
        local number = digits(account.phone_number)
        local cid = ctx.numberToCid[number]
        if not cid then
            out.unresolved = out.unresolved + 1
        else
            groups[cid] = groups[cid] or {}
            groups[cid][#groups[cid] + 1] = {
                account = account,
                active = activeByPhone[number] == tostring(account.username):lower(),
            }
        end
    end

    local existing = store.existingBirdyIdentities()
    local used = {}
    for handle in pairs(existing.handles) do used[tostring(handle):lower()] = true end

    local cids = {}
    for cid in pairs(groups) do cids[#cids + 1] = cid end
    table.sort(cids)

    local selected = {}
    for _, cid in ipairs(cids) do
        local candidates = groups[cid]
        table.sort(candidates, accountOrder)
        out.alternate = out.alternate + math.max(0, #candidates - 1)

        local account = candidates[1].account
        local source = tostring(account.username)
        local existingProfile = existing.cids[cid]
        if existingProfile then
            -- A failed first attempt can leave the profile insert behind before the domain marker
            -- is written. Its source phone and original join timestamp identify it precisely enough
            -- to resume the idempotent graph inserts. Any other profile is live data and is skipped.
            local samePhone = digits(existingProfile.phone) == digits(account.phone_number)
            local sameTimestamp = tonumber(existingProfile.created_ts) == tonumber(account.ts)
            if samePhone and sameTimestamp then
                selected[source:lower()] = {
                    account = account,
                    cid = cid,
                    handle = existingProfile.handle,
                    loggedIn = false,
                }
            else
                out.occupied = out.occupied + 1
            end
        else
            selected[source:lower()] = {
                account = account,
                cid = cid,
                handle = claimHandle(source, cid, used),
                loggedIn = false,
            }
        end
    end

    local sessions = {}
    local seenSessions = {}
    for _, login in ipairs(twitterLogins) do
        local profile = selected[login.username:lower()]
        if profile and login.cid and not existing.sessions[login.cid] then
            local key = login.cid .. '\0' .. profile.handle
            if not seenSessions[key] then
                seenSessions[key] = true
                profile.loggedIn = true
                sessions[#sessions + 1] = { 'birdy', login.cid, profile.handle }
            end
        else
            out.sessionOrphan = out.sessionOrphan + 1
        end
    end

    local profiles = {}
    local grants = {}
    for _, profile in pairs(selected) do
        profiles[#profiles + 1] = {
            profile.account.username,
            profile.cid,
            profile.handle,
            profile.loggedIn and 1 or 0,
        }
        grants[#grants + 1] = {
            app = 'birdy',
            username = profile.handle,
            cid = profile.cid,
        }
    end
    table.sort(profiles, function(left, right) return left[2] < right[2] end)

    local migrated = store.migrateBirdy(profiles, ctx.dryRun)
    for key, value in pairs(migrated) do out[key] = value end

    if ctx.dryRun then
        out.sessions = #sessions
        out.logins = #grants
        return out
    end

    out.logins = store.grantMigratedLogins(grants)
    local linked, inserted = store.insertPgSessions(sessions)
    linked, inserted = linked or 0, inserted or 0
    if linked == 0 and #sessions > 0 then
        error(('no Birdy accounts found to link %d active session(s)'):format(#sessions), 0)
    end
    out.sessions = linked
    out.createdSessions = inserted
    out.sessionOrphan = out.sessionOrphan + (#sessions - linked)
    return out
end

return M
