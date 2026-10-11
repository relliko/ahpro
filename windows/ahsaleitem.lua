--[[
* A listing's small menu in Sales Status (auc4: Price history, Remove from auction) drawn as the main
* menu is (the option menu reader and pane), the game's cursor shown. Remove from auction leads to the
* game's own yes/no; the game greys the options that don't apply (shown faint, and they can't be
* pressed).
--]]
return {
    id = 'ahsaleitem', imgui = 'facelift_auc4', name = 'Listing menu',
    toggle = 'auclist', off_with = 'ahone', -- (windows/ahbrowse instead)
    parts = {
        { name = 'item', menus = { 'auc4' }, adapter = 'menuopts' },
    },
    needs_open = { 'auclist' },
    look = 'ah', -- (the auction house's theme: ui/theme AREAS)
    pane = 'menuopts',
    scroll = false,
    background = false, -- the pane frames the options
    layout = { from = 'model', w = 'from', h = 'from' },
};
