--[[
* facelift - windows/runtime
* Runs the windows (windows/init) every frame:
*   1. finds each part's game menu: the focused one, or (show = 'open') one that's open under it
*      (a window that follows others has no parts: it shows beside the one of them drawn; one
*      that's always up has none either: it shows whenever the game shows its interface)
*   2. reads it through its adapter; a focused part that doesn't read right means the game's own
*      window shows, untouched
*   3. hides the game's menus the window covers, places the window (layout/place) and draws its pane
*   4. after the window is drawn, does what was clicked, through the adapters
* A window that hits an error is closed off cleanly (ImGui's stacks unwound, its game menus shown
* again) and stays off for the session; the others carry on.
--]]

local imgui = require('ui.gui');
local theme = require('ui.theme');
local menus = require('core.menus');
local hide  = require('core.hide');
local sigs  = require('core.sigs');
local safemem = require('core.safemem');
local game  = require('core.game');
local place = require('layout.place');
local store = require('layout.store');
local clock = require('core.clock');
local perf = require('core.perf');
local edit  = require('layout.edit');

local runtime = {
    notify = function (w, err) end, -- set by facelift.lua: tells the player a window turned off
    measure = false,                -- time each window (w.cost, ms; the inspector shows it)
    by_id = {},
    list = {},
};

local NONE = {};
local frames = 0;
local PICK_FOR = 2;    -- seconds a pick made through another menu stays good
local LOOK_EVERY = 30; -- frames between looks for an 'open' part that wasn't open (else on focus changes)
local MAX = { 4000, 4000 };

-- How the menu on top is left when a part is picked through it (see windows/init, through): closed,
-- or (a storage's pair, notes-storage.md) the game's own Left / Right to the other half.
local closers = {
    close_obj = function (focus)
        game.call('menu.close_obj', menus.manager(), focus.obj, 1);
    end,
    left = function (focus)
        game.call('menu.input', focus.obj, 3);
    end,
    right = function (focus)
        game.call('menu.input', focus.obj, 4);
    end,
};
local CLOSER_SIG = { close_obj = 'menu.close_obj', left = 'menu.input', right = 'menu.input' };

local loaded = {};
local function load(kind, name)
    local key = kind .. '.' .. name;
    if (loaded[key] == nil) then
        loaded[key] = require(key);
    end
    return loaded[key];
end

-- A window from its spec, ready to run.
function runtime.make(spec)
    local w = {
        spec = spec, id = spec.id, parts = {}, part = {}, reqs = {}, sigs = {},
        queue = {}, n = 0, pending = nil,
        place = {}, anchor = {}, pos = { 0, 0 }, size = { 0, 0 }, min = { 0, 0 }, pivot = { 0, 0 },
        rect = { x = 0, y = 0, w = 0, h = 0 }, drawn = -1, env = {},
        name = spec.name or spec.title or spec.id,
        off = false, fault = nil, ready = nil, misses = 0,
    };
    -- An option's value: the player's (layout edit mode), else the window's default.
    w.opt = function (name)
        local o = store.get(spec.id);
        -- (rawget: the saved tables are Ashita's T{}, whose methods (all, any, ...) would answer a name)
        local v = o ~= nil and type(o.opts) == 'table' and rawget(o.opts, name) or nil;
        if (v ~= nil) then
            return v;
        end
        local d = spec.options ~= nil and spec.options[name] or nil;
        return d ~= nil and d.default or nil;
    end;
    -- Sets an option (kept with the window's layout, saved at once).
    w.set_opt = function (name, v)
        local o = store.get(spec.id);
        local t = {};
        for k, x in pairs(o ~= nil and o.opts or NONE) do
            t[k] = x;
        end
        t[name] = v;
        store.set(spec.id, { opts = t });
        store.save();
    end;
    local seen = {};
    local function need(s)
        if (s ~= nil and not seen[s]) then
            seen[s] = true;
            w.sigs[#w.sigs + 1] = s;
        end
    end
    w.req = function (part, action, arg)
        w.n = w.n + 1;
        local q = w.queue[w.n];
        if (q == nil) then
            q = {};
            w.queue[w.n] = q;
        end
        q.part, q.action, q.arg = part, action, arg;
    end
    for i, ps in ipairs(spec.parts or NONE) do
        local A = load('adapters', ps.adapter);
        local p = { name = ps.name, spec = ps, adapter = A, model = A.new(), menus = {},
                    obj = 0, handler = 0, menu = nil, focused = false, live = false, armed = false };
        if (ps.menus == '*') then
            p.any = true; -- any focused menu no other window names (its adapter decides)
        else
            for _, n in ipairs(ps.menus) do
                p.menus[n] = true;
            end
        end
        for _, s in ipairs(A.sigs or NONE) do
            need(s);
        end
        need(ps.vtable);
        if (type(ps.oninput) == 'table') then
            for _, s in ipairs(ps.oninput) do
                need(s);
            end
        else
            need(ps.oninput);
        end
        for _, how in pairs(ps.through or NONE) do
            need(CLOSER_SIG[how]);
        end
        w.parts[i], w.part[ps.name] = p, p;
        w.reqs[ps.name] = function (action, arg) w.req(ps.name, action, arg); end;
    end
    w.pane = load('panes', spec.pane);
    w.pane_state = w.pane.new(spec);
    local L = spec.layout;
    w.flags = bit.bor(L.auto and ImGuiWindowFlags_AlwaysAutoResize or 0, L.z == 'under' and ImGuiWindowFlags_NoBringToFrontOnFocus or 0,
        spec.scroll == false and bit.bor(ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoScrollWithMouse) or 0,
        spec.background == false and ImGuiWindowFlags_NoBackground or 0);
    runtime.by_id[spec.id] = w;
    runtime.list[#runtime.list + 1] = w;
    return w;
end

-- The window's layout: its own, with the player's changes on top (rebuilt only when those change).
local function effective(w)
    local o = store.get(w.id);
    if (w.eff == nil or o ~= w.eff_src) then
        local L = {};
        for k, v in pairs(w.spec.layout) do
            L[k] = v;
        end
        for k, v in pairs(o or NONE) do
            if (k ~= 'fs' and k ~= 'opts') then
                L[k] = v;
            end
        end
        w.eff, w.eff_src = L, o;
    end
    return w.eff, o;
end

-- Whether the game's code the window needs was all found.
function runtime.ready(w)
    if (w.ready == nil) then
        w.ready = sigs.ok(w.sigs);
    end
    return w.ready;
end

-- A window that follows others shows with the first of them drawn this frame (they come before it
-- in windows/init), as w.lead; its pane reads that window.
local function lead(w)
    w.lead = nil;
    for _, id in ipairs(w.spec.follows) do
        local t = runtime.by_id[id];
        if (t ~= nil and t ~= w and t.drawn == frames) then
            w.lead = t;
            return true;
        end
    end
    return false;
end

--[[
* The menus some window names (its parts' menus and the ones it suppresses), on or off: a part of
* any menu ('*') leaves those to their own windows, or to the game when those are off. A part with
* claim = false only follows its menu (with cover = false: another window draws it).
--]]
local named = nil;
local function claimed()
    if (named == nil) then
        named = {};
        for _, w in ipairs(runtime.list) do
            for _, ps in ipairs(w.spec.parts or NONE) do
                if (type(ps.menus) == 'table' and ps.claim ~= false) then
                    for _, n in ipairs(ps.menus) do
                        named[n] = true;
                    end
                end
            end
            if (type(w.spec.suppress) == 'table') then
                for _, n in ipairs(w.spec.suppress) do
                    named[n] = true;
                end
            end
        end
    end
    return named;
end

--[[
* Typing in the chat: the chat's input takes focus, but the menu that had it is still up in the game
* (a price box half typed in). A part of that menu is shown as it was, for looking only (clicks are
* dropped, as for any part without focus), until focus comes back. Only windows that name their menus:
* the option menus' windows show a menu without focus anyway.
--]]
local TYPING = { inline = true, chatctrl = true };
local before = { obj = 0, name = nil, handler = 0 }; -- the last focus that wasn't the chat's input
local held = nil; -- before, while the chat's input has focus and that menu is still open

-- 1, 2: finds and reads the window's parts; false if it isn't to show.
local function parts(w, focus, look)
    local spec = w.spec;
    local focused, dead, open_live = false, false, false;
    for _, p in ipairs(w.parts) do
        p.focused, p.live, p.obj, p.handler, p.menu, p.held = false, false, 0, 0, nil, false;
        if (focus ~= nil and (p.menus[focus.name] or (p.any and p.spec.show ~= 'open' and focus.name ~= nil and not claimed()[focus.name]))) then
            p.focused, p.obj, p.handler, p.menu = true, focus.obj, focus.handler, focus.name;
            focused = true;
        elseif (held ~= nil and p.menus[held.name]) then
            p.obj, p.handler, p.menu, p.held = held.obj, held.handler, held.name, true;
        elseif (p.spec.show == 'open' and p.spec.by_name) then
            -- (found by its menu's name when it's open: the first of its menus that is)
            for _, n in ipairs(p.spec.menus) do
                local obj = menus.find(n);
                if (obj ~= nil) then
                    p.obj, p.handler, p.menu = obj, safemem.u32(obj + 0x0C) or 0, n;
                    break;
                end
            end
        elseif (p.spec.show == 'open' and (p.armed or look or p.spec.watch)) then
            local obj, h = p.adapter.locate(p, claimed());
            if (obj ~= nil) then
                p.obj, p.handler, p.menu = obj, h, menus.open()[obj];
            end
        end
        if (p.obj ~= 0) then
            p.live = p.adapter.read(p, p.model) == true;
        end
        p.armed = p.live;
        if (p.focused and not p.live and p.spec.optional) then
            p.focused = false; -- (an optional part, not this menu after all: another part's, or none)
        elseif (p.focused and not p.live) then
            dead = true;
        elseif (p.live and (p.spec.show == 'open' or p.held)) then
            open_live = true;
        end
    end
    focused = false;
    for _, p in ipairs(w.parts) do
        focused = focused or p.focused;
    end
    if (dead) then
        w.misses = w.misses + 1;
        return false;
    end
    if (not focused and not open_live) then
        return false;
    end
    for _, name in ipairs(spec.needs_open or NONE) do
        if (menus.find(name) == nil) then
            return false;
        end
    end
    return true;
end

--[[
* A layout's dock list ({ { target, at = 'bl' or 'tr', dx, dy, unless = id or { ids }, with = id },
* ... }): the first of those windows that's up (this frame or the last) with room beside it for this
* one decides where it goes (as from = 'window'); an entry is skipped while an unless window is up (it
* would land on it), or while its with window isn't. With none, the layout's own anchor. The choice
* holds while the window stays up (it doesn't jump as its height changes), until its entry can't be
* used any more (target gone, an unless window up, its with window gone). A player who
* moved it has their own offset for that spot (o.docks).
--]]
local function up(id, w)
    local t = id ~= nil and runtime.by_id[id] or nil;
    return t ~= nil and t ~= w and not t.off and t.drawn >= frames - 1;
end

-- Whether window id was drawn this frame or the last (its rect is where it is).
function runtime.up(id)
    return up(id, nil);
end

-- Where window id was last drawn (screen px: x, y, w, h) if that was within n frames, else nil.
function runtime.recent(id, n)
    local t = runtime.by_id[id];
    if (t == nil or t.off or t.drawn < frames - n or t.rect.w <= 0) then
        return nil;
    end
    return t.rect.x, t.rect.y, t.rect.w, t.rect.h;
end

-- Whether dock entry d can be used now: its target up, its 'with' window up (when it names one), and
-- none of its 'unless' windows (one id or a list) up.
local function usable(d, w)
    if (not up(d.target, w) or (d.with ~= nil and not up(d.with, w))) then
        return false;
    end
    if (type(d.unless) == 'table') then
        for _, id in ipairs(d.unless) do
            if (up(id, w)) then
                return false;
            end
        end
        return true;
    end
    return not up(d.unless, w);
end

local function docked(w, L, o, we)
    if (L.dock == nil or (o ~= nil and o.from ~= nil)) then
        return L;
    end
    if (w.drawn < frames - 1) then
        w.dock_pick = nil; -- it wasn't up: choose again
    end
    local pick = w.dock_pick;
    if (pick ~= nil and not usable(L.dock[pick], w)) then
        pick = nil;
    end
    if (pick == nil) then
        local bw = type(L.w) == 'number' and L.w * we.fs or 0;
        local bh = w.rect.h > 0 and w.rect.h or 240 * we.fs;
        for i, d in ipairs(L.dock) do
            if (usable(d, w)) then
                local r = runtime.by_id[d.target].rect;
                if ((d.at == 'bl' and r.y + r.h + (d.dy or 0) + bh <= we.dh - 4)
                        or (d.at == 'tr' and r.x + r.w + (d.dx or 0) + bw <= we.dw - 4)) then
                    pick = i;
                    break;
                end
            end
        end
    end
    w.dock_pick = pick;
    if (pick == nil) then
        return L;
    end
    w.docks = w.docks ~= nil and w.docks_src == L and w.docks or {};
    w.docks_src = L;
    local D = w.docks[pick];
    if (D == nil) then
        local d = L.dock[pick];
        local mine = o ~= nil and o.docks ~= nil and o.docks[d.target .. '/' .. d.at] or nil;
        D = {};
        for k, v in pairs(L) do
            D[k] = v;
        end
        D.from, D.target, D.at, D.dock, D.docked = 'window', d.target, d.at, nil, true;
        D.dx, D.dy = (mine or d).dx or 0, (mine or d).dy or 0;
        w.docks[pick] = D;
    end
    return D;
end

--[[
* A layout's avoid list ({ id, ... }): windows this one mustn't cover (the item tooltip, where the
* game put its own, over facelift's chat box, taller than the game's log; the bag's list beside
* another list, both wider than the game's). Landing on one, it moves the least way that clears it
* and stays on the screen: above, below, to its right or to its left (else it stays); with avoid_side,
* to its right or left whenever either has room, above or below only when neither has. Its size is
* last frame's (it fits its content); not while the player has placed it themselves or is editing.
--]]
local function avoid(w, L, o, pl, we)
    if (L.avoid == nil or edit.on or (o ~= nil and (o.dx ~= nil or o.dy ~= nil or o.x ~= nil))) then
        return;
    end
    local ww = pl.has_size and pl.w or w.rect.w;
    local wh = w.rect.h;
    if (ww <= 0 or wh <= 0) then
        return;
    end
    local x0, y0 = pl.x - pl.px * ww, pl.y - pl.py * wh;
    for _, id in ipairs(L.avoid) do
        if (up(id, w)) then
            local r = runtime.by_id[id].rect;
            if (x0 < r.x + r.w and x0 + ww > r.x and y0 < r.y + r.h and y0 + wh > r.y) then
                local best, bx, by = nil, x0, y0;
                local function try(nx, ny)
                    if (nx >= 4 and ny >= 4 and nx + ww <= we.dw - 4 and ny + wh <= we.dh - 4) then
                        local d = math.abs(nx - x0) + math.abs(ny - y0);
                        if (best == nil or d < best) then
                            best, bx, by = d, nx, ny;
                        end
                    end
                end
                if (L.avoid_side) then
                    -- (beside it when there's room either side, else above or below)
                    try(r.x + r.w + 4, y0);
                    try(r.x - 4 - ww, y0);
                end
                if (best == nil) then
                    try(x0, r.y - 4 - wh);
                    try(x0, r.y + r.h + 4);
                    try(r.x + r.w + 4, y0);
                    try(r.x - 4 - ww, y0);
                end
                x0, y0 = bx, by;
            end
        end
    end
    pl.x, pl.y = x0 + pl.px * ww, y0 + pl.py * wh;
end

-- Whether a window with takes_if takes its parts and suppressed menus now: that option on, or that
-- function(w, focus) true.
local function takes(w, focus)
    local t = w.spec.takes_if;
    if (t == nil) then
        return true;
    elseif (type(t) == 'function') then
        return t(w, focus) == true;
    end
    return w.opt(t) == 1;
end

local function step(w, focus, env, look)
    local spec = w.spec;
    w.lingering = false;
    -- A window standing aside while another is up (unless_up), or while a game menu is open (unless_open),
    -- or while another lingers (unless_lingering: this frame's, for one before it in windows/init).
    for _, id in ipairs(spec.unless_up or NONE) do
        if (up(id, w)) then
            return;
        end
    end
    for _, id in ipairs(spec.unless_lingering or NONE) do
        local t = runtime.by_id[id];
        if (t ~= nil and t ~= w and t.lingering and t.drawn >= frames - 1) then -- (not one since switched off)
            return;
        end
    end
    for _, name in ipairs(spec.unless_open or NONE) do
        if (menus.find(name) ~= nil) then
            return;
        end
    end
    -- And one that shows only while another is up (while_up: any of them; ahpro's item tooltip).
    if (spec.while_up ~= nil) then
        local any = false;
        for _, id in ipairs(spec.while_up) do
            any = any or up(id, w);
        end
        if (not any) then
            return;
        end
    end
    if (spec.follows ~= nil) then
        if (not lead(w)) then
            return;
        end
    elseif (spec.always) then
        if (menus.game_hides() == true) then
            return; -- (the game's interface hidden, or a cutscene: none of it shows)
        end
        if (#w.parts > 0 and takes(w, focus)) then
            parts(w, focus, look); -- (its parts, when their menus are up: up without them all the same)
        else
            for _, p in ipairs(w.parts) do
                p.live, p.focused = false, false;
            end
        end
    elseif (not parts(w, focus, look)) then
        -- A window that lingers (spec.linger(w) true) once its menus are gone: drawn on as it was last
        -- read, for looking only (its parts aren't live: nothing asked of them reaches the game), where
        -- it was. The price history while the game asks about the sale (the game closed it to ask).
        if (spec.linger == nil or w.drawn < 0 or not spec.linger(w)) then
            return;
        end
        w.lingering = true;
    end

    -- A pick made through another menu, now that its part has focus again.
    local pd = w.pending;
    if (pd ~= nil) then
        local p = w.part[pd.part];
        if (p.focused and p.live) then
            w.pending = nil;
            if (os.clock() - pd.at < PICK_FOR) then
                p.adapter.actions[pd.action](p, p.model, pd.arg);
            end
        end
    end

    -- 3: hide, place, draw.
    for _, p in ipairs(w.parts) do
        if (p.live and p.spec.cover ~= false and not p.model.keep_game) then
            -- (keep_game: the adapter needs the game's own drawing this frame; reopens: the game opens
            -- the menu again every frame, which takes its layer from the game's table)
            hide.cover(p.obj, w, p.spec.reopens and p.menu or nil);
        end
    end
    if (takes(w, focus)) then
        for _, name in ipairs(spec.suppress or NONE) do
            hide.cover(menus.find(name), w);
        end
    end

    local L, o = effective(w);
    local we = w.env;
    we.scale, we.dw, we.dh, we.fs = env.scale, env.dw, env.dh, env.fs * (o ~= nil and o.fs or 1);
    we.focus = focus ~= nil and focus.name or nil; -- the game menu with focus, for panes
    we.frame = frames;                               -- panes tell a new opening by a gap
    L = docked(w, L, o, we);
    -- The part's own game rect (sizes follow it), and what the window is placed from.
    local ap = (L.part ~= nil and w.part[L.part]) or w.parts[1];
    local own = nil;
    if (ap == nil) then
        own = nil; -- no game menu of its own
    elseif (spec.layout.from == 'model') then
        own = ap.model;
    else
        local x, y, rw, rh = menus.rect(ap.obj);
        -- A part that knows its window's height better than the game's frame (whose words refresh only
        -- while the game draws the menu, and facelift hides it): that height, the bottom kept.
        if (x ~= nil and L.fit == 'model' and ap.model ~= nil and (ap.model.fit_h or 0) > 0) then
            y, rh = y + rh - ap.model.fit_h, ap.model.fit_h;
        elseif (x ~= nil and L.fit == 'model_top' and ap.model ~= nil and (ap.model.fit_h or 0) > 0) then
            rh = ap.model.fit_h; -- (the top kept)
        end
        if (x ~= nil) then
            own = w.anchor;
            own.x, own.y, own.w, own.h = x, y, rw, rh;
            -- Bigger than the game's (grow): about the bottom right of its own rect or another menu's.
            local k = 1;
            if (L.grow ~= nil and L.grow.opt ~= nil) then -- (a percent option, its window's or another's)
                local ow = L.grow.of ~= nil and runtime.by_id[L.grow.of] or w;
                k = math.max(0.5, math.min(((ow ~= nil and ow.opt(L.grow.opt)) or 100) / 100, 4));
            elseif (L.grow ~= nil) then
                k = L.grow[1] or 1;
            end
            if (k ~= 1) then
                local cx, cy = x + rw, y + rh;
                local about = L.grow.about ~= nil and menus.find(L.grow.about) or nil;
                local ax, ay, aw, ah = nil, nil, nil, nil;
                if (about ~= nil and menus.shown(about)) then
                    ax, ay, aw, ah = menus.rect(about);
                end
                if (ax ~= nil) then
                    cx, cy = ax + aw, ay + ah;
                end
                own.x, own.y, own.w, own.h = cx + (x - cx) * k, cy + (y - cy) * k, rw * k, rh * k;
            end
            w.grow = k;
        end
    end
    local a = own;
    if (L.from == 'screen') then
        a = nil;
    elseif (L.from == 'window') then
        local t = L.target ~= nil and runtime.by_id[L.target] or w.lead;
        a = (t ~= nil and t ~= w and t.drawn >= frames - 1) and t.rect or nil;
    end
    w.n = 0;
    -- Decided before any SetNextWindow call: ImGui would give those to whichever window begins next.
    if (w.pane.visible ~= nil and not edit.on and not w.pane.visible(w.pane_state, w)) then
        return; -- the game's menus stay hidden; there's just nothing to show
    end
    local pl = w.place;
    if (place.resolve(L, a, we, pl, own) and not edit.held(w)) then
        -- A pane that needs its window wider than the layout gives (the bag's grid): that wide,
        -- kept on the screen.
        local want = w.pane.width ~= nil and w.pane.width(w.pane_state, w, we) or nil;
        if (want ~= nil and pl.has_size and want > pl.w) then
            local left = pl.x - pl.px * pl.w;
            if (L.align == 'right') then
                left = left + pl.w - want; -- (lined up on the right: it grows to the left)
            end
            pl.w = want;
            if (L.clamp) then
                left = math.max(4, math.min(left, we.dw - want - 4));
            end
            pl.x = left + pl.px * want;
        end
        -- And taller (the target's bar): lined up on the bottom, it grows upward.
        local wanth = w.pane.height ~= nil and w.pane.height(w.pane_state, w, we) or nil;
        if (wanth ~= nil and pl.has_size and wanth > pl.h) then
            local top = pl.y - pl.py * pl.h;
            if (L.valign == 'bottom') then
                top = top + pl.h - wanth;
            end
            pl.h = wanth;
            if (L.clamp) then
                top = math.max(4, math.min(top, we.dh - wanth - 4));
            end
            pl.y = top + pl.py * wanth;
        end
        -- A pane that sizes its window itself, before it begins (the chat box: its rows open, so a row
        -- opening moves only its top, with no frame of the old size): its width and height, either nil
        -- for the layout's.
        if (w.pane.size ~= nil and pl.has_size) then
            local sw, sh = w.pane.size(w.pane_state, w, we);
            pl.w, pl.h = sw or pl.w, sh or pl.h;
        end
        avoid(w, L, o, pl, we);
        -- Kept on the screen whole (layout clamp): a window as tall or wide as its content is placed
        -- before it's drawn (layout/place takes it to be 40 px), so its size last frame is used.
        if (L.clamp and we.dw ~= nil and we.dw > 0 and w.drawn >= frames - 2) then
            local ww = (pl.has_size and pl.w > 0) and pl.w or w.rect.w;
            local wh = (pl.has_size and pl.h > 0) and pl.h or w.rect.h;
            local left, top = pl.x - pl.px * ww, pl.y - pl.py * wh;
            left = math.max(4, math.min(left, we.dw - ww - 4));
            top = math.max(4, math.min(top, we.dh - wh - 4));
            pl.x, pl.y = left + pl.px * ww, top + pl.py * wh;
        end
        w.pos[1], w.pos[2] = pl.x, pl.y;
        if (L.from == 'screen' or pl.px ~= 0 or pl.py ~= 0) then
            w.pivot[1], w.pivot[2] = pl.px, pl.py;
            imgui.SetNextWindowPos(w.pos, ImGuiCond_Always, w.pivot);
        else
            imgui.SetNextWindowPos(w.pos, ImGuiCond_Always);
        end
        if (pl.has_size) then
            w.size[1], w.size[2] = pl.w, pl.h;
            imgui.SetNextWindowSize(w.size, ImGuiCond_Always);
        end
        if (pl.has_min) then
            w.min[1], w.min[2] = pl.min_w, pl.min_h;
            imgui.SetNextWindowSizeConstraints(w.min, MAX);
        end
    end

    -- A window as tall as its game window (fit_height): padding that makes one line fill it.
    local pad_y = nil;
    if (spec.fit_height and own ~= nil and own.h ~= nil and own.h > 0) then
        pad_y = math.max(2, (own.h * we.scale - imgui.GetFontSize() * we.fs) / 2);
    end
    local flags = w.flags;
    -- A window moved by Shift + drag (movable = 'shift'): while Shift is held (or it's being dragged) it
    -- can be moved, and takes the mouse even with mouse = false (the recast bars: else the mouse goes
    -- through to the game); one that takes the mouse anyway (the map) keeps it for its own controls.
    local shifted = false;
    if (spec.movable == 'shift' and not edit.on) then
        shifted = w.grabbed == true or imgui.GetIO().KeyShift == true;
    end
    if (((spec.mouse == false and not shifted) or (spec.mouse == 'unscaled' and (w.grow or 1) == 1)) and not edit.on) then
        flags = bit.bor(flags, ImGuiWindowFlags_NoMouseInputs); -- the game gets the mouse there
    end
    -- A window's own background opacity (spec.bg: its options <bg>_own, on, and <bg>, a percent).
    local bg_a = nil;
    if (spec.bg ~= nil and w.opt(spec.bg .. '_own') == 1) then
        bg_a = (w.opt(spec.bg) or 0) / 100;
    end
    local area = theme.begin_area(spec.look); -- (its part of the interface's own theme, if it has one)
    if (theme.window(spec.imgui, we.fs, flags, edit.on or ((spec.movable == true or shifted) and 'quiet'), spec.solid, pad_y, bg_a)) then
        local r = w.rect;
        r.x, r.y = imgui.GetWindowPos();
        r.w, r.h = imgui.GetWindowSize();
        w.drawn = frames;
        if (edit.on) then
            edit.chrome(w, L, a, own, we, pl, runtime.list);
        elseif (spec.movable == true or shifted) then
            edit.drag(w, L, a, own, we, pl, true); -- (dragged by its empty space, kept where it's dropped)
        end
        w.pane.draw(w.pane_state, w, we);
    end
    theme.finish();
    if (area) then
        theme.end_area();
    end
    if (edit.on) then
        w.n = 0; -- nothing reaches the game while editing
    end

    -- 4: what was clicked. A part that has focus does it now (and a part with acts while another of the
    -- window's has: it works the game's menus itself, adapters/ahpath); one under the focused menu,
    -- only through it (and then once it has focus again); otherwise it's for looking only.
    local any = false; -- (a part of this window, or a menu it covers, has focus: a part with acts may act then too)
    for _, p in ipairs(w.parts) do
        any = any or p.focused;
    end
    for _, name in ipairs(spec.suppress or NONE) do
        any = any or (focus ~= nil and focus.name == name);
    end
    for i = 1, w.n do
        local q = w.queue[i];
        local p = w.part[q.part];
        if (p ~= nil and p.live) then
            if (p.focused or (p.spec.acts and any)) then
                p.adapter.actions[q.action](p, p.model, q.arg);
            elseif (focus ~= nil and p.spec.through ~= nil and p.spec.through[focus.name] ~= nil) then
                w.pending = { part = q.part, action = q.action, arg = q.arg, at = os.clock() };
                closers[p.spec.through[focus.name]](focus);
            end
        end
    end
    w.n = 0;
end

local function run(w, focus, env, look)
    local t0 = (runtime.measure or perf.on) and clock.now() or nil;
    local k0 = perf.on and collectgarbage('count') or nil;
    local gm, tm = imgui.mark(), theme.mark();
    local ok, err = xpcall(step, debug.traceback, w, focus, env, look);
    if (t0 ~= nil) then
        local ms = (clock.now() - t0) * 1000;
        w.cost = w.cost ~= nil and (w.cost * 0.9 + ms * 0.1) or ms;
        perf.add('w:' .. tostring(w.id), ms, 1, k0 and (collectgarbage('count') - k0));
    end
    if (not ok) then
        imgui.unwind(gm);
        theme.unwind(tm);
        hide.uncover(w);
        w.off, w.fault, w.n, w.pending = true, err, 0, nil;
        runtime.notify(w, err);
    end
end


-- One frame: focus is core/menus.focused(); on(w) says whether the player has the window switched on.
local last_focus = 0;

function runtime.frame(windows, focus, env, on)
    local f = focus ~= nil and focus.obj or 0;
    held = nil;
    if (focus ~= nil and TYPING[focus.name]) then
        if (before.obj ~= 0 and menus.open()[before.obj] == before.name) then
            held = before;
        end
    elseif (focus ~= nil) then
        before.obj, before.name, before.handler = focus.obj, focus.name, focus.handler;
    end
    frames = frames + 1;
    runtime.scale = env.scale;
    local look = f ~= last_focus or frames % LOOK_EVERY == 0;
    last_focus = f;
    for _, w in ipairs(windows) do
        w.enabled = not w.off and on(w) and runtime.ready(w); -- (switched on and working: others may ask)
        if (w.enabled) then
            run(w, focus, env, look);
        end
    end
end

return runtime;
