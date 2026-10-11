--[[
* facelift - adapters/sellpick: the Sell flow's item picker (research/ffxi-re/client-notes.md,
* "Auction house sale"): the game's ordinary inventory list (menu 'inventor', handler slot
* sig inventory.slot) opened with the auction sale helper (sig ahsell.ctx) at handler +0x5C.
*
* A row (0x54 bytes, a scroll list's): cells kind[8] at +0, colour[8] at +8, value[8] at +0x28:
* icon (0x16, the item record), name (0x19, the item id, its colour 0x80808080 normal, 0x80404040
* greyed: can't be sold, 0x80804020 the one being priced), count (7, for stackables; else nothing);
* +0x48 the item record. The game decides what can be sold; facelift only reads its colour.
*
* Choosing an item is the game's own Enter (its key handler does the work before the list's
* OnSelect, so it goes through the menu input): it asks the server for the item's price history
* and opens the sale price box. Greyed items aren't offered.
--]]

local safemem    = require('core.safemem');
local sigs       = require('core.sigs');
local scrolllist = require('adapters.scrolllist');
local gametext   = require('core.gametext');

local A = {
    sigs = { 'inventory.slot', 'ahsell.ctx', 'list.set_index', 'menu.input' },
};

function A.new()
    return { page = 0, top = 0, count = 0, rows = 0, cursor = 1, index = 0, list = {}, version = 0, raw = nil, age = 0 };
end

-- The rows as { id, name, lname, n (count, stackables only), stack (a full stack: sold as one),
-- stack_size, faint (greyed) },
-- rebuilt when the game's rows change (looked at every few frames); false if a row looks wrong.
local function items(m)
    m.age = m.age + 1;
    if (m.raw ~= nil and m.age < 10 and m.count == m.built_n and m.rows == m.built_rows) then
        return true;
    end
    m.built_n, m.built_rows = m.count, m.rows;
    m.age = 0;
    if (m.count == 0) then
        m.raw, m.list = '', {};
        return true;
    end
    local block = m.rows ~= 0 and m.count <= 200 and safemem.read(m.rows, m.count * 0x54) or nil;
    if (block == nil) then
        return false;
    end
    if (block == m.raw) then
        return true;
    end
    local list = {};
    local res = AshitaCore:GetResourceManager();
    for i = 0, m.count - 1 do
        local o = i * 0x54;
        local k0, k1, k2 = block:byte(o + 1), block:byte(o + 2), block:byte(o + 3);
        if (k0 ~= 0x16 or k1 ~= 0x19 or (k2 ~= 0 and k2 ~= 7)) then
            return false;
        end
        local id = safemem.le32(block, o + 0x2C);
        local item = res:GetItemById(id);
        local name = gametext.name(item, id);
        local n = k2 == 7 and safemem.le32(block, o + 0x30) or nil;
        local size = item ~= nil and item.StackSize or 1;
        -- The game sells a full stack as a stack, anything less as single items.
        list[i + 1] = { id = id, name = name, lname = name:lower(), n = n, stack = size > 1 and n ~= nil and n >= size,
                        stack_size = size, faint = safemem.le32(block, o + 0x0C) == 0x80404040 };
    end
    m.raw, m.list, m.version = block, list, m.version + 1;
    return true;
end

-- The list's own fields into m; false unless it's the inventory opened by the auction sale.
local function check(p, m)
    local h = p.handler;
    local slot, ctx = sigs.get('inventory.slot'), sigs.get('ahsell.ctx');
    if (h == nil or h == 0 or slot == 0 or ctx == 0 or safemem.u32(slot) ~= h or safemem.u32(h + 0x08) ~= p.obj) then
        return false;
    end
    local helper = safemem.u32(ctx);
    if (helper == nil or helper == 0 or safemem.u32(h + 0x5C) ~= helper) then
        return false;
    end
    return scrolllist.read(h, p.obj, m);
end

function A.read(p, m)
    if (m.seen ~= p.obj) then
        m.seen, m.raw = p.obj, nil; -- opened anew: its rows are read at once
    end
    return check(p, m) and items(m);
end

-- Whether the game's row i (from 0) is still item r (and can be sold): read now, not from the
-- rows last kept.
local function same(m, i, r)
    local s = safemem.read(m.rows + i * 0x54, 0x54);
    return s ~= nil and s:byte(1) == 0x16 and s:byte(2) == 0x19 and safemem.le32(s, 0x2C) == r.id
        and (r.n == nil or safemem.le32(s, 0x30) == r.n) and safemem.le32(s, 0x0C) ~= 0x80404040;
end

local now = A.new();

A.actions = {
    -- Item i (from 0): the game's cursor goes there.
    point = function (p, m, i)
        if (check(p, now) and i >= 0 and i < now.count) then
            scrolllist.point(p.handler, i);
        end
    end,
    -- Item i (from 0), if it can be sold: the game's Enter on it.
    choose = function (p, m, i)
        local r = m.list[i + 1];
        if (r ~= nil and not r.faint and check(p, now) and i >= 0 and i < now.count and same(now, i, r)) then
            scrolllist.enter(p.handler, p.obj, i);
        end
    end,
};

return A;
