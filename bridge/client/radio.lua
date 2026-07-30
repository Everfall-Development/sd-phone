local EVERFALL <const> = 'ef_radio'

---@type table Radio provider. ef_radio owns channel subscription state when present; pma-voice is
---the fallback and still owns the local output volume in both paths.
local radio = {}

---@return string|nil
function radio.activeSystem()
    if GetResourceState(EVERFALL) == 'started' then return EVERFALL end
    if GetResourceState('pma-voice') == 'started' then return 'pma-voice' end
    return nil
end

---@param volume number
---@return boolean
function radio.setVolume(volume)
    if GetResourceState('pma-voice') ~= 'started' then return false end
    local succeeded, result = pcall(function()
        return exports['pma-voice']:setRadioVolume(volume)
    end)
    return succeeded and result ~= false
end

---@param frequency number user-facing channel, including tenths
---@param enabled boolean
---@return boolean
function radio.setChannel(frequency, enabled)
    if radio.activeSystem() == EVERFALL then
        local channel = enabled and frequency or 0
        local succeeded, result = pcall(function()
            return lib.callback.await('EF-Radio:Server:SetRadioChannel', false, channel)
        end)
        return succeeded and type(result) == 'table' and result.success == true
    end

    if GetResourceState('pma-voice') ~= 'started' then return false end
    local channel = enabled and math.floor(frequency * 10 + 0.5) or 0
    local succeeded, result = pcall(function()
        return exports['pma-voice']:setRadioChannel(channel)
    end)
    return succeeded and result ~= false
end

return radio
