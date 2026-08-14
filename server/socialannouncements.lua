---@type table sd-phone config root: public social webhook presentation + server-only secret.
local config = require 'configs.config'

---@type table Shared social announcement module.
local announcements = {}

local settings = config.SocialWebhooks or {}
local MAX_ATTEMPTS = 3
local DEFAULT_RETRY_MS = 1000
local MAX_RETRY_MS = 10000

---@param value any
---@param maxLength integer
---@return string
local function boundedString(value, maxLength)
    if type(value) ~= 'string' then return '' end
    value = value:gsub('[%z\1-\8\11\12\14-\31]', '')
    if #value > maxLength then return value:sub(1, maxLength) end
    return value
end

---@param value any
---@return string|nil
local function httpUrl(value)
    local url = boundedString(value, 512)
    if url:match('^https?://') then return url end
    return nil
end

---@return string|nil
local function webhookUrl()
    if settings.Enabled ~= true then return nil end
    local keys = config.ApiKeys
    local configured = type(keys) == 'table' and keys.SocialWebhook or nil
    if type(configured) ~= 'string' or configured == '' then
        configured = GetConvar(settings.Convar or 'sd_phone_social_webhook', '')
    end
    if type(configured) ~= 'string' then return nil end
    if configured:match('^https://discord%.com/api/webhooks/') then return configured end
    if configured:match('^https://discordapp%.com/api/webhooks/') then return configured end
    return nil
end

---@param responseBody string|nil
---@param attempt integer
---@return integer
local function retryDelay(responseBody, attempt)
    local fallback = DEFAULT_RETRY_MS * attempt
    if type(responseBody) ~= 'string' or responseBody == '' then return fallback end
    local decodedOk, decoded = pcall(json.decode, responseBody)
    if not decodedOk or type(decoded) ~= 'table' then return fallback end
    local requested = tonumber(decoded.retry_after)
    if not requested then return fallback end
    if requested < 50 then requested = requested * 1000 end
    return math.min(math.max(math.floor(requested), 250), MAX_RETRY_MS)
end

---@param url string
---@param encoded string
---@param label string
---@param attempt integer
local function sendAttempt(url, encoded, label, attempt)
    PerformHttpRequest(url, function(status, responseBody)
        status = tonumber(status) or 0
        if status >= 200 and status < 300 then return end

        local retryable = status == 0 or status == 429 or status >= 500
        if retryable and attempt < MAX_ATTEMPTS then
            local delay = retryDelay(responseBody, attempt)
            SetTimeout(delay, function()
                sendAttempt(url, encoded, label, attempt + 1)
            end)
            return
        end

        print(('^1[sd-phone]^0 %s Discord announcement failed with HTTP %s after %d attempt(s).')
            :format(label, tostring(status), attempt))
    end, 'POST', encoded, { ['Content-Type'] = 'application/json' })
end

---@param account table
---@param label string
---@param author string
---@param description string
---@param images string[]
---@param location string|nil
local function sendDiscord(account, label, author, description, images, location)
    local url = webhookUrl()
    if not url then return end

    local first = {
        author = { name = author },
        description = description ~= '' and description or '*Shared a photo*',
        color = tonumber(account.Color) or 5793266,
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        footer = { text = ('Everfall • %s'):format(label) },
    }
    if images[1] then first.image = { url = images[1] } end
    if location then first.fields = { { name = 'Location', value = location, inline = true } } end

    local embeds = { first }
    for index = 2, math.min(#images, 3) do
        embeds[#embeds + 1] = {
            color = tonumber(account.Color) or 5793266,
            image = { url = images[index] },
        }
    end

    local encodedOk, encoded = pcall(json.encode, {
        username = boundedString(account.Username, 80),
        avatar_url = httpUrl(account.Avatar),
        allowed_mentions = { parse = {} },
        embeds = embeds,
    })
    if not encodedOk or type(encoded) ~= 'string' then
        print(('^1[sd-phone]^0 Could not encode the %s Discord announcement.'):format(label))
        return
    end
    sendAttempt(url, encoded, label, 1)
end

---@param raw any
---@return string[]
local function imageUrls(raw)
    if type(raw) ~= 'table' then return {} end
    local images = {}
    for index = 1, math.min(#raw, 3) do
        local url = httpUrl(raw[index])
        if url then images[#images + 1] = url end
    end
    return images
end

---@param post table
local function notifyQuip(post)
    local targets = {}
    local authorSource = tonumber(post.source)
    for _, rawSource in ipairs(GetPlayers()) do
        local source = tonumber(rawSource)
        if source and source ~= authorSource then
            local resolved, hasPhone = pcall(function()
                return exports['sd-phone']:hasPhone(source)
            end)
            if resolved and hasPhone then targets[#targets + 1] = source end
        end
    end
    if not targets[1] then return end

    local displayName = boundedString(post.displayName, 32)
    local handle = boundedString(post.username, 15)
    local preview = boundedString(post.body, 120)
    if preview == '' then preview = 'Shared a photo' end
    local actor = displayName ~= '' and displayName or ('@' .. handle)
    local images = imageUrls(post.images)

    require('server.util').pushMany('sd-phone:client:notify', targets, {
        app = 'birdy',
        appId = 'birdy',
        title = 'New Quip Post',
        body = ('%s: %s'):format(actor, preview),
        image = images[1],
        time = 'now',
        link = { ['birdy:openPostId'] = post.id },
    })
end

---@param post any
function announcements.quip(post)
    if type(post) ~= 'table' or type(post.id) ~= 'string' then return end
    notifyQuip(post)

    local account = settings.Quip or {}
    local displayName = boundedString(post.displayName, 32)
    local handle = boundedString(post.username, 15)
    local author = displayName ~= '' and ('%s (@%s)'):format(displayName, handle) or ('@' .. handle)
    sendDiscord(account, 'Quip', author, boundedString(post.body, 280), imageUrls(post.images), nil)
end

---@param post any
function announcements.kaleido(post)
    if type(post) ~= 'table' or type(post.id) ~= 'string' or post.private == true then return end
    local handle = boundedString(post.username, 64)
    local location = boundedString(post.location, 120)
    local account = settings.Kaleido or {}
    sendDiscord(
        account,
        'Kaleido',
        '@' .. handle,
        boundedString(post.caption, 2200),
        imageUrls(post.images),
        location ~= '' and location or nil
    )
end

return announcements
