--[[
* facelift - adapters/iteminfo: the game's item tooltip (menu 'iteminfo'), and its second panel
* ('itemxinf', which only the bag list opens, beside it). The game has one of each for every screen
* (the bags, the auction house, shops, bazaars, trade, delivery, loot, equipment...): every screen
* hands it the item through the same setters (client-notes, "Item tooltip, item lists and shops").
* Display only: no input, never focused.
*
* The handler (vtable iteminfo.vtable / itemxinf.vtable, in slot iteminfo.slot / itemxinf.slot; the
* part's spec names them as slot and vtable): +0x24 the item id (word), +0x26 its slot in its bag,
* +0x340 the bag, +0x348 its extra data (augments...) or 0. With no item (id 0) it's still covered and
* nothing is drawn.
--]]

local safemem = require('core.safemem');
local sigs    = require('core.sigs');
local menus   = require('core.menus');

local A = {
    sigs = { 'iteminfo.slot', 'iteminfo.vtable', 'itemxinf.slot', 'itemxinf.vtable', 'ui.eventmode' },
};

function A.new()
    return { id = 0, slot = 0, bag = 0, ext = 0, x = 0, y = 0, w = 0, h = 0, version = 0 };
end

local function slot_sig(p) return p.spec.slot or 'iteminfo.slot'; end
local function vtable_sig(p) return p.spec.vtable or 'iteminfo.vtable'; end

-- The tooltip's menu and handler while it's open, or nil.
function A.locate(p)
    local slot = sigs.get(slot_sig(p));
    local h = slot ~= 0 and safemem.u32(slot) or nil;
    local obj = h ~= nil and h ~= 0 and safemem.u32(h + 0x08) or nil;
    if (obj == nil or obj == 0 or not p.menus[menus.open()[obj] or '']) then
        return nil;
    end
    return obj, h;
end

-- Fills m; false (the game's own tooltip shows) when it isn't the tooltip, the game hides it, or
-- something doesn't add up.
function A.read(p, m)
    local h = p.handler;
    if (h == nil or h == 0 or safemem.u32(h) ~= sigs.get(vtable_sig(p)) or safemem.u32(h + 0x08) ~= p.obj) then
        return false;
    end
    if (menus.game_hides() ~= false or not menus.shown(p.obj)) then
        return false;
    end
    local a, b = safemem.read(h + 0x24, 4), safemem.read(h + 0x340, 0x0C);
    if (a == nil or b == nil) then
        return false;
    end
    local id, slot = safemem.le16(a, 0), a:byte(3);
    local bag, ext = safemem.le32(b, 0), safemem.le32(b, 8);
    if (bag > 17) then
        return false;
    end
    local x, y, w, hh = menus.rect(p.obj);
    if (x == nil) then
        return false;
    end
    if (id ~= m.id or slot ~= m.slot or bag ~= m.bag or ext ~= m.ext) then
        m.version = m.version + 1;
    end
    m.id, m.slot, m.bag, m.ext = id, slot, bag, ext;
    m.x, m.y, m.w, m.h = x, y, w, hh;
    return true;
end

A.actions = {};

return A;
