--[[
* The auction house as one window (panes/ahbrowse), from its first menu on: Bid, Sell and Sales
* Status as tabs at its top. Bid: the categories, the item list and the item (its tooltip, the
* prices kept, Price history / Bid / Sort). Sell: the bag to pick from and the item. Sales Status:
* your listings and the one picked (Price history / Remove). It stands in for the separate auction
* windows (they stand aside while this switch is on). The game's menus stay open underneath and do
* the work: a click is the game's key or mouse on them. The price box and the price history are
* their own windows still. Parts are optional: the game's list and bag are each read by whichever
* part they are just now (the bid list or Sales Status, the Sell picker).
--]]
local AH = require('data.ahmenus');

local cats, suppress = {}, { 'iteminfo' }; -- (the item shows at the right: the game's tooltip hidden)
for _, name in ipairs(AH.menus) do
    if (name ~= 'auc1') then
        cats[#cats + 1] = name;
    end
    suppress[#suppress + 1] = name;
end

return {
    id = 'ahbrowse', imgui = 'facelift_ahbrowse', name = 'Auction house (one window)',
    toggle = 'ahone', title = 'Auction house as one window', fallback = 'the separate auction windows show',
    parts = {
        { name = 'list', menus = { 'auclist' }, adapter = 'auclist', show = 'open', optional = true, through = { auc3 = 'close_obj' } },
        { name = 'cats', menus = cats, adapter = 'ahpath', show = 'open', watch = true, acts = true, optional = true },
        { name = 'top', by_name = true, menus = { 'auc1' }, adapter = 'menuopts', show = 'open', optional = true },
        { name = 'item', by_name = true, menus = { 'auc3' }, adapter = 'menuopts', show = 'open', optional = true },
        { name = 'sales', menus = { 'auclist' }, adapter = 'aucsales', show = 'open', optional = true, through = { auc4 = 'close_obj' } },
        { name = 'listing', by_name = true, menus = { 'auc4' }, adapter = 'menuopts', show = 'open', optional = true },
        { name = 'sell', by_name = true, menus = { 'inventor' }, adapter = 'sellpick', show = 'open', optional = true },
    },
    suppress = suppress,
    unless_open = { 'auchisto' }, -- (the price history takes the list's place: its own window)
    look = 'ah', -- (the auction house's theme: ui/theme AREAS)
    pane = 'ahbrowse',
    movable = true, -- (drag it by its empty space; kept per character, Reset in edit mode)
    scroll = false,
    layout = { from = 'screen', x = 0.5, y = 0.12, px = 0.5, py = 0, h = 0, clamp = true, auto = true, z = 'under' },
    options = { -- (also in its cog, top right)
        rows = { label = 'Rows shown', default = 20, min = 8, max = 40, order = 1 },
        icons = { label = 'Category icons', kind = 'check', default = 1, min = 0, max = 1, order = 2,
                  hint = 'An item the game lists there, beside each category.' },
        gather = { label = 'Gather every Sales Status page', kind = 'check', default = 0, min = 0, max = 1, order = 3,
                   hint = "With the server's Sales Status pages (6 a press): pressed again every 2 s until all are in one list. Off: one page at a time, with a Next page button." },
    },
};
