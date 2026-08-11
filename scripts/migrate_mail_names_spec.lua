package.path = './?.lua;./?/init.lua;' .. package.path

local insertedMailAccounts
local insertedEngineAccounts
local grantedLogins

package.preload['configs.mail'] = function()
    return { Domain = 'lifeinvader.com' }
end

package.preload['server.mail.store'] = function()
    return { reconcileSessions = function() end }
end

package.preload['server.migrate.store'] = function()
    return {
        lbSource = function() return true end,
        lbMailAccounts = function()
            return {
                { address = 'alice@eyefind.info', password = 'alice-password' },
                { address = 'bob@eyefind.info', password = 'bob-password' },
                { address = 'unknown@eyefind.info', password = 'unknown-password' },
            }
        end,
        lbMailAccountLinks = function()
            return {
                { phone_number = '111', username = 'alice@eyefind.info', active = 1 },
                { phone_number = '222', username = 'bob@eyefind.info', active = 0 },
                { phone_number = '333', username = 'bob@eyefind.info', active = 0 },
            }
        end,
        lbMailMessages = function()
            return {
                {
                    id = 1,
                    recipient = 'unknown@eyefind.info',
                    sender = 'alice@eyefind.info',
                    subject = 'Known sender',
                    content = 'Hello',
                    ts = 100,
                    read = false,
                },
                {
                    id = 2,
                    recipient = 'alice@eyefind.info',
                    sender = 'bob@eyefind.info',
                    subject = 'Ambiguous sender',
                    content = 'Hello',
                    ts = 200,
                    read = true,
                },
            }
        end,
        encodeJson = function(value) return value end,
        insertMailAccounts = function(rows) insertedMailAccounts = rows end,
        insertPgAccounts = function(rows) insertedEngineAccounts = rows end,
        grantMigratedLogins = function(rows)
            grantedLogins = rows
            return #rows, 0
        end,
    }
end

local porter = require 'server.migrate.port.mail'
local result = porter.run({
    numberToCid = { ['111'] = 'cid-alice', ['222'] = 'cid-bob', ['333'] = 'cid-other' },
    namesByCid = {
        ['cid-alice'] = 'Alice Carter',
        ['cid-bob'] = 'Bob Bailey',
        ['cid-other'] = 'Other Person',
    },
    dryRun = false,
})

assert(result.accounts == 3)
assert(result.messages == 2)
assert(result.sessions == 1, 'only active legacy login rows should restore sessions')
assert(#grantedLogins == 1 and grantedLogins[1].cid == 'cid-alice')

local mailByAddress = {}
for _, row in ipairs(insertedMailAccounts) do mailByAddress[row[1]] = row end

assert(mailByAddress['alice@lifeinvader.com'][3] == 'Alice Carter')
assert(mailByAddress['bob@lifeinvader.com'][3] == 'bob', 'conflicting owners must keep the safe local-part fallback')
assert(mailByAddress['unknown@lifeinvader.com'][3] == 'unknown')

local aliceInbox = mailByAddress['alice@lifeinvader.com'][4]
local unknownInbox = mailByAddress['unknown@lifeinvader.com'][4]
assert(aliceInbox[1].from.name == 'bob', 'ambiguous sender must not inherit either character name')
assert(unknownInbox[1].from.name == 'Alice Carter', 'known sender should use the owning character name')

local engineByAddress = {}
for _, row in ipairs(insertedEngineAccounts) do engineByAddress[row[2]] = row end
assert(engineByAddress['alice@lifeinvader.com'][3] == 'Alice Carter')
assert(engineByAddress['bob@lifeinvader.com'][3] == 'bob')

print('migrate_mail_names_spec: ok')
