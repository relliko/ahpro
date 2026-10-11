--[[
* facelift - adapters/aucsales: your auction house listings, Sales Status (research/ffxi-re/
* client-notes.md, "Sales Status"): the auction list's own handler (adapters/auclist) in mode 1
* (+0x898 = 1), which the game opens when the server answers the first menu's Sales Status.
*
* The game rebuilds the rows from its listing slots on every UI update (and asks the server about
* each listing once per opening, on its own). A row (0x54 bytes): cells kind[8] at +0, colour[8]
* at +8, value[8] at +0x28: icon (kind 0x15, the item), name (0x19, the item, in the status
* colour), stack size (0x1B for a stack, else nothing), price (0x0A, value = price + 1); +0x48 the
* listing's slot (0-7). The name's colour is the status: 0x80509050 on sale here, 0x80909040 sold,
* 0x80804020 returned, 0x80404040 on sale at another auction house or waiting on the server.
*
* Choosing a listing is the game's Enter on it, and only for one on sale here: that opens its small
* menu (Price history, Remove from auction). The game's Enter on a sold or returned one would ask
* the server to clear it; facelift leaves that to the game.
--]]

local safemem    = require('core.safemem');
local sigs       = require('core.sigs');
local menus      = require('core.menus');
local scrolllist = require('adapters.scrolllist');
local gametext   = require('core.gametext');

local A = {
    sigs = { 'auclist.vtable', 'auclist.slot', 'list.set_index' },
};

local STATUS = { [0x80509050] = 'sale', [0x80909040] = 'sold', [0x80804020] = 'returned' };

function A.new()
    return { page = 0, top = 0, count = 0, rows = 0, cursor = 1, index = 0, list = {}, version = 0, raw = nil };
end

-- The rows as { id, name, lname, stack, stack_size, price, status ('sale', 'sold', 'returned' or
-- 'other'), slot }, rebuilt only when the game's rows change; false if a row doesn't look right.
local function listings(m)
    if (m.count == 0) then
        if (m.raw ~= '') then
            m.raw, m.list, m.version = '', {}, m.version + 1;
        end
        return true;
    end
    local block = m.rows ~= 0 and safemem.read(m.rows, m.count * 0x54) or nil;
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
        local k0, k1, k2, k3 = block:byte(o + 1), block:byte(o + 2), block:byte(o + 3), block:byte(o + 4);
        local slot = safemem.le32(block, o + 0x48);
        if (k0 ~= 0x15 or k1 ~= 0x19 or k3 ~= 0x0A or (k2 ~= 0 and k2 ~= 0x1B) or slot > 7) then
            return false;
        end
        local id = safemem.le32(block, o + 0x28);
        local item = res:GetItemById(id);
        local name = gametext.name(item, id);
        list[i + 1] = { id = id, name = name, lname = name:lower(), stack = k2 == 0x1B,
                        stack_size = item ~= nil and item.StackSize or 1,
                        price = math.max(0, safemem.le32(block, o + 0x34) - 1),
                        status = STATUS[safemem.le32(block, o + 0x0C)] or 'other', slot = slot };
    end
    m.raw, m.list, m.version = block, list, m.version + 1;
    return true;
end

-- The list's own fields into m; false if the handler isn't the auction list in Sales Status.
local function check(p, m)
    local h = p.handler;
    if (h == nil or h == 0 or safemem.u32(h) ~= sigs.get('auclist.vtable') or safemem.u32(h + 0x08) ~= p.obj) then
        return false;
    end
    local mode = safemem.read(h + 0x898, 1);
    return mode ~= nil and mode:byte(1) == 1 and scrolllist.read(h, p.obj, m) and m.count >= 0 and m.count <= 8;
end

-- Fills m, listings too; false if it isn't Sales Status or a row doesn't look right.
function A.read(p, m)
    return check(p, m) and listings(m);
end

-- The list's menu and handler while another menu has focus (its small menu), or nil.
function A.locate(p)
    local slot = sigs.get('auclist.slot');
    local h = slot ~= 0 and safemem.u32(slot) or nil;
    local obj = h ~= nil and h ~= 0 and safemem.u32(h + 0x08) or nil;
    if (obj == nil or obj == 0 or menus.open()[obj] ~= 'auclist') then
        return nil;
    end
    return obj, h;
end

local now = A.new();

A.actions = {
    -- Listing i (from 0): the game's cursor goes there.
    point = function (p, m, i)
        if (A.read(p, now) and i >= 0 and i < now.count) then
            scrolllist.point(p.handler, i);
        end
    end,
    -- Listing i (from 0), only one on sale here: the game's Enter on it (its small menu opens).
    choose = function (p, m, i)
        if (A.read(p, now) and i >= 0 and i < now.count and now.list[i + 1].status == 'sale') then
            scrolllist.choose(p.handler, i);
        end
    end,
};

return A;
