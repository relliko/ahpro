--[[
* The number box (auction house bid and sale prices, trading gil, other amounts), kept minimal
* (panes/pricebox). For a bid it docks under the prices window (else beside it, else beside the
* list) so the list and the prices stay in view; anything else goes where the game's box was. It's
* solid, and the game's own gil window ('money', opened with a bid or a sale) is hidden: the box
* shows your gil.
--]]
return {
    id = 'pricebox', imgui = 'facelift_moneyctr', name = 'Price box',
    toggle = 'moneyctr', title = 'Price box', fallback = 'the game\'s own box shows',
    parts = {
        { name = 'box', menus = { 'moneyctr' }, adapter = 'numberbox' },
    },
    suppress = { 'money' },
    solid = true,
    look = 'ah', -- (the auction house's theme: ui/theme AREAS)
    pane = 'pricebox',
    layout = { from = 'model', w = 320, h = 0, clamp = true, auto = true,
               dock = { { target = 'ahprices', at = 'bl', dy = 6 }, { target = 'ahprices', at = 'tr', dx = 6 },
                        { target = 'ahlist', at = 'tr', dx = 6, unless = 'ahprices' },
                        { target = 'ahbrowse', at = 'tr', dx = 6, unless = 'ahprices' } } },
    options = {
        hold_at = { label = 'Ask twice at this many times the usual price (0: never)', default = 3, min = 0, max = 10, order = 1 },
    },
};
