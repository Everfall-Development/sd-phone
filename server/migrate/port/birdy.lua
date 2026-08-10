---@type table Quip porter (server.migrate.port.birdy). Copies lb-phone's Twitter graph into
---Quip and restores every resolved account session for each character.
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

local function identityKey(cid, phone, timestamp)
    return ('%s\0%s\0%s'):format(cid, digits(phone), tonumber(timestamp) or 0)
end

---Quip supports multiple profiles per character. Preserve every legacy account whose phone resolves
---to a character, create a switchable session for each one, and make the account that was active in
---lb-phone the most recently used session.
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

    local activeByPhone = {}
    if store.lbSource('logged_in_accounts') then
        for _, login in ipairs(store.lbLoggedIn()) do
            if tostring(login.app or ''):lower() == 'twitter' then
                local number = digits(login.phone_number)
                local cid = ctx.numberToCid[number]
                if cid then
                    activeByPhone[number] = tostring(login.username or ''):lower()
                else
                    out.sessionOrphan = out.sessionOrphan + 1
                end
            end
        end
    end

    local resolved = {}
    for _, account in ipairs(store.lbTwitterAccounts()) do
        local number = digits(account.phone_number)
        local cid = ctx.numberToCid[number]
        if not cid then
            out.unresolved = out.unresolved + 1
        else
            resolved[#resolved + 1] = {
                account = account,
                cid = cid,
                active = activeByPhone[number] == tostring(account.username):lower(),
            }
        end
    end

    local existing = store.existingBirdyIdentities()
    local used = {}
    for handle in pairs(existing.handles) do used[tostring(handle):lower()] = true end

    local existingByIdentity = {}
    for _, profile in ipairs(existing.profiles) do
        local key = identityKey(profile.citizenid, profile.phone, profile.created_ts)
        existingByIdentity[key] = existingByIdentity[key] or {}
        existingByIdentity[key][#existingByIdentity[key] + 1] = profile
    end
    for _, profiles in pairs(existingByIdentity) do
        table.sort(profiles, function(left, right)
            return tostring(left.handle) < tostring(right.handle)
        end)
    end

    table.sort(resolved, function(left, right)
        if left.cid ~= right.cid then return left.cid < right.cid end
        local leftTimestamp = tonumber(left.account.ts) or 0
        local rightTimestamp = tonumber(right.account.ts) or 0
        if leftTimestamp ~= rightTimestamp then return leftTimestamp < rightTimestamp end
        return tostring(left.account.username) < tostring(right.account.username)
    end)

    local selected = {}
    local accountsByCid = {}
    for _, candidate in ipairs(resolved) do
        local account = candidate.account
        local cid = candidate.cid
        local source = tostring(account.username)
        local key = identityKey(cid, account.phone_number, account.ts)
        local matches = existingByIdentity[key]
        local existingProfile
        if matches then
            local expectedHandle = normalizedHandle(source)
            for index, profile in ipairs(matches) do
                if tostring(profile.handle):lower() == expectedHandle then
                    existingProfile = table.remove(matches, index)
                    break
                end
            end
            existingProfile = existingProfile or table.remove(matches, 1)
        end
        local handle
        if existingProfile then
            handle = existingProfile.handle
        else
            handle = claimHandle(source, cid, used)
        end

        selected[source:lower()] = {
            account = account,
            cid = cid,
            handle = handle,
            active = candidate.active,
        }
        accountsByCid[cid] = (accountsByCid[cid] or 0) + 1
    end
    for _, count in pairs(accountsByCid) do
        out.alternate = out.alternate + math.max(0, count - 1)
    end

    local sessions = {}
    local profiles = {}
    local grants = {}
    for _, profile in pairs(selected) do
        profiles[#profiles + 1] = {
            profile.account.username,
            profile.cid,
            profile.handle,
            profile.active and 1 or 0,
        }
        sessions[#sessions + 1] = {
            'birdy',
            profile.cid,
            profile.handle,
            profile.active and 1 or 0,
        }
        grants[#grants + 1] = {
            app = 'birdy',
            username = profile.handle,
            cid = profile.cid,
        }
    end
    table.sort(profiles, function(left, right)
        if left[2] ~= right[2] then return left[2] < right[2] end
        return left[1] < right[1]
    end)

    local migrated = store.migrateBirdy(profiles, ctx.dryRun)
    for key, value in pairs(migrated) do out[key] = value end

    if ctx.dryRun then
        out.sessions = #sessions
        out.logins = #grants
        return out
    end

    out.logins, out.deferred = store.grantMigratedLogins(grants)
    if out.deferred > 0 then out.retry = true end
    local linked, inserted = store.insertPgSessions(sessions)
    linked, inserted = linked or 0, inserted or 0
    if linked == 0 and #sessions > 0 then
        error(('no Quip accounts found to link %d session(s)'):format(#sessions), 0)
    end
    out.sessions = linked
    out.createdSessions = inserted
    out.sessionOrphan = out.sessionOrphan + (#sessions - linked)
    return out
end

return M
