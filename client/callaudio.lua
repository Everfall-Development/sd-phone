---@type table sd-phone config root (configs/config.lua).
local config = require 'configs.config'

---@type table Call-audio config (configs/callaudio.lua).
local cfg = type(config.CallAudio) == 'table' and config.CallAudio or {}

---@type table<string, table> Line name ('handset', 'speaker', ...) -> its tuning block.
local LINES = {}
for name, line in pairs(cfg.Lines or {}) do
    if type(line) == 'table' then LINES[name:lower()] = line end
end

---Audio submixes are a per-GAME-SESSION engine resource: the pool is small, there is no native to
---destroy one, and a resource restart would otherwise burn a fresh set off it every time - four
---restarts an hour is all it takes to run a dev server out and start getting -1 back. The ids are
---parked on the player's own state bag, which outlives this resource, so a restart reuses the
---submixes it already made. (A full reconnect clears the bag and does leak the old set; nothing
---client-side can reclaim them, and that is the same deal every submix-using resource takes.)
---@type string
local CACHE_KEY = 'sdPhoneCallSubmixes'

---@type table<string, number> Line name -> submix id, once built.
local submixes = {}

---@type boolean True while a payphone booth is carrying the call.
local onPayphone = false
---@type boolean True while speakerphone is on.
local onSpeaker = false
---@type boolean True while the call is a FaceTime.
local onVideo = false
---@type string|nil Line currently handed to pma-voice, so an unchanged mode costs nothing.
local activeLine = nil

---Reads a tuning value, falling back when a config block leaves it out.
---@param line table tuning block
---@param key string
---@param fallback number
---@return number
local function param(line, key, fallback)
    local value = tonumber(line[key])
    if not value then return fallback end
    return value + 0.0
end

---Builds one line's submix: a radio-FX chain seeded with the engine default, then tuned to the
---band and drive that make this particular earpiece.
---@param name string line name, for the submix's engine-side label
---@param line table tuning block
---@return number|nil submix id, nil when the engine pool is exhausted
local function buildLine(name, line)
    local id = CreateAudioSubmix(('sd-phone:%s'):format(name))
    if not id or id < 0 then return nil end

    -- GetHashKey, not joaat: these natives want the signed 32-bit hash, and joaat hands back the
    -- unsigned one.
    SetAudioSubmixEffectRadioFx(id, 0)
    SetAudioSubmixEffectParamInt(id, 0, GetHashKey('default'), 1)

    SetAudioSubmixEffectParamFloat(id, 0, GetHashKey('freq_low'),    param(line, 'FreqLow',     300.0))
    SetAudioSubmixEffectParamFloat(id, 0, GetHashKey('freq_hi'),     param(line, 'FreqHigh',   3400.0))
    SetAudioSubmixEffectParamFloat(id, 0, GetHashKey('o_freq_lo'),   param(line, 'OutFreqLow',  280.0))
    SetAudioSubmixEffectParamFloat(id, 0, GetHashKey('o_freq_hi'),   param(line, 'OutFreqHigh', 3800.0))
    SetAudioSubmixEffectParamFloat(id, 0, GetHashKey('fudge'),       param(line, 'Fudge',         0.0))
    SetAudioSubmixEffectParamFloat(id, 0, GetHashKey('rm_mod_freq'), param(line, 'ModFreq',       0.0))
    SetAudioSubmixEffectParamFloat(id, 0, GetHashKey('rm_mix'),      param(line, 'ModMix',        0.0))

    local volume = type(line.Volume) == 'table' and line.Volume or {}
    local left  = param(volume, 'Left',  1.0)
    local right = param(volume, 'Right', 1.0)
    SetAudioSubmixOutputVolumes(id, 0, left, right, left, right, 1.0, 1.0)
    AddAudioSubmixOutput(id, 0)

    return id
end

---Builds every configured line once per game session, reusing whatever a previous run of this
---resource already left on the state bag.
local function build()
    local cached = LocalPlayer.state[CACHE_KEY]
    if type(cached) == 'table' then
        for name, id in pairs(cached) do
            if type(id) == 'number' and id >= 0 then submixes[name] = id end
        end
    end

    local built = false
    for name, line in pairs(LINES) do
        if not submixes[name] then
            local id = buildLine(name, line)
            if id then
                submixes[name] = id
                built = true
            else
                lib.print.warn(('[sd-phone] Out of audio submixes; call line %q falls back to the default.'):format(name))
            end
        end
    end

    if built then LocalPlayer.state:set(CACHE_KEY, submixes, false) end
end

---Which line the call is on right now. A FaceTime outranks everything (the picture is the point,
---and it is the only wideband leg); a booth outranks the speaker toggle it does not offer.
---@return string|nil
local function resolve()
    if onVideo    and submixes.video    then return 'video' end
    if onPayphone and submixes.payphone then return 'payphone' end
    if onSpeaker  and submixes.speaker  then return 'speaker' end
    if submixes.handset then return 'handset' end
    return nil
end

---Hands the resolved line to pma-voice, which applies it to every call-channel voice this client
---hears. Idempotent.
---
---pma-voice reads its call submix when a party STARTS transmitting, so a mid-call switch (speaker
---on, video answered) lands on the other side's next utterance rather than mid-word - which is the
---right seam to change an earpiece on anyway.
local function sync()
    local line = resolve()
    if line == activeLine then return end
    activeLine = line
    if not line then return end
    pcall(function() exports['pma-voice']:setEffectSubmix('call', submixes[line]) end)
end

local callaudio = {}

---Speakerphone toggled.
---@param on boolean
function callaudio.setSpeaker(on)
    onSpeaker = on == true
    sync()
end

---FaceTime picture came up or went away.
---@param on boolean
function callaudio.setVideo(on)
    onVideo = on == true
    sync()
end

---A street booth took the call, or gave it back.
---@param on boolean
function callaudio.setPayphone(on)
    onPayphone = on == true
    sync()
end

---Call over: back to the plain handset line, ready for the next one.
function callaudio.reset()
    onSpeaker  = false
    onVideo    = false
    onPayphone = false
    sync()
end

if cfg.Enabled ~= false and next(LINES) then
    build()
    sync()

    -- pma-voice rebuilds submixIndicies from scratch on start, dropping our override with it.
    AddEventHandler('onClientResourceStart', function(resource)
        if resource ~= 'pma-voice' then return end
        activeLine = nil
        sync()
    end)
end

return callaudio
