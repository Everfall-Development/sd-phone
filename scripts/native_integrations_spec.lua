package.path = './?.lua;./?/init.lua;' .. package.path

-- Mail onboarding must enter through the same authoritative sign-up action as the NUI. This
-- harness captures the server export without booting FiveM or a database.
local mailExports = {}
local signUpSource
local signUpPayload

CreateThread = function(callback) callback() end
exports = function(name, handler) mailExports[name] = handler end
lib = { callback = { register = function() end } }

package.preload['server.boot'] = function()
    return { schemaFailed = function() end, schemaReady = function() end }
end
package.preload['server.mail.store'] = function()
    return { ensureSchema = function() end }
end
package.preload['server.mail.actions'] = function()
    return {
        repairOrphanAccounts = function() end,
        signUp = function(source, payload)
            signUpSource = source
            signUpPayload = payload
            return { success = true, data = { account = { email = payload.email } } }
        end,
    }
end
package.preload['server.badges.init'] = function()
    return { push = function() end }
end
package.preload['server.util'] = function()
    return {
        fail = function(message) return { success = false, message = message } end,
        trim = function(value)
            if type(value) ~= 'string' then return '' end
            return value:match('^%s*(.-)%s*$')
        end,
    }
end

require 'server.mail.init'

local invalidSource = mailExports.createMailAccount('7', {})
assert(invalidSource.success == false)
assert(signUpSource == nil)

local invalidPayload = mailExports.createMailAccount(7, 'payload')
assert(invalidPayload.success == false)
assert(signUpSource == nil)

local payload = {
    email = 'new.player@everfall.com',
    password = 'secret',
    displayName = 'New',
    phone = '5550100',
}
local created = mailExports.createMailAccount(7, payload)
assert(created.success == true)
assert(signUpSource == 7)
assert(signUpPayload == payload)

-- Birdy moderation deletes both the content store and the shared account-engine identity. It is
-- handle-based and server-only; malformed or unknown handles are harmless no-ops.
local profile
local account
local deletedProfile
local deletedAccount

package.loaded['configs.config'] = nil
package.loaded['bridge.server.player'] = nil
package.loaded['server.birdy.store'] = nil
package.loaded['server.accounts.store'] = nil
package.loaded['server.accounts.actions'] = nil
package.loaded['server.settings.store'] = nil
package.loaded['server.banking.actions'] = nil
package.loaded['bridge.server.money'] = nil
package.loaded['server.badges.init'] = nil
package.loaded['server.admin.moderation'] = nil
package.loaded['server.watchers'] = nil
package.loaded['server.util'] = nil
package.loaded['server.birdy.actions'] = nil

package.preload['configs.config'] = function()
    return { Birdy = {}, Mail = { Domain = 'everfall.com' } }
end
package.preload['bridge.server.player'] = function() return {} end
package.preload['server.birdy.store'] = function()
    return {
        getProfileByHandle = function(handle)
            assert(handle == 'bad_actor')
            return profile
        end,
        deleteAccount = function(handle) deletedProfile = handle end,
    }
end
package.preload['server.accounts.store'] = function()
    return {
        getAccount = function(app, handle)
            assert(app == 'birdy')
            assert(handle == 'bad_actor')
            return account
        end,
        deleteAccount = function(id) deletedAccount = id end,
    }
end
package.preload['server.accounts.actions'] = function() return {} end
package.preload['server.settings.store'] = function() return {} end
package.preload['server.banking.actions'] = function() return {} end
package.preload['bridge.server.money'] = function() return {} end
package.preload['server.badges.init'] = function() return {} end
package.preload['server.admin.moderation'] = function() return {} end
package.preload['server.watchers'] = function()
    return { of = function() return {} end }
end
package.preload['server.util'] = function()
    return {
        ok = function(data) return { success = true, data = data } end,
        fail = function(message) return { success = false, message = message } end,
    }
end

local birdyActions = require 'server.birdy.actions'
assert(birdyActions.deleteAccountByHandle(nil) == false)

profile = nil
account = nil
assert(birdyActions.deleteAccountByHandle('@bad_actor') == false)

profile = { handle = 'bad_actor' }
account = { id = 'account-id' }
assert(birdyActions.deleteAccountByHandle('@Bad_Actor') == true)
assert(deletedProfile == 'bad_actor')
assert(deletedAccount == 'account-id')

print('native_integrations_spec: ok')
