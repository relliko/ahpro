--[[
* An item's price history at the auction house (the item menu's Price history) where the game's
* was. The game closes the item list while it's up and opens it again on Escape, so this takes the
* list's place: same switch, same spot. The item tooltip is facelift's (windows/iteminfo); the
* category menus the game keeps drawing at the right are hidden, as with the list. It's at least as
* wide as the game's list and grows to fit its columns. In the Sell flow it stays up under the price
* box (the game's header row there is left out).
--]]
local AH = require('data.ahmenus');

local suppress = {}; -- the item tooltip isn't hidden: windows/iteminfo stands in for it
for _, name in ipairs(AH.menus) do
    suppress[#suppress + 1] = name;
end

return {
    id = 'ahhisto', imgui = 'facelift_auchisto', name = 'Price history',
    toggle = 'auclist',
    parts = {
        { name = 'list', menus = { 'auchisto' }, adapter = 'auchisto', show = 'open' },
    },
    suppress = suppress,
    look = 'ah', -- (the auction house's theme: ui/theme AREAS)
    pane = 'ahhisto',
    layout = { from = 'menu', min = { w = { 'from', min = 300 } }, clamp = true, auto = true },
};
