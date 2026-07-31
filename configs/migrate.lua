-- lb-phone -> sd-phone data migration. When a server switches from lb-phone to sd-phone this
-- carries each player's essentials across on first boot, so people keep their phone instead of
-- starting over: phone number + lock passcode, contacts, call history, blocked numbers, SMS
-- threads (incl. groups), photos + albums, and notes.
--
-- It is idempotent and non-destructive. A marker row (phone_migrations) stops it running twice,
-- every write is INSERT IGNORE / fill-only, and a player who already has sd-phone data is never
-- overwritten. Safe to leave enabled forever: once there is nothing left to import it is a cheap
-- no-op. The join is lb-phone's phone owner id -> framework citizenid, and each player's lb-phone
-- number is adopted as their sd-phone number so every contact / thread / call log still lines up.
return {
    -- Keep the LB archive available for manual recovery without importing it automatically.
    -- A manual import can still be started with the `sdphone:migrate` server-console command.
    enabled = true,

    -- Archived lb-phone tables are renamed from phone_* to lb_phone_* during the cutover.
    sourcePrefix = 'lb_phone_',

    -- How an lb-phone phone owner id maps to an sd-phone citizenid:
    --   'auto'      match owner_id against known citizenids first, else treat it as a license
    --   'citizenid' owner_id is already the citizenid (skip the license fallback)
    --   'license'   owner_id is a license; always map through the players table
    -- 'auto' is right for almost everyone (it covers both lb-phone identifier setups).
    identifierMode = 'citizenid',

    -- Dry run: count everything and log the plan, but write nothing. Run the console command with
    -- `sdphone:migrate dry` for a preview without flipping this.
    dryRun = false,

    -- Per-domain switches, if you want to import only some of it. `numbers` must stay on: every
    -- other domain is keyed off the number -> citizenid resolution it establishes.
    --
    -- `reactions` needs `messages` (it attaches to the messages that porter writes), and
    -- `sessions` needs `photogram` (it links to the accounts that porter creates). Birdy owns
    -- both the Twitter content import and its active account sessions.
    --
    -- lb-phone passwords are bcrypt hashed and cannot be converted to sd-phone's hasher. Active
    -- sessions are restored, and each resolved account receives a fresh password in Passwords so
    -- its owner can sign back in later.
    domains = {
        numbers    = true,
        contacts   = true,
        blocked    = true,
        calls      = true,
        messages   = true,
        photos     = true,
        notes      = true,
        -- wallpaper, theme, clock format, ringtones, volumes, home-screen layout
        settings   = true,
        -- message reactions; needs `messages`
        reactions  = true,
        -- Instagram accounts, posts, comments, likes, follows, stories and DMs
        photogram  = true,
        -- Twitter accounts, tweets, likes, reposts, follows, DMs, alerts and active login
        birdy      = true,
        -- mail accounts and their received messages
        mail       = true,
        -- wallet transaction history
        wallet     = true,
        -- voice memo recordings
        voicememos = true,
        -- keeps players signed into migrated Photogram accounts; runs last
        sessions   = true,
    },
}
