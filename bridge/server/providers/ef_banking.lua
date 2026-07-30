---@type table Player bridge (bridge.server.player): source -> citizenid resolution.
local player = require 'bridge.server.player'

local RESOURCE <const> = 'ef_banking'

---@type table Everfall banking provider. All mutations go through ef_banking so account locks,
---holds, ledgers, projections, and offline characters stay inside its authoritative transaction
---boundary.
local banking = {}

---@return boolean
function banking.active()
    return GetResourceState(RESOURCE) == 'started'
end

---@param target number|string player source or citizenid
---@return string|nil citizenid
local function resolveIdentifier(target)
    if type(target) == 'string' and target ~= '' then return target end
    if type(target) == 'number' then return player.getIdentifier(target) end
    return nil
end

---@param target number|string player source or citizenid
---@param amount number
---@param reason? string
---@return boolean
function banking.addMoney(target, amount, reason)
    local citizenid = resolveIdentifier(target)
    if not citizenid or not banking.active() then return false end

    local succeeded, applied = pcall(function()
        return exports.ef_banking:AddPlayerMoney(
            citizenid,
            'bank',
            amount,
            reason or 'Phone credit',
            { channel = 'sd-phone' },
            'sd-phone'
        )
    end)
    return succeeded and applied == true
end

---@param target number|string player source or citizenid
---@param amount number
---@param reason? string
---@return boolean
function banking.removeMoney(target, amount, reason)
    local citizenid = resolveIdentifier(target)
    if not citizenid or not banking.active() then return false end

    local succeeded, applied = pcall(function()
        return exports.ef_banking:RemovePlayerMoney(
            citizenid,
            'bank',
            amount,
            reason or 'Phone debit',
            { channel = 'sd-phone' },
            'sd-phone'
        )
    end)
    return succeeded and applied == true
end

---ef_banking projects its authoritative personal account into QBox PlayerData, which is the
---fastest live read for a connected phone owner.
---@param source number player source
---@return number
function banking.getBalance(source)
    local frameworkPlayer = player.get(source)
    local balances = frameworkPlayer and frameworkPlayer.PlayerData and frameworkPlayer.PlayerData.money
    return balances and tonumber(balances.bank) or 0
end

---@param citizenid string
---@param amount number
---@param reason? string
---@return boolean
function banking.addOffline(citizenid, amount, reason)
    return banking.addMoney(citizenid, amount, reason or 'Offline phone credit')
end

---@param society string bare Everfall business key
---@return number|nil
function banking.getSocietyBalance(society)
    if not banking.active() then return nil end
    local succeeded, balance = pcall(function()
        return exports.ef_banking:GetSocietyBalance(society)
    end)
    if succeeded and type(balance) == 'number' then return balance end
    return nil
end

---@param society string bare Everfall business key
---@param amount number
---@param reason? string
---@return boolean
function banking.addSocietyMoney(society, amount, reason)
    if not banking.active() then return false end
    local succeeded, applied = pcall(function()
        return exports.ef_banking:AddSocietyMoney(
            society,
            amount,
            reason or 'Phone society credit',
            { channel = 'sd-phone' },
            'sd-phone'
        )
    end)
    return succeeded and applied == true
end

---@param society string bare Everfall business key
---@param amount number
---@param reason? string
---@return boolean
function banking.removeSocietyMoney(society, amount, reason)
    if not banking.active() then return false end
    local succeeded, applied = pcall(function()
        return exports.ef_banking:RemoveSocietyMoney(
            society,
            amount,
            reason or 'Phone society debit',
            { channel = 'sd-phone' },
            'sd-phone'
        )
    end)
    return succeeded and applied == true
end

return banking
