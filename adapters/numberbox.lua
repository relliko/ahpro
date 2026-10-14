--[[
* facelift - adapters/numberbox: the number box (menu 'moneyctr')
*
* The box the game opens for an auction house bid or sale price, trading gil, and other amounts.
* Its handler object (research/ffxi-re/client-notes.md, "Number entry box"):
*   +0x08 the menu        +0x14/+0x16 x/y and +0x18/+0x1A width/height (words, UI pixels)
*   +0x20 arrow step      +0x24 max          +0x28 the number
*   +0x2C OK callback (0 once answered)      +0x30 what the opener passed along (ctx)
* Confirm(value) is what the game itself runs on Enter (with the number) and on Escape (with -1):
* it hands the value to whoever opened the box and closes it. It checks nothing, so facelift only
* ever confirms with the box's own number (kept between 0 and max) or -1. The game's arrows and
* Enter keep working; facelift shows the same number and edits it in place.
*
* An auction house bid (auc3's Bid, 0x1D9443) has OK callback 0x1D9500 (sig numberbox.ahbid, not
* required: without it every box is a plain one) and ctx = the auction list entry under the list's
* cursor: +0 kind (3 single, 4 stack), +4 item id. On OK the game asks its own yes/no, with No
* selected, and only Yes makes the bid. A sale (the Sell flow, 0x1D99CF) has OK callback 0x1D9A20
* (sig numberbox.ahsell) and ctx = the inventory item (+0 id); whether it's a full stack is the
* global the game sets just before (sig ahsell.single: 1 single, 0 stack). The game then asks its
* own yes/no and shows the fee before anything is listed.
--]]

local safemem = require('core.safemem');
local sigs    = require('core.sigs');
local game    = require('core.game');

local A = {
    sigs = { 'numberbox.confirm', 'numberbox.oninput' },
};

function A.new()
    return { x = 0, y = 0, w = 0, h = 0, step = 0, max = 0, value = 0, cb = 0, ctx = 0, gil = nil,
             kind = 'other', item = nil, handler = 0, bid = { id = 0, stack = false } };
end

local function gil_on_hand()
    local inv = AshitaCore:GetMemoryManager():GetInventory();
    local g = inv ~= nil and inv:GetContainerItem(0, 0) or nil;
    return g ~= nil and g.Count or nil;
end

-- What kind of box: 'ahbid' or 'other'. Once answered (+0x2C is 0) a box keeps the kind it had.
local function kind_of(p, m)
    if (m.cb == 0) then
        return m.handler == p.handler and m.kind or 'other';
    end
    local bid, sell = sigs.get('numberbox.ahbid'), sigs.get('numberbox.ahsell');
    return (bid ~= 0 and m.cb == bid) and 'ahbid' or ((sell ~= 0 and m.cb == sell) and 'ahsell' or 'other');
end

-- The item a sale box lists (the inventory item it was given), or nil.
local function sell_item(m)
    local e = m.ctx ~= 0 and safemem.read(m.ctx, 2) or nil;
    local slot = sigs.get('ahsell.single');
    local single = slot ~= 0 and safemem.read(slot, 4) or nil;
    if (e == nil or single == nil) then
        return nil;
    end
    local id = safemem.le16(e, 0);
    if (id == 0 or id == 0xFFFF) then
        return nil;
    end
    m.bid.id, m.bid.stack = id, safemem.le32(single, 0) == 0;
    return m.bid;
end

-- The item a bid box bids on (the list entry it was given), or nil if it doesn't look like one.
local function bid_item(m)
    local e = m.ctx ~= 0 and safemem.read(m.ctx, 8) or nil;
    if (e == nil) then
        return nil;
    end
    local k, id = safemem.le32(e, 0), safemem.le16(e, 4);
    if ((k ~= 3 and k ~= 4) or id == 0) then
        return nil;
    end
    m.bid.id, m.bid.stack = id, k == 4;
    return m.bid;
end

-- Fills m from the box; false if the handler isn't the number box (its vtable's OnInput must match).
function A.read(p, m)
    local h = p.handler;
    if (h == nil or h == 0) then
        return false;
    end
    local vt = safemem.u32(h);
    if (vt == nil or safemem.u32(vt + 0x18) ~= sigs.get('numberbox.oninput') or safemem.u32(h + 0x08) ~= p.obj) then
        return false;
    end
    local s = safemem.read(h + 0x14, 0x20);
    if (s == nil) then
        return false;
    end
    m.x, m.y, m.w, m.h = safemem.les16(s, 0x00), safemem.les16(s, 0x02), safemem.les16(s, 0x04), safemem.les16(s, 0x06);
    m.step, m.max, m.value = safemem.les32(s, 0x0C), safemem.les32(s, 0x10), safemem.les32(s, 0x14);
    m.cb, m.ctx = safemem.le32(s, 0x18), safemem.le32(s, 0x1C);
    m.kind = kind_of(p, m);
    m.handler = h;
    m.item = (m.kind == 'ahbid' and bid_item(m)) or (m.kind == 'ahsell' and sell_item(m)) or nil;
    m.gil = gil_on_hand();
    return true;
end

local now = A.new();

A.actions = {
    -- The box's number, kept between 0 and its max.
    set = function (p, m, v)
        v = math.max(0, math.min(m.max, math.floor(v)));
        game.write_i32(p.handler + 0x28, v);
        m.value = v;
    end,
    -- The game's OK with the box's own number (v nil), or its Cancel (v -1); nothing else. Only
    -- while the box is still open and waiting (the game's Enter may have got there first), and
    -- never with a number outside 0..max (another addon may have put one there): then nothing.
    confirm = function (p, m, v)
        if (v ~= nil and v ~= -1) then
            return;
        end
        if (A.read(p, now) and now.cb ~= 0 and (v == -1 or (now.value >= 0 and now.value <= now.max))) then
            if (v == nil) then
                -- (the game's question after it goes where this box is: adapters/yesno)
                local about = nil;
                if (now.item ~= nil) then -- (an AH bid or sale)
                    local item = AshitaCore:GetResourceManager():GetItemById(now.item.id);
                    local name = require('core.gametext').name(item, now.item.id);
                    if (now.item.stack) then
                        name = ('%s x%d'):format(name, item ~= nil and item.StackSize or 1);
                    end
                    about = { id = now.item.id, stack = now.item.stack, value = now.value, name = name, sale = now.kind == 'ahsell' };
                end
                require('adapters.yesno').sent('pricebox', about);
            end
            game.call('numberbox.confirm', p.handler, v or now.value);
        end
    end,
};

return A;
