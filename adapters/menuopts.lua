--[[
* facelift - adapters/menuopts: any of the game's option menus (the main menu, the Mog House's,
* shops' Buy/Sell, magic and ability menus, search, linkshell, merits, config pages...). The menu
* object draws every menu's options itself (Menu::Draw 0x1177D0; client-notes "Menu layouts and
* option pictures"): each option is an element in its list at +0x14, with a picture (a sprite: the
* game's button bar and its label's glyphs, from the game's sprite sets), a state and a place. The
* handler's own Draw only adds extras, so a menu is taken only when its handler draws nothing of its
* own (the do-nothing Draw of the default vtable) or nothing that matters (the main menu lighting its
* page arrows); anything else stays the game's.
*
* Model: opts[1..n] = { n (the option's number, what the cursor takes), state (5 greyed, 0x10
* inert), deco (a title tab or other picture that isn't an option), x, y, w, h (UI px), label (the
* picture as quads, kept per sprite), title (char* the game's title text for it, or 0), out (wholly
* outside the menu's window in its layout, like the main menu's page arrows: drawn apart from the
* box) }, marks[option] = picture (what a party menu's Draw adds on an option: a mark, a check),
* cursor,
* the area they all cover (x, y, w, h, UI px) and the box around the rest (bx, by, bw, bh; bw 0
* when there's none).
*
* The main menu's last option (12: Map, or Mog House in the Mog House) is hidden from the menu and
* drawn by its handler, which keeps three pictures for it (Map, Mog House, Mog House greyed) and
* picks one each frame; it's taken from there (the menuwind.draw pattern covers that choice).
*
* An option is chosen as the game's mouse does: the cursor moved there, then Enter through the game's
* menu input (0x118260), which buzzes on a greyed option and runs the handler's OnInput otherwise. A
* part's cooldown = { [menu] = { [option] = seconds } }: a press of that option within that long of
* the last does nothing (shown faint meanwhile: m.cool[option]); for options whose Enter has the
* game ask the server (the auction house's Sales Status).
*
* Other option menus the game shows while one has focus: the menus a submenu was opened from (kept
* up under it), and the ones a screen opens beside its list without focus (the bag's side menu
* itmsortw, opened by the list's helper; the sort menus of the magic and ability lists...). A part
* with show = 'open' and rank = k is the k-th of those: open, shown by the game, not focused, not
* named by another window; the most recently focused first, then the rest in the game's list order
* (shown as they are, not clickable: a click goes to the game, which moves focus there itself).
--]]

local safemem = require('core.safemem');
local sigs    = require('core.sigs');
local menus   = require('core.menus');
local game    = require('core.game');
local era     = require('core.era');

local pressed = {}; -- [menu/option] = when it was last pressed, for cooldowns

local A = {
    sigs = { 'menu.input', 'menu.set_cursor', 'menu.default_vtable', 'menuwind.draw' },
};

local MAX = 64;
local NONE = {};
local OWN = 12; -- the main menu's option its handler draws
local recent = {}; -- [menu object] = when it was last read with focus

function A.new()
    return { opts = {}, marks = {}, cool = {}, n = 0, cursor = 0, x = 0, y = 0, w = 0, h = 0, bx = 0, by = 0, bw = 0, bh = 0, version = 0 };
end

-- A float from its bits (never through an ffi float: NaN bits don't survive LuaJIT), or nil.
local function f32(b)
    if (b == 0) then
        return 0;
    end
    local e = math.floor(b / 0x800000) % 256;
    if (e == 255) then
        return nil;
    end
    local m = b % 0x800000;
    local v = (e == 0) and m * 2 ^ -149 or (1 + m / 0x800000) * 2 ^ (e - 127);
    return b >= 0x80000000 and -v or v;
end

--[[
* Whether a handler's Draw leaves the options to the menu: one that draws nothing (a bare ret, as the
* main menu's second page has, or the default's: mov byte [ecx+0x10], 1; ret), or the main menu's
* (it only lights its page arrows). Kept per Draw.
--]]
local draws = nil;
local quiet = nil; -- the default OnInput (no input): display-only menus aren't options
local function draws_nothing(d)
    if (draws == nil) then
        draws = {};
        local vt = sigs.get('menu.default_vtable');
        if (vt ~= 0) then
            quiet = safemem.u32(vt + 0x18);
        end
        local mw = sigs.get('menuwind.draw');
        if (mw ~= 0) then
            draws[mw] = true;
        end
    end
    local v = draws[d];
    if (v == nil) then
        local c = safemem.read(d, 5);
        v = c ~= nil and (c:byte(1) == 0xC3 or c == '\198\065\016\001\195');
        draws[d] = v;
    end
    return v;
end

--[[
* A picture as quads, kept per sprite: { count, head, quads = { { tex (D3D8 texture), glyph (on 'font
* font': the label's text), shadow (its dark copy), x0, y0, x1, y1 (sprite px), u0, v0, u1, v1 } } }.
* The game's button bar ('menu buttonto') is left out: facelift draws its own button. A sprite is
* read again when its part list changes.
--]]
local pics, npics = {}, 0;
local function picture(sprite)
    local hdr = sprite ~= 0 and safemem.read(sprite, 0x18) or nil;
    if (hdr == nil) then
        return nil;
    end
    local head, count = safemem.le32(hdr, 0x04), safemem.le32(hdr, 0x14);
    local P = pics[sprite];
    if (P ~= nil and P.head == head and P.count == count) then
        return P;
    end
    if (count > 128) then
        return nil;
    end
    P = { head = head, count = count, quads = {} };
    local node, k = head, 0;
    while (node ~= 0 and k < 128) do
        k = k + 1;
        local nd = safemem.read(node, 0x18);
        if (nd == nil) then
            return nil;
        end
        local part = safemem.le32(nd, 0x10);
        if (nd:byte(0x15) == 0 and part ~= 0) then
            local s = safemem.read(part, 0xD0);
            if (s == nil) then
                return nil;
            end
            local name = s:sub(0x33, 0x42):lower();
            if (name ~= 'menu    buttonto') then
                local to = safemem.le32(s, 0x4C);
                local tt = to ~= 0 and safemem.read(to + 0x40, 8) or nil;
                local tex = tt ~= nil and (safemem.le32(tt, 0) ~= 0 and safemem.le32(tt, 0) or safemem.le32(tt, 4)) or 0;
                -- Corners TL, TR, BL, BR: the quad from its smallest to its largest, with those
                -- corners' texture coordinates (a mirrored part keeps its flip).
                local lo, hi = 1, 1;
                local xs, ys = {}, {};
                for i = 1, 4 do
                    xs[i], ys[i] = safemem.les16(s, 0xC0 + (i - 1) * 2), safemem.les16(s, 0xC8 + (i - 1) * 2);
                    if (xs[i] + ys[i] < xs[lo] + ys[lo]) then lo = i; end
                    if (xs[i] + ys[i] > xs[hi] + ys[hi]) then hi = i; end
                end
                local function uv(i)
                    local o = 0x50 + (i - 1) * 0x1C;
                    return f32(safemem.le32(s, o + 0x14)), f32(safemem.le32(s, o + 0x18));
                end
                local u0, v0 = uv(lo);
                local u1, v1 = uv(hi);
                if (tex ~= 0 and u0 ~= nil and v0 ~= nil and u1 ~= nil and v1 ~= nil and xs[hi] > xs[lo] and ys[hi] > ys[lo]) then
                    local q = {
                        tex = tex, glyph = name == 'font    font    ', shadow = s:byte(0x2F) == 2 and s:byte(0x31) == 1,
                        x0 = xs[lo], y0 = ys[lo], x1 = xs[hi], y1 = ys[hi], u0 = u0, v0 = v0, u1 = u1, v1 = v1 };
                    -- A part turned in its texture (the target arrow's frames lie on their side there): its
                    -- top-right and bottom-left corners' coordinates too, all four kept (gamepic draws them).
                    local tr, bl = nil, nil;
                    for i = 1, 4 do
                        if (xs[i] == xs[hi] and ys[i] == ys[lo]) then tr = i; end
                        if (xs[i] == xs[lo] and ys[i] == ys[hi]) then bl = i; end
                    end
                    if (tr ~= nil and bl ~= nil) then
                        local tru, trv = uv(tr);
                        local blu, blv = uv(bl);
                        if (tru ~= nil and trv ~= nil and blu ~= nil and blv ~= nil and not (blu == u0 and trv == v0 and tru == u1 and blv == v1)) then
                            q.rot = { u0, v0, tru, trv, u1, v1, blu, blv }; -- (top-left, top-right, bottom-right, bottom-left)
                        end
                    end
                    P.quads[#P.quads + 1] = q;
                end
            end
        end
        node = safemem.le32(nd, 0);
    end
    -- A label whose dark copy isn't flagged as one (the armor menu's Body came out doubled): the same
    -- glyph twice on its texture, a pixel or two apart; the lower-right one is the shadow.
    local qs = P.quads;
    for i = 1, #qs do
        local q = qs[i];
        if (not q.shadow) then
            for j = i + 1, #qs do
                local r = qs[j];
                if ((q.glyph or r.glyph) and not r.shadow and r.tex == q.tex and r.u0 == q.u0 and r.v0 == q.v0 and r.u1 == q.u1 and r.v1 == q.v1) then
                    local dx, dy = r.x0 - q.x0, r.y0 - q.y0;
                    if ((dx ~= 0 or dy ~= 0) and math.abs(dx) <= 2 and math.abs(dy) <= 2) then
                        if (dx + dy > 0) then r.shadow = true; else q.shadow = true; end
                        break;
                    end
                end
            end
        end
    end
    if (npics >= 512) then
        pics, npics = {}, 0;
    end
    pics[sprite], npics = P, npics + 1;
    return P;
end

-- The picture the main menu's Draw puts on option 12: [h + 0x18 + 4k], k = [h+0x14] while byte
-- [h+0x25] is set (usable), else 2 (greyed). 0 when it can't be read.
local function own_picture(h)
    local b = safemem.read(h + 0x14, 0x12);
    if (b == nil) then
        return 0;
    end
    local k = b:byte(0x12) ~= 0 and safemem.le32(b, 0) or 2;
    return (k >= 0 and k <= 2) and safemem.le32(b, 0x04 + k * 4) or 0;
end

-- Whether a Draw is a party menu's (it adds a mark: see marks below), or the command menu's (its
-- options' pictures by id: see player_pics).
local function party_draw(d)
    return d == sigs.get('party.draw') or d == sigs.get('party.seekdraw') or d == sigs.get('playermo.draw')
        or d == sigs.get('linkshell.optdraw');
end

--[[
* The command menu's options (playermo, in the field and in battle: Attack or Switch Target, Magic,
* Abilities, Trust, Items, Disengage...): its Draw (0x12B3C0) draws every one itself, option i (1 to
* byte [h+0x53]) the picture for id word [h + 0x1C + 2(i-1)] (0x12B380: ids 1-27; entry
* [playermo.pics + 12 id]: word the sprite's number, byte +2 its set; the set's object [h + 0x14 +
* 4 set], the sprite word number of the table it points at). Into pp: pp.n the options, pp[i] the
* sprite (0: none). Nil when it can't be read.
--]]
local pp = { n = 0, ids = {} };
local function player_pics(h)
    local b = safemem.read(h + 0x14, 0x40);
    local tbl = sigs.get('playermo.pics');
    if (b == nil or tbl == 0) then
        return nil;
    end
    local count = b:byte(0x40);
    if (count == 0 or count > 30) then
        return nil;
    end
    for i = 1, count do
        local id = safemem.le16(b, 0x08 + (i - 1) * 2);
        local sp = 0;
        local e = (id >= 1 and id < 0x1C) and safemem.read(tbl + id * 12, 4) or nil;
        if (e ~= nil and e:byte(3) < 8) then
            local so = safemem.le32(b, e:byte(3) * 4);
            local t = so ~= 0 and safemem.u32(so) or nil;
            sp = (t ~= nil and t ~= 0) and (safemem.u32(t + safemem.le16(e, 0) * 4) or 0) or 0;
        end
        pp[i], pp.ids[i] = sp, id;
    end
    pp.n = count;
    return pp;
end

-- Whether handler h's menu is an option menu facelift can stand in for (its Draw draws nothing that
-- matters, or a party menu's mark, and it takes input), and whether it's the main menu's: true/false,
-- own, and its Draw.
local function option_menu(h)
    local vt = h ~= nil and h ~= 0 and safemem.u32(h) or nil;
    if (vt == nil or vt == 0) then
        return false, false;
    end
    local fns = safemem.read(vt + 0x10, 0x0C);
    if (fns == nil or safemem.le32(fns, 8) == quiet) then
        return false, false;
    end
    local d = safemem.le32(fns, 0);
    if (not draws_nothing(d) and not party_draw(d)) then
        return false, false;
    end
    return true, d == sigs.get('menuwind.draw'), d;
end

--[[
* The option a party menu's Draw (0x205790) draws itself: option [h+0x14] (-1 none; hidden in the
* menu, as the main menu's 12), its picture [h + 0x20 + 4k], k = [h+0x18] (the menu's Update, 0x2056C0:
* 1 while your target is a player who isn't you with entity flag bit 20 or 21 at +0x124; the two are
* the window pictures 82, as the layout's own for it, and 79): { n, sprite }, or nil.
--]]
local function party_own(h)
    local b = safemem.read(h + 0x14, 0x14);
    local item, k = b ~= nil and safemem.le32(b, 0) or 0xFFFFFFFF, b ~= nil and safemem.le32(b, 4) or 2;
    if (item == 0xFFFFFFFF or item >= 64 or k > 1) then
        return nil;
    end
    return { n = item, sprite = safemem.le32(b, 0x0C + k * 4) };
end

--[[
* The checks the seek languages' Draw (0x205B10) puts on its options, into m.marks[option] = picture
* (none: empty): the check [h+0x34] on each language option i (from 1) whose bit is set in [h+0x2C],
* the bit from the table [party.langbits + 5 language + i - 1] (language [[game.lang] + 8], 0-3).
--]]
local function marks(h, obj, m, d)
    local mk = m.marks;
    for k in pairs(mk) do
        mk[k] = nil;
    end
    if (d == nil or d ~= sigs.get('party.seekdraw')) then
        return;
    end
    local b = safemem.read(h + 0x2C, 0x0C);
    local g = safemem.u32(sigs.get('game.lang'));
    local lang = g ~= nil and g ~= 0 and safemem.u32(g + 8) or nil;
    local tbl = sigs.get('party.langbits');
    local bits = (lang ~= nil and lang <= 3 and tbl ~= 0) and safemem.read(tbl + lang * 5, 5) or nil;
    local count = safemem.read(obj + 0x58, 2);
    if (b == nil or bits == nil or count == nil) then
        return;
    end
    local mask, check = safemem.le32(b, 0), safemem.le32(b, 8);
    for i = 1, math.min(5, safemem.les16(count, 0) - 1) do
        if (math.floor(mask / 2 ^ bits:byte(i)) % 2 == 1) then
            mk[i] = picture(check);
        end
    end
end

-- Fills m from the menu; false (the game's own menu shows) when it isn't an option menu facelift
-- can stand in for, or something doesn't add up.
function A.read(p, m)
    local ok, own, d = option_menu(p.handler);
    if (not ok) then
        return false;
    end
    -- The option the handler draws itself (the main menu's 12, a party menu's): { n, sprite, hidden
    -- (only while the menu hides it) }.
    local drawn, pics = nil, nil;
    if (own) then
        drawn = { n = OWN, sprite = own_picture(p.handler), hidden = true };
    elseif (d == sigs.get('party.draw')) then
        drawn = party_own(p.handler);
    elseif (d == sigs.get('linkshell.optdraw')) then
        -- A linkshell item's menu (link2/3/4/13, notes-linkshell.md class B): option word h+0x14,
        -- hidden in the menu, is the handler's: picture [h + 0x1C + 4 word h+0x16] ('Unequip' / 'Set
        -- as No. 1'); its greying is the menu item's own state.
        local b = safemem.read(p.handler + 0x14, 0x10);
        if (b ~= nil and safemem.le16(b, 2) <= 1) then
            drawn = { n = safemem.le16(b, 0), sprite = safemem.le32(b, 0x08 + 4 * safemem.le16(b, 2)), hidden = true };
        end
    elseif (d == sigs.get('playermo.draw')) then
        pics = player_pics(p.handler);
        if (pics == nil) then
            return false;
        end
    end
    if (not A.read_options(p, m, drawn, pics)) then
        return false;
    end
    for k in pairs(m.cool) do
        m.cool[k] = nil;
    end
    local cd = p.spec ~= nil and p.spec.cooldown ~= nil and p.spec.cooldown[p.menu] or nil;
    for n, secs in pairs(cd or {}) do
        local at = pressed[p.menu .. '/' .. n];
        if (at ~= nil and os.clock() - at < secs) then
            m.cool[n] = true;
        end
    end
    marks(p.handler, p.obj, m, d);
    return true;
end

--[[
* Options hidden for the era (core/era): by the menu's option number, or the command menu's by its
* command id (pics.ids). The ones under a hidden option move up by its height (single columns: same
* x), so the menu closes up; the game's cursor, landing on a hidden option (its keys still go there),
* is moved on along the options' own up/down neighbours (layout record +0x17 / +0x18) in the
* direction it came from, as SetCursor, to the next shown one.
--]]
local last_cursor = {}; -- [menu object] = the cursor last frame
local function era_hidden(menu, pics, num)
    if (not era.on) then
        return false;
    end
    if (pics ~= nil and pics.ids ~= nil) then
        return era.command(pics.ids[num]);
    end
    return era.option(menu, num);
end

-- The options of a menu whose handler another adapter has checked (adapters/yesno): as A.read fills
-- them, and the menu window's own place on screen (wx, wy, ww, wh, UI px: from an option's place and
-- its layout rect, scaled as the game lays it out; wx nil when that can't be told). own: the option
-- the handler draws itself, { n, sprite (its picture), hidden (only while the menu hides it) }, or nil.
-- pics: a handler that draws every option itself (the command menu: player_pics): only options 1 to
-- pics.n, option i's picture pics[i].
function A.read_options(p, m, own, pics)
    local h, obj = p.handler, p.obj;
    if (not p.focused and (menus.game_hides() ~= false or not menus.shown(obj))) then
        return false;
    end
    local mh = safemem.read(obj + 0xB8, 2);
    local yoff = mh ~= nil and safemem.les16(mh, 0) or 0;
    if (menus.rect(obj) == nil) then
        return false;
    end
    -- The window's size in the menu's layout (its resource header +0x10..+0x16: left, top, right,
    -- bottom), which the options' layout rects (+0x32..+0x38, from the window's corner) are in. Not
    -- the frame words: the game refreshes those only while it draws the menu.
    local hdr = safemem.u32(obj + 0x04);
    local wr = hdr ~= nil and hdr ~= 0 and safemem.read(hdr + 0x10, 8) or nil;
    local ww = wr ~= nil and safemem.les16(wr, 4) - safemem.les16(wr, 0) or 0;
    local wh = wr ~= nil and safemem.les16(wr, 6) - safemem.les16(wr, 2) or 0;
    -- The area the options and their pictures cover (not the game's frame, which is sized for every
    -- option the menu can have and can run off the screen), and the box: the same without the ones
    -- wholly outside the window.
    local ax, ay, bx, by = math.huge, math.huge, -math.huge, -math.huge;
    local cx, cy, dx, dy = math.huge, math.huge, -math.huge, -math.huge;
    local wtop = nil; -- the window's top on screen (UI px), from an option's place and its layout rect
    m.wx = nil;
    -- Hidden options (era): their places, and every option's neighbours, first.
    local gaps, navs, present = nil, nil, nil;
    if (era.on and (era.OPTIONS[p.menu] ~= nil or (pics ~= nil and pics.ids ~= nil))) then
        gaps, navs, present = {}, {}, {};
        local nd0 = safemem.u32(obj + 0x14) or 0;
        local k = 0;
        while (nd0 ~= 0 and k < MAX) do
            k = k + 1;
            local nd = safemem.read(nd0, 0x18);
            if (nd == nil) then
                break;
            end
            local el = safemem.le32(nd, 0x10);
            local e = (nd:byte(0x15) == 0 and el ~= 0) and safemem.read(el, 0x3C) or nil;
            if (e ~= nil and safemem.le16(e, 0) == 1) then
                local num = safemem.le16(e, 0x3A);
                local entry = safemem.le32(e, 0x0C);
                local rec = entry ~= 0 and safemem.u32(entry) or nil;
                local nav = rec ~= nil and rec ~= 0 and safemem.read(rec + 0x15, 6) or nil;
                if (nav ~= nil) then
                    navs[num] = { up = nav:byte(3), down = nav:byte(4) };
                end
                if (pics == nil or num <= pics.n) then
                    present[num] = true;
                end
                if (era_hidden(p.menu, pics, num)) then
                    gaps[#gaps + 1] = { x = safemem.les16(e, 0x2A), y = safemem.les16(e, 0x2C), h = safemem.les16(e, 0x30) };
                end
            end
            nd0 = safemem.le32(nd, 0);
        end
        if (#gaps == 0) then
            gaps = nil;
        end
    end
    local n = 0;
    local node = safemem.u32(obj + 0x14) or 0;
    local walked = 0;
    while (node ~= 0 and walked < MAX) do
        walked = walked + 1;
        local nd = safemem.read(node, 0x18);
        if (nd == nil) then
            return false;
        end
        local el = safemem.le32(nd, 0x10);
        if (nd:byte(0x15) == 0 and el ~= 0) then
            local e = safemem.read(el, 0x48);
            if (e == nil) then
                return false;
            end
            local num = safemem.le16(e, 0x3A);
            local drawn = own and num == own.n and (e:byte(0x3D) == 0 or not own.hidden);
            local pic = pics ~= nil and num >= 1 and num <= pics.n and pics[num] or nil;
            if (pics ~= nil and pic == nil) then
                -- (past the handler's options: not drawn)
            elseif (gaps ~= nil and era_hidden(p.menu, pics, num)) then
                -- (hidden for the era)
            elseif (safemem.le16(e, 0) == 1 and (e:byte(0x3D) ~= 0 or drawn or (pic ~= nil and pic ~= 0))) then
                n = n + 1;
                local o = m.opts[n];
                if (o == nil) then
                    o = {};
                    m.opts[n] = o;
                end
                o.n, o.state = safemem.le16(e, 0x3A), safemem.le32(e, 0x10);
                o.x, o.y = safemem.les16(e, 0x2A), safemem.les16(e, 0x2C) + yoff;
                local y0 = o.y; -- (as the game lays it out: the window's place comes from it)
                if (gaps ~= nil) then
                    for _, g in ipairs(gaps) do
                        if (math.abs(g.x - o.x) < 4 and g.y + yoff < y0) then
                            o.y = o.y - g.h; -- (an option above it hidden: the menu closes up)
                        end
                    end
                end
                o.w, o.h = safemem.les16(e, 0x2E), safemem.les16(e, 0x30);
                o.sx, o.sy = f32(safemem.le32(e, 0x1C)) or 1, f32(safemem.le32(e, 0x20)) or 1;
                o.title = safemem.le32(e, 0x44);
                -- A title tab or the like: an item whose six neighbours are all 0xFF.
                local entry = safemem.le32(e, 0x0C);
                local rec = entry ~= 0 and safemem.u32(entry) or nil;
                local nav = rec ~= nil and rec ~= 0 and safemem.read(rec + 0x15, 6) or nil;
                o.deco = nav ~= nil and nav == '\255\255\255\255\255\255';
                o.label = picture((pic ~= nil and pic ~= 0) and pic or (drawn and own.sprite or safemem.le32(e, 0x04)));
                if (o.w <= 0 or o.h <= 0 or o.w > 2000 or o.h > 2000) then
                    return false;
                end
                local l, t, r, b = safemem.les16(e, 0x32), safemem.les16(e, 0x34), safemem.les16(e, 0x36), safemem.les16(e, 0x38);
                o.out = ww > 0 and wh > 0 and (r <= 0 or l >= ww or b <= 0 or t >= wh);
                if (wtop == nil and b > t and o.h > 0 and r > l and o.w > 0) then
                    local sx, sy = o.w / (r - l), o.h / (b - t);
                    wtop = y0 - t * sy; -- the layout's top, scaled as the game lays it out
                    m.wx, m.wy, m.ww, m.wh = o.x - l * sx, wtop, ww * sx, wh * sy;
                end
                -- A title tab or the like counts by its picture alone: its rect can be wider (the
                -- main menu's "Commands" tab starts 16 px left of the buttons).
                local quads = o.label ~= nil and o.label.quads or NONE;
                local x0, y0, x1, y1 = o.x, o.y, o.x + o.w, o.y + o.h;
                if (o.deco and #quads > 0) then
                    x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge;
                end
                for _, q in ipairs(quads) do
                    x0, y0 = math.min(x0, o.x + q.x0 * o.sx), math.min(y0, o.y + q.y0 * o.sy);
                    x1, y1 = math.max(x1, o.x + q.x1 * o.sx), math.max(y1, o.y + q.y1 * o.sy);
                end
                ax, ay, bx, by = math.min(ax, x0), math.min(ay, y0), math.max(bx, x1), math.max(by, y1);
                if (not o.out) then
                    cx, cy, dx, dy = math.min(cx, x0), math.min(cy, y0), math.max(dx, x1), math.max(dy, y1);
                end
            end
        end
        node = safemem.le32(nd, 0);
    end
    if (n == 0) then
        return false;
    end
    for i = n + 1, m.n do
        m.opts[i] = nil;
    end
    m.n = n;
    m.cursor = menus.cursor(obj) or 0;
    if (gaps ~= nil and p.focused and era_hidden(p.menu, pics, m.cursor)) then
        -- On a hidden option: on to the next shown one the way it came (down unless it came up).
        local prev = last_cursor[obj];
        local dir = (prev ~= nil and navs[prev] ~= nil and navs[prev].up == m.cursor) and 'up' or 'down';
        local t = m.cursor;
        for _ = 1, MAX do
            t = navs[t] ~= nil and navs[t][dir] or nil;
            if (t == nil or t == 0 or t == 0xFF or t == m.cursor) then
                t = nil;
                break;
            end
            if (present[t] and not era_hidden(p.menu, pics, t)) then
                break;
            end
        end
        if (t ~= nil and game.call('menu.set_cursor', obj, t)) then
            m.cursor = menus.cursor(obj) or t;
        end
    end
    if (p.focused) then
        last_cursor[obj] = m.cursor;
    end
    if (p.focused) then
        recent[obj] = os.clock();
    else
        -- The game lights the cursor's option only while the menu's byte +0x63 is set (1 from the
        -- menu's ctor; the bag's side menu's Update sets it to whether it has focus).
        local lit = safemem.read(obj + 0x63, 1);
        if (lit == nil or lit:byte(1) == 0) then
            m.cursor = 0;
        end
    end
    -- A few UI px around it all, so nothing sits where ImGui clips a window's edge.
    m.x, m.y, m.w, m.h = math.floor(ax) - 6, math.floor(ay) - 6, math.ceil(bx - ax) + 12, math.ceil(by - ay) + 12;
    if (dx > cx) then
        -- Not above the window's own top (a title tab's picture can reach over it, into what the game
        -- puts above the menu, like the Network panel over the main menu): the tab sits on the edge.
        local top = math.floor(cy) - 6;
        if (wtop ~= nil and top < wtop - 2) then
            top = math.floor(wtop) - 2;
        end
        m.bx, m.by, m.bw, m.bh = math.floor(cx) - 6, top, math.ceil(dx - cx) + 12, math.ceil(dy) + 6 - top;
    else
        m.bx, m.by, m.bw, m.bh = 0, 0, 0, 0;
    end
    return true;
end

-- The option menus shown besides the focused one, in rank order (see the top); worked out once a walk
-- of the open menus, for every rank. taken: the menus other windows name.
local order, pos, built = {}, {}, -1;
local probe, scratch = { focused = false, obj = 0, handler = 0 }, nil;
local function by_rank(x, y)
    local a, b = recent[x], recent[y];
    if (a ~= nil and b ~= nil) then
        return a > b;
    elseif (a ~= nil or b ~= nil) then
        return a ~= nil;
    end
    return pos[x] < pos[y];
end
local function shown_besides(taken)
    local w = menus.walks();
    if (built == w) then
        return order;
    end
    built = w;
    for i = #order, 1, -1 do
        order[i] = nil;
    end
    local open = menus.open();
    for obj in pairs(recent) do
        if (open[obj] == nil) then
            recent[obj] = nil;
        end
    end
    local f = menus.focused();
    local fobj = f ~= nil and f.obj or 0;
    scratch = scratch or A.new();
    for i, obj in ipairs(menus.order()) do
        local name = open[obj];
        if (obj ~= fobj and name ~= nil and not (taken ~= nil and taken[name])) then
            probe.obj, probe.handler = obj, safemem.u32(obj + 0x0C) or 0;
            if (A.read(probe, scratch)) then
                order[#order + 1], pos[obj] = obj, i;
            end
        end
    end
    table.sort(order, by_rank);
    return order;
end

-- A part's menu besides the focused one (show = 'open', rank = k): the k-th of those shown.
function A.locate(p, taken)
    local obj = shown_besides(taken)[p.spec.rank or 1];
    if (obj == nil) then
        return nil;
    end
    return obj, safemem.u32(obj + 0x0C) or 0;
end

local now = A.new();

A.picture = picture; -- (a sprite as quads: the scroll lists' picture cells too)

A.actions = {
    -- The game's cursor to option n (SetCursor, as the mouse over it: a window whose buttons are laid
    -- out other than the game's, moved with other keys).
    point = function (p, m, n)
        game.call('menu.set_cursor', p.obj, n);
    end,
    -- Option n: the cursor moved there, then Enter on it, as the game's mouse does (not while it
    -- cools down).
    select = function (p, m, n)
        if (not A.read(p, now) or now.cool[n]) then
            return;
        end
        for i = 1, now.n do
            local o = now.opts[i];
            if (o.n == n and not o.deco and o.state ~= 5 and o.state ~= 0x10) then
                if (game.call('menu.set_cursor', p.obj, n) and menus.cursor(p.obj) == n) then
                    local cd = p.spec ~= nil and p.spec.cooldown ~= nil and p.spec.cooldown[p.menu] or nil;
                    if (cd ~= nil and cd[n] ~= nil) then
                        pressed[p.menu .. '/' .. n] = os.clock();
                    end
                    game.call('menu.input', p.obj, 5);
                end
                return;
            end
        end
    end,
};

return A;
