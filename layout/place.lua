--[[
* facelift - layout/place
* Where a window goes and how big it is, from its layout and an anchor rectangle. Plain numbers in
* and out (no ImGui), so it can be tested on its own.
*
* A layout (windows/*.lua, layout = { ... }, with the player's changes from layout/store on top):
*   from   = 'menu'    over the part's game menu (its rect, in the game's UI pixels)
*            'model'   over the rect in the part's model (x/y/w/h, UI pixels)
*            'screen'  at x, y (fractions of the screen), the window's own point px, py (0-1) there
*            'window'  next to another facelift window (target = its id): its corner at = 'tr' (to
*                      the right, tops level), 'bl' (below, left edges level), 'br' or 'tl'
*   part   = name      which part (default: the window's first)
*   dx, dy = n         moved by this much from there (UI pixels; screen pixels next to a window)
*   valign = 'bottom'            line up the bottom edges (the window grows upward; pivot py = 1)
*   align  = 'left' or 'right'   line up the left (default) or right edges with the anchor (a window
*                                as wide as its content: its right edge, through the pivot px = 1)
*   w, h   = n                   size, times the text size (h 0: fit the content)
*            { 'from', min = n } the anchor's width, at least n times the text size
*   min    = { w = ..., h = 'from' }  instead of a size: at least this big (w as above; h the anchor's)
*   clamp  = true      keep it on screen (4 px in from each edge)
*   auto   = true      grow and shrink with the content
*   z      = 'under'   don't come to the front when clicked (a list under its item menu)
*   avoid  = { id, ... }  windows not to cover: moved above (else below) one it lands on (the
*                      runtime does this, from the window's last height)
*   fit    = 'model'   ('menu') the game's rect as tall as the part's model says (model.fit_h, UI px),
*                      its bottom kept ('model_top': its top): for a menu the game sizes as it draws
*                      it, and facelift hides
*   grow   = { k, about = name }  ('menu') the game's rect k times as big (or { opt = name, of = id }:
*                      a percent option of this window's, or window id's), about the bottom right of
*                      game menu name's (default its own), so windows the game stacks stay stacked;
*                      the window's w.grow = k, for a pane drawing in the game's layout (the runtime)
--]]

local place = {};

local function valid(v)
    return v ~= nil and v > 0 and v < 4000;
end

local function size(spec, aw, scale, fs)
    if (type(spec) == 'number') then
        return spec * fs;
    end
    if (spec == 'from') then
        return valid(aw) and aw * scale or 0;
    end
    if (type(spec) == 'table' and spec[1] == 'from') then
        return math.max(valid(aw) and aw * scale or 0, (spec.min or 0) * fs);
    end
    return 0;
end

local NONE = {};
local CORNERS = { tl = { 0, 0 }, tr = { 1, 0 }, bl = { 0, 1 }, br = { 1, 1 } };

--[[
* Fills out = { x, y, w, h, has_size, min_w, min_h, has_min, px, py } for layout L with env =
* { scale, fs, dw, dh } (dw/dh: the screen). a: where it's placed from ({ x, y, w, h }; UI pixels for
* 'menu' and 'model', screen pixels for 'window'; not used for 'screen'). own: the part's own game
* rect (UI pixels), which 'from' sizes follow wherever the window is placed (default a). Sizes are
* filled in any case; returns false when there's no anchor (the window stays where it was).
--]]
function place.resolve(L, a, env, out, own)
    a = a or NONE;
    own = own or a;
    local from = L.from or 'menu';
    local scale = env.scale;
    local fs = env.fs;
    out.has_size, out.has_min, out.px, out.py = false, false, 0, 0;
    if (L.min ~= nil) then
        out.has_min = true;
        out.min_w = size(L.min.w, own.w, scale, fs);
        out.min_h = L.min.h == 'from' and (valid(own.h) and own.h * scale or 0) or size(L.min.h, own.h, scale, fs);
        out.w, out.h = out.min_w, out.min_h;
    else
        out.has_size = true;
        out.w = size(L.w, own.w, scale, fs);
        out.h = size(L.h or 0, own.h, scale, fs);
    end

    if (from == 'screen') then
        out.x, out.y = (L.x or 0.5) * (env.dw or 0), (L.y or 0.5) * (env.dh or 0);
        out.px, out.py = L.px or 0, L.py or 0;
        return true;
    end
    if (a.x == nil) then
        return false;
    end
    if (from == 'window') then
        local c = CORNERS[L.at or 'tr'] or CORNERS.tr;
        out.x, out.y = a.x + c[1] * (a.w or 0) + (L.dx or 0), a.y + c[2] * (a.h or 0) + (L.dy or 0);
    else
        out.x, out.y = (a.x + (L.dx or 0)) * scale, (a.y + (L.dy or 0)) * scale;
        if (out.has_size and L.align == 'right') then
            out.x = (a.x + (L.dx or 0) + (a.w or 0)) * scale - out.w;
            if (out.w <= 0) then
                out.px = 1; -- as wide as its content: its right edge goes there
            end
        end
        if (L.valign == 'bottom') then
            out.y, out.py = (a.y + (L.dy or 0) + (a.h or 0)) * scale, 1;
        end
    end
    if (L.clamp and env.dw ~= nil and env.dw > 0) then
        local w = out.has_size and out.w or (out.min_w or 0);
        local h = out.has_size and out.h or (out.min_h or 0);
        out.x = math.max(4, math.min(out.x, env.dw - w - 4));
        out.y = math.max(4, math.min(out.y, env.dh - math.max(h, 40) - 4));
    end
    return true;
end

--[[
* The other way: the layout changes that put a window of layout L at screen position x, y (where the
* player dragged it), keeping its kind of anchor. a and own are what resolve was given; ww the
* window's width (for a right-aligned one as wide as its content).
* Returns a table of the fields to store (dx/dy, or x/y for 'screen').
--]]
function place.offset(L, a, env, x, y, own, ww, wh)
    local from = L.from or 'menu';
    if (from == 'screen') then
        local dw, dh = env.dw or 0, env.dh or 0;
        return { x = dw > 0 and x / dw or 0.5, y = dh > 0 and y / dh or 0.5, px = 0, py = 0 };
    end
    a = a or NONE;
    if (a.x == nil) then
        return nil;
    end
    if (from == 'window') then
        local c = CORNERS[L.at or 'tr'] or CORNERS.tr;
        return { dx = x - (a.x + c[1] * (a.w or 0)), dy = y - (a.y + c[2] * (a.h or 0)) };
    end
    local scale = env.scale > 0 and env.scale or 1;
    if (L.align == 'right' and L.min == nil) then
        local w = size(L.w, (own or a).w, env.scale, env.fs);
        if (w <= 0) then
            w = ww or 0;
        end
        return { dx = (x + w) / scale - a.x - (a.w or 0), dy = y / scale - a.y };
    end
    if (L.valign == 'bottom') then
        return { dx = x / scale - a.x, dy = (y + (wh or 0)) / scale - a.y - (a.h or 0) };
    end
    return { dx = x / scale - a.x, dy = y / scale - a.y };
end

return place;
