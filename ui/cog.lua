--[[
* facelift - ui/cog: a window's settings cog (the chat box's, the auction house's): a toothed ring in a
* square button, and its popup with the window's options as the config window draws them (ui/options).
*
* cog.button(id, d): the cog at the cursor, d px square; true when clicked (it opens the popup).
* cog.popup(id, title, w, fs, more): the popup while it's open: title, w's options, then more(), if
*   given, for the window's own extras; true while it's open.
--]]

local imgui = require('ui.gui');
local theme = require('ui.theme');

local cog = {
    -- The addon's theme choice for a window's look (look = its area), drawn in its cog: set by the
    -- addon (facelift: the auction house's own theme; ahpro: its theme), or nil.
    theme_picker = nil,
};

local DIM = theme.derive('LIGHT', 0.45);

function cog.button(id, d)
    local hit = imgui.InvisibleButton('##' .. id, { d, d });
    local x0, y0 = imgui.GetItemRectMin();
    local dl = imgui.GetWindowDrawList();
    local col = imgui.GetColorU32(imgui.IsItemHovered() and theme.ACCENT or DIM);
    local cx, cy, r = x0 + d / 2, y0 + d / 2, d * 0.30;
    for i = 0, 7 do
        local a = i * math.pi / 4;
        local c, s = math.cos(a), math.sin(a);
        dl:AddLine({ cx + c * r * 0.8, cy + s * r * 0.8 }, { cx + c * r * 1.35, cy + s * r * 1.35 }, col, d * 0.14);
    end
    dl:AddCircle({ cx, cy }, r, col, 0, d * 0.12);
    dl:AddCircle({ cx, cy }, r * 0.35, col, 0, d * 0.08);
    if (hit) then
        imgui.OpenPopup('##' .. id .. '_cfg');
    end
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('Settings');
    end
    return hit;
end

function cog.popup(id, title, w, fs, more)
    if (not imgui.BeginPopup('##' .. id .. '_cfg')) then
        return false;
    end
    imgui.TextColored(theme.ACCENT, title);
    imgui.Dummy({ 320 * fs, 1 }); -- (its width: the hints wrap at it)
    imgui.PushItemWidth(220 * fs);
    require('ui.options').draw(w);
    imgui.PopItemWidth();
    if (more ~= nil) then
        imgui.Spacing();
        more();
    end
    imgui.EndPopup();
    return true;
end

return cog;
