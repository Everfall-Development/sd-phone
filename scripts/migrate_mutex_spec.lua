package.path = './?.lua;./?/init.lua;' .. package.path

local output = print
local commands = {}
local queuedThreads = {}
local logs = {}
local executeThreads = false
local tableChecks = 0
local tableBehavior = 'nested'

function CreateThread(callback)
    if executeThreads then
        callback()
        return
    end
    queuedThreads[#queuedThreads + 1] = callback
end

function RegisterCommand(name, callback)
    commands[name] = callback
end

function GetGameTimer()
    return 0
end

function TriggerClientEvent() end

function print(value)
    logs[#logs + 1] = tostring(value)
end

lib = {
    math = {
        round = function(value) return math.floor(value + 0.5) end,
        groupdigits = function(value) return tostring(value) end,
    },
}

package.preload['configs.config'] = function()
    return { Migrate = { enabled = true } }
end
package.preload['bridge.shared.framework'] = function()
    return {}
end
package.preload['server.migrate.identity'] = function()
    return {}
end
package.preload['server.migrate.plan'] = function()
    return {}
end

package.preload['server.migrate.store'] = function()
    return {
        lbTable = function(name) return 'phone_' .. name end,
        tableExists = function()
            tableChecks = tableChecks + 1
            if tableBehavior == 'nested' then
                tableBehavior = 'missing'
                commands['sdphone:migrate'](0, {})
            elseif tableBehavior == 'error' then
                error('fixture import failure')
            end
            return false
        end,
    }
end

local portNames = {
    'numbers', 'contacts', 'blocked', 'calls', 'messages', 'reactions', 'photos', 'notes',
    'settings', 'photogram', 'birdy', 'mail', 'wallet', 'voicememos', 'sessions',
}
for i = 1, #portNames do
    package.preload['server.migrate.port.' .. portNames[i]] = function()
        return { run = function() return {} end }
    end
end

require 'server.migrate.init'

assert(#queuedThreads == 1, 'the boot importer should schedule exactly one runner')
assert(type(commands['sdphone:migrate']) == 'function')

executeThreads = true
queuedThreads[1]()

local guardMessages = 0
for i = 1, #logs do
    if logs[i]:find('an lb-phone import is already running', 1, true) then
        guardMessages = guardMessages + 1
    end
end
assert(guardMessages == 1, 'a console import must be refused while the boot import owns the runner')
assert(tableChecks == 1, 'the refused import must not enter database preflight')

commands['sdphone:migrate'](0, {})
assert(tableChecks == 2, 'the guard must release after a normal early return')

tableBehavior = 'error'
commands['sdphone:migrate'](0, {})
assert(tableChecks == 3)

tableBehavior = 'missing'
commands['sdphone:migrate'](0, {})
assert(tableChecks == 4, 'the guard must release after an import error')

output('migrate_mutex_spec: ok')
