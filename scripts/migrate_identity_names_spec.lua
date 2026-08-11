package.path = './?.lua;./?/init.lua;' .. package.path

package.preload['configs.config'] = function()
    return { Migrate = { sourcePrefix = 'lb_phone_' } }
end
package.preload['server.settings.store'] = function() return {} end
package.preload['server.util'] = function() return {} end

json = {
    decode = function(value)
        assert(value == 'qb-charinfo')
        return { firstname = 'Quinn', lastname = 'Bailey' }
    end,
}

local framework

MySQL = {
    query = {
        await = function(sql)
            if framework == 'qbx' then
                assert(sql:find('p.firstName AS firstname', 1, true))
                assert(sql:find('p.lastName AS lastname', 1, true))
                assert(sql:find('LEFT JOIN users u ON u.userId = p.userId', 1, true))
                return {
                    { citizenid = 'qbx-cid', license = 'license:qbx', firstname = 'Alice', lastname = 'Carter' },
                }
            end

            if framework == 'qb' then
                assert(sql:find('charinfo', 1, true))
                return {
                    { citizenid = 'qb-cid', license = 'license:qb', charinfo = 'qb-charinfo' },
                }
            end

            assert(framework == 'esx')
            assert(sql:find('firstname, lastname', 1, true))
            return {
                { citizenid = 'esx-cid', firstname = 'Elliot', lastname = 'Stone' },
            }
        end,
    },
}

local store = require 'server.migrate.store'

framework = 'qbx'
local qbx = store.loadRoster(framework)
assert(qbx.namesByCid['qbx-cid'] == 'Alice Carter')
assert(qbx.licenseToCids['license:qbx'][1] == 'qbx-cid')

framework = 'qb'
local qb = store.loadRoster(framework)
assert(qb.namesByCid['qb-cid'] == 'Quinn Bailey')

framework = 'esx'
local esx = store.loadRoster(framework)
assert(esx.namesByCid['esx-cid'] == 'Elliot Stone')

print('migrate_identity_names_spec: ok')
