--[[
* facelift - ui/tabs: a row of tabs as small buttons (the chat box's channels, the auction house's
* Bid / Sell / Sales Status): each framed in a faint fill, the one you're on filled in the accent,
* one the game's cursor is on (key) outlined in it; a dot at the top right of one with something new.
* Corners as the theme's (theme.r). tabs.draw returns the index clicked, or nil.
--]]

local imgui = require('ui.gui');
local theme = require('ui.theme');

local tabs = {};

local BG    = theme.derive('LIGHT', 0.06);
local HOVER = theme.derive('LIGHT', 0.12);
local HERE  = theme.derive('ACCENT', 0.30);
local DOT   = theme.derive('ACCENT', 0.90);

--[[
* items[1..n] = { label, here (the one you're on), key (the game's cursor on it), new (a dot), faint
* (can't be used just now) }; id: unique among the window's widgets; fs: text size.
--]]
function tabs.draw(id, items, fs)
    local clicked = nil;
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 8 * fs, 2 * fs });
    for i, t in ipairs(items) do
        if (i > 1) then
            imgui.SameLine(0, 3 * fs);
        end
        imgui.PushStyleColor(ImGuiCol_Button, t.here and HERE or BG);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, t.here and HERE or HOVER);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, HERE);
        imgui.PushStyleColor(ImGuiCol_Text, (t.here or t.key) and theme.ACCENT or (t.faint and theme.FAINT or theme.TEXT));
        if (imgui.Button(t.label .. '##' .. id .. i)) then
            clicked = i;
        end
        imgui.PopStyleColor(4);
        local x0, y0 = imgui.GetItemRectMin();
        local x1, y1 = imgui.GetItemRectMax();
        local dl = imgui.GetWindowDrawList();
        if (t.key and not t.here) then
            dl:AddRect({ x0, y0 }, { x1, y1 }, imgui.GetColorU32(theme.ACCENT), theme.r(3 * fs), 0, 1);
        end
        if (t.new) then
            dl:AddCircleFilled({ x1 - 3 * fs, y0 + 3 * fs }, 2 * fs, imgui.GetColorU32(DOT));
        end
    end
    imgui.PopStyleVar(1);
    return clicked;
end

return tabs;
