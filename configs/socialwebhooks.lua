-- Public social-post announcements. The Discord webhook secret stays in the server-only
-- configs/server/apikeys.lua as SocialWebhook, with sd_phone_social_webhook as a convar fallback.
return {
    Enabled = true,
    Convar = 'sd_phone_social_webhook',

    Quip = {
        Username = 'Quip',
        Avatar = 'https://files.jellyton.me/ShareX/2024/01/Quip.jpg',
        Color = 5793266,
    },

    Kaleido = {
        Username = 'Kaleido',
        Avatar = 'https://files.jellyton.me/ShareX/2024/01/Kaleido.jpg',
        Color = 15022389,
    },
}
