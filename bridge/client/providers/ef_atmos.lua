local RESOURCE <const> = 'ef_atmos'
local FORECAST_REFRESH_MS <const> = 30000

---@type table Everfall atmosphere provider. ef_atmos publishes its live weather and time through
---global statebags, so phone reads never need an extra callback or polling resource boundary.
local atmos = {}

---@type table|nil Latest authoritative ef_atmos forecast payload.
local currentForecast
---@type integer Game timer when the forecast payload arrived.
local forecastReceivedAt = 0
---@type number Remaining active-event seconds when the payload arrived.
local forecastRemainingAtReceipt = 0
---@type number Server epoch supplied with the payload.
local forecastServerTimeAtReceipt = 0

---@return boolean
function atmos.active()
    return GetResourceState(RESOURCE) == 'started'
end

---@param forecast any
---@return boolean accepted
local function cacheForecast(forecast)
    if type(forecast) ~= 'table' or type(forecast.weatherEvents) ~= 'table' then return false end
    currentForecast = forecast
    forecastReceivedAt = GetGameTimer()
    forecastRemainingAtReceipt = math.max(0, tonumber(forecast.currentEventRemainingSeconds) or 0)
    forecastServerTimeAtReceipt = math.max(0, tonumber(forecast.serverTime) or 0)
    return true
end

---@return table|nil forecast
local function fetchForecast()
    if not atmos.active() then return nil end
    local succeeded, forecast = pcall(function()
        return lib.callback.await('ef_atmos:server:fetchWeatherForecast', false)
    end)
    if succeeded then cacheForecast(forecast) end
    return currentForecast
end

---@param forecast table|nil
---@return table|nil forecast
local function refreshForecastClock(forecast)
    if not forecast then return nil end

    local elapsedSeconds = math.max(0, GetGameTimer() - forecastReceivedAt) / 1000
    if forecast.isWeatherPaused ~= true then
        forecast.currentEventRemainingSeconds = math.max(0, forecastRemainingAtReceipt - elapsedSeconds)
    end
    forecast.serverTime = forecastServerTimeAtReceipt + math.floor(elapsedSeconds)
    return forecast
end

---@return { current: string, next: string, time: { hour: integer, minute: integer }, forecast: table|nil }
function atmos.read()
    local forecast = currentForecast
    if not forecast or (GetGameTimer() - forecastReceivedAt) >= FORECAST_REFRESH_MS then
        forecast = fetchForecast()
    end
    forecast = refreshForecastClock(forecast)
    local current = type(GlobalState.currentWeatherEvent) == 'string'
        and GlobalState.currentWeatherEvent
        or 'CLEAR'
    local events = forecast and forecast.weatherEvents
    local nextEvent = type(events) == 'table' and events[2]
    local nextWeather = type(nextEvent) == 'table' and type(nextEvent.weatherType) == 'string'
        and nextEvent.weatherType or current
    local currentTime = GlobalState.currentTime
    local hour = type(currentTime) == 'table' and tonumber(currentTime.hour) or GetClockHours()
    local minute = type(currentTime) == 'table' and tonumber(currentTime.minute) or GetClockMinutes()

    return {
        current = current,
        next = nextWeather,
        time = { hour = math.floor(hour or 0), minute = math.floor(minute or 0) },
        forecast = forecast,
    }
end

---@param callback fun()
function atmos.onChange(callback)
    AddStateBagChangeHandler('currentWeatherEvent', 'global', function() callback() end)
    AddStateBagChangeHandler('currentWeatherChange', 'global', function() callback() end)
    AddStateBagChangeHandler('currentTime', 'global', function() callback() end)
    RegisterNetEvent('ef_atmos:Client:SyncWeatherCycle', function(forecast)
        if cacheForecast(forecast) then callback() end
    end)
    RegisterNetEvent('ef_atmos:Client:UpdateWeatherForecast', function(forecast)
        if cacheForecast(forecast) then callback() end
    end)
end

return atmos
