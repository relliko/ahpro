--[[
* The prices facelift has kept for an item (db/prices: every sale seen in a price history, for all
* your characters), with a graph over time. It sits to the right of the price history, the auction
* list or Sales Status, where it follows the item under the mouse (else the one selected). It has
* no game menu of its own and hides nothing.
--]]
return {
    id = 'ahprices', imgui = 'facelift_ahprices', name = 'Prices seen',
    toggle = 'prices', title = 'Prices seen', fallback = 'it doesn\'t show',
    follows = { 'ahhisto', 'ahlist', 'ahsales', 'ahsellpick' },
    look = 'ah', -- (the auction house's theme: ui/theme AREAS)
    pane = 'ahprices',
    layout = { from = 'window', at = 'tr', dx = 6, w = 320, h = 0, clamp = true, auto = true },
};
