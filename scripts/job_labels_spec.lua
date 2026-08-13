package.path = './?.lua;./?/init.lua;' .. package.path

local function loadJob(framework, qbxGetJob)
    package.preload['bridge.shared.framework'] = function() return framework end
    package.preload['bridge.server.player'] = function() return { get = function() end } end
    package.loaded['bridge.shared.framework'] = nil
    package.loaded['bridge.server.player'] = nil
    package.loaded['bridge.server.job'] = nil

    exports = {
        qbx_core = {
            GetJob = function(_, jobName)
                if qbxGetJob then return qbxGetJob(jobName) end
            end,
        },
    }

    return require 'bridge.server.job'
end

local qbx = loadJob({ name = 'qbx', qb = true }, function(jobName)
    if jobName == 'taxi_tuggers' then return { label = "Tugger's Taxis" } end
end)
assert(qbx.getLabel('taxi_tuggers') == "Tugger's Taxis")
assert(qbx.getLabel('missing') == nil)

local qb = loadJob({
    name = 'qb',
    qb = true,
    core = { Shared = { Jobs = { taxi = { label = 'Taxi Service' } } } },
})
assert(qb.getLabel('taxi') == 'Taxi Service')

local esx = loadJob({
    name = 'esx',
    qb = false,
    core = {
        GetJobs = function()
            return { unemployed = { label = 'Unemployed' } }
        end,
    },
})
assert(esx.getLabel('unemployed') == 'Unemployed')

local protected = loadJob({ name = 'qbx', qb = true }, function()
    error('provider unavailable')
end)
assert(protected.getLabel('taxi') == nil)
assert(protected.getLabel('') == nil)

print('job_labels_spec: ok')
