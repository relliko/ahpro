-- The auction house item menu (auc3: Price history, Bid, Sort) drawn as the main menu is (the option
-- menu reader and pane: the game's own labels on themed buttons at their places), with the list still
-- up. The game's cursor (it jumps here when a row is picked) is shown.
return {
    id = 'ahitem', imgui = 'facelift_auc3', name = 'Auction item menu',
    toggle = 'auclist', off_with = 'ahone', -- (windows/ahbrowse instead)
    parts = {
        { name = 'item', menus = { 'auc3' }, adapter = 'menuopts' },
    },
    needs_open = { 'auclist' },
    look = 'ah', -- (the auction house's theme: ui/theme AREAS)
    pane = 'menuopts',
    scroll = false,
    background = false, -- the pane frames the options
    layout = { from = 'model', w = 'from', h = 'from' },
};
