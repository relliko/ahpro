--[[
* Sales Status (the first auction menu's Sales Status, once the server answers): your listings where
* the game's list was, with their prices and where they stand. It stays up under a listing's small
* menu; picking another listing from it closes that menu the game's way first. The game's item
* info panel and the auction menus it keeps at the right are hidden, as with the auction list.
--]]
local AH = require('data.ahmenus');

local suppress = {}; -- the item tooltip isn't hidden: windows/iteminfo stands in for it
for _, name in ipairs(AH.menus) do
    suppress[#suppress + 1] = name;
end

return {
    id = 'ahsales', imgui = 'facelift_aucsales', name = 'Sales status',
    toggle = 'auclist', off_with = 'ahone', -- (windows/ahbrowse instead)
    parts = {
        { name = 'list', menus = { 'auclist' }, adapter = 'aucsales', show = 'open', through = { auc4 = 'close_obj' } },
    },
    suppress = suppress,
    look = 'ah', -- (the auction house's theme: ui/theme AREAS)
    pane = 'ahsales',
    layout = { from = 'menu', w = { 'from', min = 340 }, h = 0, clamp = true, auto = true, z = 'under' },
};
