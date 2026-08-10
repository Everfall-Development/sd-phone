package.path = './?.lua;./?/init.lua;' .. package.path

local cryptoHashCalls = 0
local widthChecks = {}

package.preload['server.util'] = function()
    return {
        ensureColumnWidth = function(tableName, columnName, _, width)
            assert(width == 255)
            widthChecks[tableName .. '.' .. columnName] = true
        end,
    }
end

package.preload['server.crypto'] = function()
    return {
        available = function() return true end,
        hashPassword = function()
            cryptoHashCalls = cryptoHashCalls + 1
            return 'scrypt$interactive'
        end,
        verifyPassword = function() return false end,
        encrypt = function(plain) return 'v1$sealed$' .. plain end,
        decrypt = function(stored) return stored:match('^v1%$sealed%$(.+)$') end,
    }
end

local realAccounts = require 'server.accounts.store'
local importedHash = realAccounts.hashImportedPassword('bulk-password')
assert(type(importedHash) == 'string' and #importedHash == 24)
assert(realAccounts.verifyPassword('bulk-password', importedHash))
assert(cryptoHashCalls == 0, 'bulk migration hashing must not call synchronous scrypt')
assert(realAccounts.sealImportedVaultSecret('saved-password') == 'v1$sealed$saved-password')
assert(realAccounts.openImportedVaultSecret('v1$sealed$saved-password') == 'saved-password')
assert(realAccounts.openImportedVaultSecret('legacy-password') == 'legacy-password')
assert(realAccounts.openImportedVaultSecret('v1$unreadable') == nil)
assert(realAccounts.canVerifyImportedPasswordHash('scrypt$fixture'))

local waits = 0
local pageReads = 0
local accountPageReads = 0
local importedHashCalls = 0
local verifyCalls = 0
local sealedValues = {}
local stagedSql
local stagedParams
local vaultInsert

function Wait(delay)
    assert(delay == 0)
    waits = waits + 1
end

local accounts = {
    openImportedVaultSecret = function(stored)
        return stored:match('^v1%$fixture%$(.+)$')
    end,
    verifyPassword = function(plain, stored)
        verifyCalls = verifyCalls + 1
        return (stored == 'scrypt$alice' and plain == 'alice-password')
            or (stored == 'scrypt$carol' and plain == 'carol-right')
    end,
    canVerifyImportedPasswordHash = function(stored)
        return stored ~= 'scrypt$heidi'
    end,
    hashImportedPassword = function(plain)
        importedHashCalls = importedHashCalls + 1
        return 'legacy$' .. plain
    end,
    sealImportedVaultSecret = function(plain)
        sealedValues[#sealedValues + 1] = plain
        return 'v1$sealed$' .. plain
    end,
}

package.loaded['server.accounts.store'] = accounts
package.preload['configs.config'] = function()
    return { Migrate = { sourcePrefix = 'phone_' } }
end
package.preload['server.settings.store'] = function()
    return {}
end

local function fixtureRow(id, username, password, hash)
    return {
        id = id,
        app = 'birdy',
        username = username,
        password = 'v1$fixture$' .. password,
        password_hash = hash,
    }
end

local function firstVaultPage()
    local rows = {}
    for id = 1, 500 do
        rows[id] = fixtureRow(id, 'unrelated-' .. tostring(id), 'unused', 'scrypt$unused')
    end
    rows[2] = fixtureRow(2, 'alice', 'alice-password', 'scrypt$alice')
    rows[3] = fixtureRow(3, 'dave', 'unused', 'scrypt$dave')
    rows[3].password = 'v1$unreadable'
    rows[4] = fixtureRow(4, 'eve', 'eve-wrong', 'scrypt$eve')
    rows[5] = fixtureRow(5, 'grace', 'grace-stale', '$2b$source-bcrypt')
    rows[6] = fixtureRow(6, 'heidi', 'heidi-password', 'scrypt$heidi')
    rows[499] = fixtureRow(499, 'carol', 'carol-wrong', 'scrypt$carol')
    return rows
end

local function accountRow(id, username, hash)
    return { id = id, app = 'birdy', username = username, password_hash = hash }
end

MySQL = {
    query = {
        await = function(sql, params)
            if sql:find('SELECT id, app, username, password_hash', 1, true) then
                accountPageReads = accountPageReads + 1
                assert(sql:find('ORDER BY id ASC', 1, true))
                assert(sql:find('LIMIT 500', 1, true))
                assert(params[1] == 0 and params[2] == 'birdy')
                return {
                    accountRow(1, 'alice', 'scrypt$alice'),
                    accountRow(2, 'bob', '$2b$source-bcrypt'),
                    accountRow(3, 'carol', 'scrypt$carol'),
                    accountRow(4, 'dave', 'scrypt$dave'),
                    accountRow(5, 'eve', 'scrypt$eve'),
                    accountRow(6, 'frank', 'scrypt$frank'),
                    accountRow(7, 'grace', '$2b$source-bcrypt'),
                    accountRow(8, 'heidi', 'scrypt$heidi'),
                }
            end

            if sql:find('SELECT p.id, p.app, p.username', 1, true) then
                pageReads = pageReads + 1
                assert(sql:find('ORDER BY p.id ASC', 1, true))
                assert(sql:find('LIMIT 500', 1, true))
                assert(params[2] == 'birdy')
                if params[1] == 0 then return firstVaultPage() end
                if params[1] == 500 then
                    return { fixtureRow(501, 'carol', 'carol-right', 'scrypt$carol') }
                end
                error('unexpected vault cursor: ' .. tostring(params[1]))
            end

            if sql:find('INSERT IGNORE INTO `_sdphone_migrate_logins`', 1, true) then
                stagedSql = sql
                stagedParams = params
            end
            if sql:find('INSERT INTO phone_passwords', 1, true) then
                vaultInsert = sql
            end
            return {}
        end,
    },
    scalar = {
        await = function(sql)
            assert(sql:find('COUNT(DISTINCT t.app, t.username)', 1, true))
            return 4
        end,
    },
    update = {
        await = function() return 0 end,
    },
}

local migrationStore = require 'server.migrate.store'
local granted, deferred = migrationStore.grantMigratedLogins({
    { app = 'birdy', username = 'alice', cid = 'cid-alice-1', email = nil },
    { app = 'birdy', username = 'alice', cid = 'cid-alice-2', email = nil },
    { app = 'birdy', username = 'bob', cid = 'cid-bob-1', email = nil },
    { app = 'birdy', username = 'bob', cid = 'cid-bob-2', email = nil },
    { app = 'birdy', username = 'carol', cid = 'cid-carol', email = 'carol@example.com' },
    { app = 'birdy', username = 'dave', cid = 'cid-dave', email = nil },
    { app = 'birdy', username = 'eve', cid = 'cid-eve', email = nil },
    { app = 'birdy', username = 'frank', cid = 'cid-frank', email = nil },
    { app = 'birdy', username = 'grace', cid = 'cid-grace', email = nil },
    { app = 'birdy', username = 'heidi', cid = 'cid-heidi', email = nil },
})

assert(granted == 4)
assert(deferred == 2, 'unreadable or unverifiable encrypted credentials must keep the domain pending')
assert(widthChecks['phone_app_accounts.password_hash'])
assert(widthChecks['phone_passwords.password'])
assert(widthChecks['phone_birdy_profiles.password'])
assert(accountPageReads == 1, 'existing account hashes must be read in a bounded keyset page')
assert(pageReads == 2, 'vault rows must be read in bounded keyset pages')
assert(verifyCalls == 5, 'each saved credential must be verified before reuse')
assert(importedHashCalls == 2, 'each new or foreign account must be hashed once')
assert(waits >= 7, 'paged reads and each scrypt verification must yield')
assert(#sealedValues == 6, 'each staged owner credential must use the encrypted vault path')
assert(stagedSql and stagedSql:find('(?,?,?,?,?,NULL)', 1, true))
assert(stagedSql and stagedSql:find('(?,?,?,?,?,?)', 1, true))
assert(vaultInsert and vaultInsert:find('t.stored', 1, true))
assert(not vaultInsert:find('t.plain', 1, true))

local staged = {}
local stagedRows = {
    { position = 1, username = 'alice', hasEmail = false },
    { position = 6, username = 'alice', hasEmail = false },
    { position = 11, username = 'bob', hasEmail = false },
    { position = 16, username = 'bob', hasEmail = false },
    { position = 21, username = 'carol', hasEmail = true },
    { position = 27, username = 'grace', hasEmail = false },
}
for i = 1, #stagedRows do
    local expected = stagedRows[i]
    local position = expected.position
    local username = stagedParams[position + 1]
    assert(username == expected.username)
    staged[username] = staged[username] or {}
    staged[username][#staged[username] + 1] = {
        stored = stagedParams[position + 3],
        hash = stagedParams[position + 4],
    }
    if expected.hasEmail then assert(stagedParams[position + 5] == 'carol@example.com') end
end

assert(#staged.alice == 2)
assert(staged.alice[1].stored == 'v1$sealed$alice-password')
assert(staged.alice[1].hash == 'scrypt$alice')
assert(staged.alice[2].hash == staged.alice[1].hash)

assert(#staged.bob == 2)
assert(staged.bob[1].stored == staged.bob[2].stored)
assert(staged.bob[1].hash == staged.bob[2].hash)
assert(staged.bob[1].hash:sub(1, 7) == 'legacy$')

assert(#staged.carol == 1)
assert(staged.carol[1].stored == 'v1$sealed$carol-right')
assert(staged.carol[1].hash == 'scrypt$carol')
assert(staged.dave == nil, 'an unreadable encrypted credential must remain untouched')
assert(staged.eve == nil, 'a saved credential that does not verify must remain untouched')
assert(staged.frank == nil, 'a working account without a vault copy must not be rotated')
assert(staged.heidi == nil, 'a scrypt credential must wait until the crypto helper is available')
assert(#staged.grace == 1)
assert(staged.grace[1].hash:sub(1, 7) == 'legacy$', 'a foreign source hash needs a fresh login')

local function read(path)
    local file = assert(io.open(path, 'r'))
    local value = file:read('*a')
    file:close()
    return value
end

for _, path in ipairs({
    'server/migrate/port/birdy.lua',
    'server/migrate/port/photogram.lua',
    'server/migrate/port/mail.lua',
}) do
    local source = read(path)
    assert(source:find('out.logins, out.deferred = store.grantMigratedLogins(grants)', 1, true))
    assert(source:find('if out.deferred > 0 then out.retry = true end', 1, true))
end

print('migrate_logins_spec: ok')
