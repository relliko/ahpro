--[[
* The auction house's first menu (Bid, Sell, Sales Status) and its category menus (Weapons, Armor,
* ... and the menus under them) drawn as the main menu is (adapters/menuopts, panes/menuopts): a
* button in the theme for each option at the option's own place, with the game's own label on it. A
* button does what the game's Enter does on that option: opens the next menu, or asks for that
* category's list (the game's own request). The menus it came through stay open in the game (Escape
* goes back to them) and are hidden. Once a category's list is up, the list window hides the category
* menus (windows/ahlist) and this goes away too, leaving the right side to the item menu.
--]]
local AH = require('data.ahmenus');

return {
    id = 'ahcats', imgui = 'facelift_auccats', name = 'Auction categories',
    toggle = 'auccats', title = 'Auction categories', off_with = 'ahone', -- (windows/ahtop, ahbrowse instead) fallback = 'the game\'s own menus show',
    parts = {
        { name = 'menu', menus = AH.menus, adapter = 'menuopts',
          -- Sales Status: its Enter has the game ask the server each time (Phoenix refuses again
          -- within 5 s), so one press per 5 s.
          cooldown = { auc1 = { [3] = 5 } } },
    },
    suppress = AH.menus,
    look = 'ah', -- (the auction house's theme: ui/theme AREAS)
    pane = 'menuopts',
    scroll = false,
    background = false, -- the pane frames the options
    layout = { from = 'model', w = 'from', h = 'from' },
};
