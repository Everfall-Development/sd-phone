local function read(path)
    local file = assert(io.open(path, 'r'))
    local value = file:read('*a')
    file:close()
    return value
end

local race = read('client/racing/race.lua')
local racegen = read('server/racing/racegen.lua')
local races = read('server/racing/races.lua')
local init = read('server/racing/init.lua')

-- The server filters unready racers before opening a run. A racer who moves out of position before
-- the flag drops can still withdraw through the registered client-side preflight; solo trials skip
-- that board-only check because beginTrial already validates the start line and driver seat.
assert(race:find("if not data.trial then", 1, true))
assert(race:find("boards().ineligible", 1, true))
assert(race:find("sd-phone:server:racing:notStarted", 1, true))
assert(init:find("register('notStarted'", 1, true))
assert(racegen:find("if race.notReady and race.notReady[cid]", 1, true))
assert(racegen:find("skipped[#skipped + 1]", 1, true))
assert(racegen:find("members[#members + 1] = cid", 1, true))
assert(races:find("refundSkipped(race)", 1, true))
assert(races:find("races.beginRun(race, race.members or {}, now)", 1, true))

print('racing_start_spec: ok')
