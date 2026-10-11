--[[
* facelift - panes/menuopts: an option menu (adapters/menuopts) where the game's was, each option a
* button in the theme at the option's own place (so lists, grids and odd layouts all come out as the
* game lays them out), with the game's own picture on it (ui/gametex: the label's glyphs in the
* theme's text colour, accent under the game's cursor, faint when greyed, over their dark shadow;
* anything else in the picture as it is). Title tabs and the like are drawn, not clickable. The mouse
* only lights a button; a click is the game's mouse on that option. The window has no background of
* its own: the theme's box goes around the options, and the ones outside the game's frame (the main
* menu's page arrows) float beside it, their picture alone (lit under the mouse).
--]]

local imgui    = require('ui.gui');
local theme    = require('ui.theme');
local gamepic  = require('ui.gamepic');
local gametext = require('core.gametext');
local safemem  = require('core.safemem');

local P = {};

local BG    = theme.derive('LIGHT', 0.05);
local HOVER = theme.derive('LIGHT', 0.10);
local HERE  = theme.derive('ACCENT', 0.24);

function P.new(spec)
    return { titles = {} }; -- [char*] = its text (UTF-8)
end

local a, b, uv0, uv1 = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };
local pos, size = { 0, 0 }, { 0, 0 };
local cols = {};

-- An ImGui colour, kept per theme version.
local function u32(c)
    local k = cols[c];
    if (k == nil or k[2] ~= theme.version) then
        k = { imgui.GetColorU32(c), theme.version };
        cols[c] = k;
    end
    return k[1];
end

local picture = gamepic.draw; -- (the game's picture: ui/gamepic)

-- The game's title text for an option (when its picture can't be drawn), kept per pointer.
local function title(st, ptr)
    if (ptr == 0) then
        return nil;
    end
    local t = st.titles[ptr];
    if (t == nil) then
        local s = safemem.read(ptr, 48);
        local z = s ~= nil and s:find('\0', 1, true) or nil;
        t = (z ~= nil and z > 1) and gametext.text(s:sub(1, z - 1)) or false;
        st.titles[ptr] = t;
    end
    return t or nil;
end

function P.draw(st, w, env)
    local p = w.parts[1];
    local m = p.model;
    local k = env.scale;
    local dl = imgui.GetWindowDrawList();
    if (m.bw > 0) then
        theme.box(m.bx * k, m.by * k, (m.bx + m.bw) * k, (m.by + m.bh) * k);
    end
    for i = 1, m.n do
        local o = m.opts[i];
        local x, y = o.x * k, o.y * k;
        local grey = o.state == 5 or o.state == 0x10 or (m.cool ~= nil and m.cool[o.n]);
        local here = not o.deco and o.n == m.cursor;
        local tint = u32(grey and theme.FAINT or (here and theme.ACCENT or theme.TEXT));
        if (not o.deco and not p.focused) then
            -- A menu under the focused one: as the game shows it, not clickable.
            if (not o.out) then
                a[1], a[2], b[1], b[2] = x, y, x + o.w * k, y + o.h * k;
                dl:AddRectFilled(a, b, u32(here and HERE or BG), theme.r(3 * k));
            end
        elseif (not o.deco) then
            pos[1], pos[2], size[1], size[2] = x, y, o.w * k, o.h * k;
            imgui.SetCursorScreenPos(pos);
            imgui.PushID(i);
            local hit = imgui.InvisibleButton('##opt', size);
            local hov = imgui.IsItemHovered();
            imgui.PopID();
            if (not o.out or hov) then
                a[1], a[2], b[1], b[2] = x, y, x + o.w * k, y + o.h * k;
                dl:AddRectFilled(a, b, u32(here and HERE or (hov and not grey and HOVER or BG)), theme.r(3 * k));
            end
            if (hit and not grey) then
                w.req(p.name, 'select', o.n);
            end
        end
        if (not picture(dl, o.label, x, y, k * o.sx, tint)) then
            local t = title(st, o.title) or (not o.deco and ('%d'):format(o.n) or nil);
            if (t ~= nil) then
                a[1], a[2] = x + 6 * k, y + (o.h * k - imgui.GetFontSize()) / 2;
                dl:AddText(a, tint, t);
            end
        end
        local mark = m.marks ~= nil and m.marks[o.n] or nil;
        if (mark ~= nil) then
            picture(dl, mark, x, y, k * o.sx, 0xFFFFFFFF); -- (a party menu's mark or check, where the game puts it)
        end
    end
end

return P;
