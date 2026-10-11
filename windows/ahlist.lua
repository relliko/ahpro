--[[
* The auction house item list over the game's. It stays up while the item menu, the price box or the
* price history has focus; picking a row from it while the item menu is up closes that menu the way
* it closes itself and opens the row. The item tooltip is facelift's (windows/iteminfo, showing the
* row under the mouse). The category menus it was picked from are hidden (the game keeps drawing
* them at the right, where the item menu goes); Escape brings them back.
--]]
local AH = require('data.ahmenus');

local suppress = {}; -- the item tooltip isn't hidden: windows/iteminfo stands in for it
for _, name in ipairs(AH.menus) do
    suppress[#suppress + 1] = name;
end

return {
    id = 'ahlist', imgui = 'facelift_auclist', name = 'Auction list',
    toggle = 'auclist', title = 'Auction list', off_with = 'ahone', -- (windows/ahbrowse instead) fallback = 'the game\'s own list shows',
    parts = {
        { name = 'list', menus = { 'auclist' }, adapter = 'auclist', show = 'open', through = { auc3 = 'close_obj' } },
    },
    suppress = suppress,
    look = 'ah', -- (the auction house's theme: ui/theme AREAS)
    pane = 'ahlist',
    layout = { from = 'menu', w = { 'from', min = 340 }, h = 0, clamp = true, auto = true, z = 'under' },
    options = {
        rows = { label = 'Rows shown (0: as the game)', default = 0, min = 0, max = 40 },
    },
};
