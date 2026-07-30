local RESOURCE <const> = 'ef_management'

---@type table Everfall management provider. The authoritative QBox multi-job roster lives in
---player_groups, which includes inactive jobs that the legacy players.job JSON query misses.
local management = {}

---@return boolean
function management.active()
    return GetResourceState(RESOURCE) == 'started'
end

---@param jobName string
---@return { citizenid: string, name: string, grade: number }[]|nil employees nil on query failure
function management.listEmployees(jobName)
    if not management.active() then return nil end

    local succeeded, rows = pcall(function()
        return MySQL.query.await([[
            SELECT players.citizenid, players.charinfo, player_groups.grade
            FROM players
            INNER JOIN player_groups ON player_groups.citizenid = players.citizenid
            WHERE player_groups.`group` = ?
        ]], { jobName })
    end)
    if not succeeded or type(rows) ~= 'table' then return nil end

    local employees = {}
    for _, row in ipairs(rows) do
        local name = row.citizenid
        local decoded, charinfo = pcall(json.decode, row.charinfo)
        if decoded and type(charinfo) == 'table' then
            local fullName = ('%s %s'):format(charinfo.firstname or '', charinfo.lastname or '')
                :gsub('^%s+', '')
                :gsub('%s+$', '')
            if fullName ~= '' then name = fullName end
        end

        employees[#employees + 1] = {
            citizenid = row.citizenid,
            name = name,
            grade = tonumber(row.grade) or 0,
        }
    end
    return employees
end

return management
