---@type string[] Every built-in sd-phone app id shipped on the home screen. Custom apps may not
---claim one of these, and the lb-phone compat layer maps foreign app names onto them.
local BUILTIN = {
    'photos', 'bank', 'settings', 'clock', 'messages', 'phone', 'calendar', 'mail', 'weather',
    'maps', 'music', 'stocks', 'ryde', 'notes', 'voicememos', 'health', 'compass', 'groups',
    'services', 'pages', 'review', 'marketplace', 'radio', 'darkchat', 'cherry', 'photogram',
    'garages', 'homes', 'calculator', 'passwords', 'cookie', 'wordle', 'flappy', 'blocks',
    'blackjack', 'climber', 'connectfour', 'chess', 'battleship', 'vibez',
    'weazelnews', 'streaks', 'birdy', 'mdt', 'racing', 'appstore', 'camera',
}

---@type table<string, true> Set form of BUILTIN for O(1) membership tests.
local set = {}
for i = 1, #BUILTIN do set[BUILTIN[i]] = true end

---@type table Shared config-derived app capability predicate.
local appcaps = require 'shared.appcaps'

---Whether an app is switched on in configs/apps.lua. Background work belonging to a single app is
---gated on this, so a disabled app costs nothing on anyone's game thread.
---@param id string app id as configs/apps.lua names it
---@return boolean enabled
local function enabled(id)
    return appcaps.enabled(id)
end

return { list = BUILTIN, set = set, enabled = enabled }
