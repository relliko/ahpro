--[[
* facelift - data/ahmenus: the auction house's first menu (auc1) and its category menus.
*
* The game draws these options as pictures, so their names aren't anywhere facelift can read them.
* Each menu's options are in the order its OnSelect handles them (FFXiMain.dll 0x1DA770 for auc2;
* the sub-menus look the option up in byte tables at 0x37EDD8.. to get the auction category, named
* here as the server names them in sql/item_basic.sql). sub: options that open another menu
* rather than a list.
--]]

return {
    labels = {
        auc1     = { 'Bid', 'Sell', 'Sales Status' },
        auc2     = { 'Weapons', 'Armor', 'Scrolls', 'Medicines', 'Furnishings', 'Materials', 'Food', 'Crystals', 'Others' },
        aucweapo = { 'Hand-to-Hand', 'Daggers', 'Swords', 'Great Swords', 'Axes', 'Great Axes', 'Scythes', 'Polearms',
                     'Katana', 'Great Katana', 'Clubs', 'Staves', 'Ranged', 'Instruments', 'Ammo & Misc.' },
        aucammo  = { 'Ammunition', 'Fishing Gear', 'Pet Items', 'Grips' },
        aucarmor = { 'Shields', 'Head', 'Neck', 'Body', 'Hands', 'Waist', 'Legs', 'Feet', 'Back', 'Earrings', 'Rings' },
        aucmagic = { 'White Magic', 'Black Magic', 'Songs', 'Ninjutsu', 'Summoning', 'Dice', 'Geomancy' },
        aucmater = { 'Smithing', 'Goldsmithing', 'Clothcraft', 'Leathercraft', 'Bonecraft', 'Woodworking', 'Alchemy', 'Alchemy 2' },
        aucfood  = { 'Meals', 'Ingredients', 'Fish' },
        aucmeals = { 'Meat & Eggs', 'Seafood', 'Vegetables', 'Soups', 'Breads & Rice', 'Sweets', 'Drinks' },
        aucitem  = { 'Misc.', 'Beast-made', 'Cards', 'Ninja Tools', 'Cursed Items', 'Automaton', 'Misc. 2', 'Misc. 3' },
    },
    -- The menus' own titles (the game's window title table, ROM/97/41.DAT).
    titles = {
        auc1 = 'Auction', auc2 = 'Auction', aucweapo = 'Weapons', aucammo = 'Ammo & Misc.', aucarmor = 'Armor', aucmagic = 'Magic Scrolls',
        aucmater = 'Materials', aucfood = 'Food', aucmeals = 'Meals', aucitem = 'Others',
    },
    sub = {
        auc1 = { [1] = true },
        auc2 = { [1] = true, [2] = true, [3] = true, [6] = true, [7] = true, [9] = true },
        aucweapo = { [15] = true },
        aucfood = { [1] = true },
    },
    -- The menu each sub option opens (auc2's OnSelect 0x1DA770, aucweapo's option 15, aucfood's 1).
    opens = {
        auc1 = { [1] = 'auc2' },
        auc2 = { [1] = 'aucweapo', [2] = 'aucarmor', [3] = 'aucmagic', [6] = 'aucmater', [7] = 'aucfood', [9] = 'aucitem' },
        aucweapo = { [15] = 'aucammo' },
        aucfood = { [1] = 'aucmeals' },
    },
    -- The auction category each option lists (the OnSelects' byte tables: client-notes, 'Auction house
    -- category menus'; numbers as the server's item_basic aH column), for the item lookup.
    cats = {
        auc2     = { [4] = 33, [5] = 34, [8] = 35 },
        aucweapo = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 },
        aucammo  = { 15, 47, 48, 62 },
        aucarmor = { 16, 17, 22, 18, 19, 23, 20, 21, 26, 24, 25 },
        aucmagic = { 28, 29, 32, 31, 30, 60, 45 },
        aucmater = { 38, 39, 40, 41, 42, 43, 44, 63 },
        aucfood  = { [2] = 59, [3] = 51 },
        aucmeals = { 52, 53, 54, 55, 56, 57, 58 },
        aucitem  = { 46, 50, 36, 49, 37, 61, 64, 65 },
    },
    -- Each option's icon: an item the game lists there (its own item icon; a menu of categories, a
    -- typical item inside it), picked from the Phoenix server's item table.
    icons = {
        auc2     = { 16535, 12568, 4609, 4112, 2, 651, 4437, 4096, 2176 },
        aucweapo = { 16385, 16448, 16535, 16583, 16640, 16704, 16768, 16832, 16900, 16966, 17024, 17088, 17152, 17344, 17318 },
        aucammo  = { 17339, 17389, 17016, 19025 },
        aucarmor = { 12289, 12448, 13081, 12568, 12696, 13192, 12824, 12952, 13594, 13321, 13465 },
        aucmagic = { 4609, 4752, 4976, 4928, 4896, 5477, 6073 },
        aucmater = { 651, 650, 825, 850, 880, 691, 914, 4168 },
        aucfood  = { 4437, 610, 4401 },
        aucmeals = { 4409, 4338, 4279, 4455, 4408, 4413, 4422 },
        aucitem  = { 503, 501, 2176, 1161, 1344, 2238, 3895, 1452 },
    },
    -- How deep each menu is. Not enough on its own to tell which one is in use: the menus above stay
    -- open under their sub-menus (the game hides them, state 0x0E). Weapons once stayed open after
    -- going back out of it, but that was facelift keeping it hidden mid-close (fixed in 0.9.1).
    depth = {
        auc1 = 0, auc2 = 1, aucweapo = 2, aucarmor = 2, aucmagic = 2, aucmater = 2, aucfood = 2, aucitem = 2,
        aucammo = 3, aucmeals = 3,
    },
    menus = { 'auc1', 'auc2', 'aucweapo', 'aucammo', 'aucarmor', 'aucmagic', 'aucmater', 'aucfood', 'aucmeals', 'aucitem' },
};
