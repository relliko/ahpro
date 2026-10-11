--[[
* facelift - core/menus
* The game's own window (menu) system, read from client memory. Offsets are from the RE notes
* (research/ffxi-re/client-notes.md, "Menu system").
*
* - The menu manager is one global object; manager+0x54 holds the focused menu.
* - A menu: +0x04 its header (name at +0x46, 16 bytes, "menu    moneyctr"), +0x0C its handler
*   (the object with the window's logic and state), +0x10 its state (0 shown; 0x0E hidden by a newer
*   menu in the same screen slot, or closing), +0x3A..+0x40 its frame's left, top, right and bottom,
*   +0x4C the cursor (the option the game's input passes to the handler, from 1), +0x60 its draw
*   layer, +0x6E set once it's asked to close, +0x70 set when the close is done (it's freed soon).
* - The manager's +0x80 / +0x82 (words) are the size of the game's UI in pixels.
* - A menu that's closing or closed counts as gone: not focused, not open.
*
* Everything is read with safemem: a menu freed mid-read gives nil instead of a crash.
--]]

local safemem = require('core.safemem');
local sigs    = require('core.sigs');

local menus = {};

local function focus_field()
    return sigs.get('menu.focus');
end

local function name_of(raw)
    raw = raw:gsub('%z', '');
    return raw:match('^menu%s+(%S+)') or raw;
end

local focus = { obj = 0, handler = 0, name = nil };
local last_raw, last_name = nil, nil;

--[[
* The focused menu: { obj, name, handler } or nil. The same table every call (copy what you keep).
* name has the 'menu' prefix stripped.
--]]
function menus.focused()
    local f = focus_field();
    if (f == 0) then
        return nil;
    end
    local obj = safemem.u32(f);
    if (obj == nil or obj == 0) then
        return nil;
    end
    -- +0x04 header, +0x0C handler, +0x6E closing, +0x70 closed, in one read.
    local s = safemem.read(obj + 0x04, 0x6D);
    if (s == nil or s:byte(0x6B) ~= 0 or s:byte(0x6D) ~= 0) then
        return nil;
    end
    local hdr = safemem.le32(s, 0);
    local raw = hdr ~= 0 and safemem.read(hdr + 0x46, 16) or nil;
    if (raw == nil) then
        return nil;
    end
    if (raw ~= last_raw) then
        last_raw, last_name = raw, name_of(raw);
    end
    focus.obj, focus.name, focus.handler = obj, last_name, safemem.le32(s, 0x08);
    return focus;
end

