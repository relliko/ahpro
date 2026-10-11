--[[
* The item tooltip, over the game's own (menu 'iteminfo'), wherever the game shows it: every screen
* hands the game's one tooltip its item (the bags, the auction house, shops, bazaars, trade, delivery,
* loot, equipment...), so this one window covers them all, drawn as every facelift window draws an
* item (ui/iteminfo). While a facelift list offers the row under the mouse (ui/tooltip), it shows that
* row. Over the other windows. Where the game puts its tooltip, except beside the auction house's
* windows, where Prices seen (and the price box under it, or the yes/no that follows it) already are:
* then under those; beside a
* facelift list (taller than the game's, which the game's tooltip sits under); and never over the
* chat box (taller than the game's tooltip, it would run down into it): above it then.
--]]
return {
    id = 'iteminfo', imgui = 'facelift_iteminfo', name = 'Item tooltip',
    toggle = 'iteminfo', title = 'Item tooltip', fallback = 'the game\'s own tooltip shows',
    parts = {
        { name = 'tip', menus = { 'iteminfo' }, adapter = 'iteminfo', show = 'open', watch = true,
          slot = 'iteminfo.slot', vtable = 'iteminfo.vtable' },
    },
    offers = true,
    unless_up = { 'ahbrowse' }, -- (it shows the item itself)
    pane = 'iteminfo',
    layout = { from = 'menu', w = { 'from', min = 300 }, h = 0, clamp = true, auto = true, -- (ui/tipsize: the same width)
               dock = { { target = 'pricebox', at = 'bl', dy = 6 },
                        -- (the bid's or sale's yes/no opens where the price box was: under it then)
                        { target = 'yesno', at = 'bl', dy = 6, with = 'ahprices' },
                        { target = 'ahprices', at = 'bl', dy = 6, unless = { 'pricebox', 'yesno' } },
                        { target = 'inventory', at = 'tr', dx = 6 },
                        { target = 'lists', at = 'tr', dx = 6 }, { target = 'lists1', at = 'tr', dx = 6 } },
               avoid = { 'chatlog' } },
};
