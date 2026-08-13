local function read(path)
    local file = assert(io.open(path, 'r'))
    local value = file:read('*a')
    file:close()
    return value
end

local race = read('client/racing/race.lua')
local racegen = read('server/racing/racegen.lua')
local races = read('server/racing/races.lua')

-- The server filters out unready racers before it opens a run. The client receives raceStart only
-- after that decision, so it must not call a second, unregistered preflight contract.
assert(race:find("boards().ineligible", 1, true) == nil)
assert(race:find("sd-phone:server:racing:notStarted", 1, true) == nil)
assert(racegen:find("if race.notReady and race.notReady[cid]", 1, true))
assert(racegen:find("skipped[#skipped + 1]", 1, true))
assert(racegen:find("members[#members + 1] = cid", 1, true))
assert(races:find("refundSkipped(race)", 1, true))
assert(races:find("races.beginRun(race, race.members or {}, now)", 1, true))

print('racing_start_spec: ok')
