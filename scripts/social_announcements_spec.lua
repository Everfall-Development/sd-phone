package.path = './?.lua;./?/init.lua;' .. package.path

local encodedPayload
local requests = {}
local pushes = {}
local responseStatus = 204
local timers = 0

package.preload['configs.config'] = function()
    return {
        ApiKeys = {
            SocialWebhook = 'https://discord.com/api/webhooks/1/token',
        },
        SocialWebhooks = {
            Enabled = true,
            Convar = 'sd_phone_social_webhook',
            Quip = {
                Username = 'Quip',
                Avatar = 'https://example.com/quip.png',
                Color = 123,
            },
            Kaleido = {
                Username = 'Kaleido',
                Avatar = 'https://example.com/kaleido.png',
                Color = 456,
            },
        },
    }
end

package.preload['server.util'] = function()
    return {
        pushMany = function(event, targets, payload)
            pushes[#pushes + 1] = { event = event, targets = targets, payload = payload }
        end,
    }
end

json = {
    encode = function(payload)
        encodedPayload = payload
        return 'encoded-payload'
    end,
    decode = function()
        return { retry_after = 0.25 }
    end,
}

exports = {
    ['sd-phone'] = {
        hasPhone = function(_, source)
            return source == 2
        end,
    },
}

function GetConvar(_, fallback)
    return fallback
end

function GetPlayers()
    return { '1', '2', '3' }
end

function PerformHttpRequest(url, callback, method, body, headers)
    requests[#requests + 1] = {
        url = url,
        method = method,
        body = body,
        headers = headers,
    }
    callback(responseStatus, responseStatus == 429 and '{"retry_after":0.25}' or '')
end

function SetTimeout(_, callback)
    timers = timers + 1
    callback()
end

local announcements = require 'server.socialannouncements'

announcements.quip({
    id = 'post-1',
    source = 1,
    username = 'casey',
    displayName = 'Casey',
    body = 'Hello Everfall',
    images = { 'https://example.com/one.png', 'javascript:bad', 'https://example.com/two.png' },
})

assert(#pushes == 1)
assert(pushes[1].event == 'sd-phone:client:notify')
assert(#pushes[1].targets == 1 and pushes[1].targets[1] == 2)
assert(pushes[1].payload.title == 'New Quip Post')
assert(pushes[1].payload.quietInApp == nil)
assert(pushes[1].payload.link['birdy:openPostId'] == 'post-1')
assert(#requests == 1 and requests[1].method == 'POST')
assert(encodedPayload.username == 'Quip')
assert(encodedPayload.allowed_mentions.parse[1] == nil)
assert(encodedPayload.embeds[1].author.name == 'Casey (@casey)')
assert(encodedPayload.embeds[1].image.url == 'https://example.com/one.png')
assert(encodedPayload.embeds[2].image.url == 'https://example.com/two.png')

announcements.kaleido({
    id = 'private-1',
    username = 'private_account',
    images = { 'https://example.com/private.png' },
    private = true,
})
assert(#requests == 1, 'private Kaleido posts must not reach the public webhook')

announcements.kaleido({
    id = 'public-1',
    username = 'lens',
    images = { 'https://example.com/public.png' },
    caption = 'A public post',
    location = 'Legion Square',
    private = false,
})
assert(#requests == 2)
assert(encodedPayload.username == 'Kaleido')
assert(encodedPayload.embeds[1].author.name == '@lens')
assert(encodedPayload.embeds[1].fields[1].value == 'Legion Square')

responseStatus = 500
announcements.kaleido({
    id = 'retry-1',
    username = 'lens',
    images = { 'https://example.com/retry.png' },
    private = false,
})
assert(#requests == 5, 'a retryable Discord failure must make three bounded attempts')
assert(timers == 2)

print('social_announcements_spec: ok')