--[[
* A menu's frame in UI pixels as x, y, w, h, or nil. The game keeps it as left, top, right, bottom
* (words at +0x3A..+0x40; Menu::Contains 0x118C10 tests points against them that way), refreshed
* each frame the game draws the menu (while it's hidden they keep their last value). A menu with
* no frame has them all 0.
--]]
function menus.rect(obj)
    local s = safemem.read(obj + 0x3A, 8);
    if (s == nil) then
        return nil;
    end
    local l, t, r, b = safemem.les16(s, 0), safemem.les16(s, 2), safemem.les16(s, 4), safemem.les16(s, 6);
    if (r <= l or b <= t) then
        return nil;
    end
    return l, t, r - l, b - t;
end

-- A menu's cursor: the option the game's input hands its handler (from 1), or nil.
function menus.cursor(obj)
    local s = safemem.read(obj + 0x4C, 2);
    return s ~= nil and safemem.les16(s, 0) or nil;
end

-- How many items (options) the menu's resource has: header +0x18 (word), the count the game's
-- input checks the cursor against (0x11B2A0). nil if it can't be read.
function menus.items(obj)
    local hdr = safemem.u32(obj + 0x04);
    local s = hdr ~= nil and hdr ~= 0 and safemem.read(hdr + 0x18, 2) or nil;
    return s ~= nil and safemem.les16(s, 0) or nil;
end

--[[
* Which options of menu obj the game has greyed out (Enter on one only buzzes): { [option] = true },
* the same table every call, or nil if the menu's items can't be read. The items are the menu's
* element list at +0x14 (node +0 next, +0x10 the element, +0x14 removed); an option element has
* kind word 1 at +0, its number at +0x3A and its state at +0x10 (5 = greyed).
--]]
local greyed = {};
function menus.greyed(obj)
    for k in pairs(greyed) do
        greyed[k] = nil;
    end
    local node = safemem.u32(obj + 0x14);
    local n = 0;
    while (node ~= nil and node ~= 0 and n < 64) do
        n = n + 1;
        local s = safemem.read(node, 0x18);
        if (s == nil) then
            return nil;
        end
        local el = safemem.le32(s, 0x10);
        if (s:byte(0x15) == 0 and el ~= 0) then
            local e = safemem.read(el, 0x3C);
            if (e == nil) then
                return nil;
            end
            if (safemem.le16(e, 0) == 1 and safemem.le32(e, 0x10) == 5) then
                greyed[safemem.le16(e, 0x3A)] = true;
            end
        end
        node = safemem.le32(s, 0);
    end
    return greyed;
end

-- The menu manager (the object CloseMenuObj and OpenMenu are called on), or nil.
function menus.manager()
    local f = focus_field();
    return f ~= 0 and f - 0x54 or nil;
end

-- The game's UI size in pixels (what menu positions are measured in), or nil.
function menus.ui_size()
    local f = focus_field();
    local s = f ~= 0 and safemem.read(f - 0x54 + 0x80, 4) or nil;
    if (s == nil) then
        return nil;
    end
    local w, h = safemem.le16(s, 0), safemem.le16(s, 2);
    if (w < 320 or h < 240) then
        return nil;
    end
    return w, h;
end

--[[
* The open menus, walked from the manager's list (node +0 next, +0x10 menu, +0x14 removed), as
* { [obj] = name }. Menus closing (+0x6E) or closed (+0x70) are left out. Walked at most once a
* frame: the result is kept until menus.begin_frame() or menus.invalidate() (after anything that
* calls the game). menus.order() is the same menus in the list's order; menus.walks() counts walks.
--]]
local open_set, listed_set, open_ok = {}, {}, false;
local order, walks = {}, 0;

function menus.open()
    if (open_ok) then
        return open_set;
    end
    for k in pairs(open_set) do
        open_set[k] = nil;
    end
    for k in pairs(listed_set) do
        listed_set[k] = nil;
    end
    for i = #order, 1, -1 do
        order[i] = nil;
    end
    walks = walks + 1;
    local mgr = menus.manager();
    local node = mgr ~= nil and safemem.u32(mgr) or nil;
    local n = 0;
    while (node ~= nil and node ~= 0 and n < 128) do
        n = n + 1;
        local s = safemem.read(node, 0x18);
        if (s == nil) then
            break;
        end
        local obj = safemem.le32(s, 0x10);
        if (s:byte(0x15) == 0 and obj ~= 0) then
            local f = safemem.read(obj + 0x6E, 3);
            if (f ~= nil and f:byte(3) == 0) then
                listed_set[obj] = true;
                local hdr = f:byte(1) == 0 and safemem.u32(obj + 0x04) or nil;
                local raw = hdr ~= nil and hdr ~= 0 and safemem.read(hdr + 0x46, 16) or nil;
                if (raw ~= nil) then
                    open_set[obj] = name_of(raw);
                    order[#order + 1] = obj;
                end
            end
        end
        node = safemem.le32(s, 0);
    end
    open_ok = true;
    return open_set;
end

function menus.order()
    menus.open();
    return order;
end

function menus.walks()
    menus.open();
    return walks;
end

-- Whether a menu is still in the manager's list and not closed (it may be closing); its memory is
-- good to write while it is.
function menus.listed(obj)
    menus.open();
    return listed_set[obj] == true;
end

-- Whether menu obj is shown by the game now (its state +0x10 is 0: not hidden behind another in its
-- screen slot).
function menus.shown(obj)
    local s = safemem.read(obj + 0x10, 4);
    return s ~= nil and safemem.le32(s, 0) == 0;
end

-- Whether the game has its UI hidden (the hide-UI key) or is in event mode (cutscenes, where only
-- some windows draw), when windows without the game's 'draw in events' flag don't draw; nil if that
-- can't be read.
function menus.game_hides()
    local mgr = menus.manager();
    local hidden = mgr ~= nil and safemem.read(mgr + 0xB4, 1) or nil;
    local slot = sigs.get('ui.eventmode');
    local ev = slot ~= 0 and safemem.u32(slot) or nil;
    if (hidden == nil or ev == nil) then
        return nil;
    end
    if (hidden:byte(1) == 1) then
        return true;
    end
    local e = ev ~= 0 and safemem.read(ev + 0x48, 1) or nil;
    return e ~= nil and e:byte(1) ~= 0;
end

-- Whether a menu has been asked to close (+0x6E), or nil if it can't be read.
function menus.closing(obj)
    local s = safemem.read(obj + 0x6E, 1);
    if (s == nil) then
        return nil;
    end
    return s:byte(1) ~= 0;
end

function menus.begin_frame() open_ok = false; end
function menus.invalidate() open_ok = false; end

-- An open menu's object by name, or nil.
function menus.find(name)
    for obj, n in pairs(menus.open()) do
        if (n == name) then
            return obj;
        end
    end
    return nil;
end

return menus;
