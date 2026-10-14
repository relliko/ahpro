--[[
* The Sell flow's item picker (the first auction menu's Sell: your inventory, "Select an item.")
* where the game's list was: a filter, icons and counts, what can't be sold faint. Picking an item
* is the game's own Enter on it (its price history and the sale price box come next). The item
* tooltip is facelift's (windows/iteminfo); the auction menus at the right are hidden.
--]]
local AH = require('data.ahmenus');

local suppress = {}; -- the item tooltip isn't hidden: windows/iteminfo stands in for it
for _, name in ipairs(AH.menus) do
    suppress[#suppress + 1] = name;
end

return {
    id = 'ahsellpick', imgui = 'facelift_sellpick', name = 'Sell: pick an item',
    toggle = 'auclist', off_with = 'ahone', -- (windows/ahbrowse instead)
    parts = {
        { name = 'list', menus = { 'inventor' }, adapter = 'sellpick' },
    },
    suppress = suppress,
    unless_lingering = { 'ahhisto' }, -- (the price history stays up while the game asks about the sale)
    look = 'ah', -- (the auction house's theme: ui/theme AREAS)
    pane = 'sellpick',
    layout = { from = 'menu', w = { 'from', min = 340 }, h = 0, clamp = true, auto = true },
};
