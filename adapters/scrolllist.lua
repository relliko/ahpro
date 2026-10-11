--[[
* facelift - adapters/scrolllist: what every scroll-list menu shares (bank, inventory, shop, friend
* list, the auction list...; their handlers derive from one base, OnInput 0x1F6C70).
* Handler fields (research/ffxi-re/client-notes.md, "Auction house item list"):
*   +0x08 the menu (its +0x4C is the cursor's row on the page, from 1)
*   +0x18 rows per page   +0x1E first row shown   +0x20 number of rows   +0x38 the rows
* Choosing a row does what the game's Enter does: SetIndex puts the cursor on it, then the list's
* own OnSelect (vtable +0x5C) acts on it.
--]]

local safemem = require('core.safemem');
local menus   = require('core.menus');
local game    = require('core.game');

local L = {
    sigs = { 'list.set_index' },
};

-- Fills the base fields of m from handler h of menu obj; false if they can't be read.
function L.read(h, obj, m)
    local s = safemem.read(h + 0x18, 0x24);
    if (s == nil) then
        return false;
    end
    m.page, m.top, m.count, m.rows = safemem.les16(s, 0x00), safemem.les16(s, 0x06), safemem.les16(s, 0x08), safemem.le32(s, 0x20);
    m.cursor = menus.cursor(obj) or 1;
    m.index = m.top + m.cursor - 1;
    return true;
end

-- Puts the game's cursor on row i (from 0) of the list with handler h, scrolling it into view.
function L.point(h, i)
    game.call('list.set_index', h, i, 0);
end

-- Row i (from 0) of the list with handler h and menu obj, then Enter through the game's own menu
-- input (sig menu.input): for lists whose Enter does its work before OnSelect (the inventory as a
-- picker), exactly what the game's key does.
function L.enter(h, obj, i)
    L.point(h, i);
    local m = {};
    if (L.read(h, obj, m) and m.index == i) then
        game.call('menu.input', obj, 5);
    end
end

-- The game's Enter on row i (from 0) of the list with handler h.
function L.choose(h, i)
    L.point(h, i);
    game.vcall(h, 0x5C, 'uint8_t(__thiscall*)(void*, int32_t)', i);
end

return L;
