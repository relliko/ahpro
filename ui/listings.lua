--[[
* facelift - ui/listings: your auction listings as rows: icon, name (x stack), price, and where it
* stands (on sale, sold, returned, elsewhere/waiting), the game's cursor highlighted. Plain rows in;
* the clicked row (from 0) and the hovered row out.
*
* A row: { id, name, stack, stack_size, price, status ('sale', 'sold', 'returned', 'other') }.
--]]

local imgui = require('ui.gui');
local theme = require('ui.theme');
local icons = require('ui.icons');
local fmt   = require('ui.fmt');

local listings = {};

local STATUS = {
    sale = { 'on sale', theme.GOOD },
    sold = { 'sold', theme.ACCENT },
    returned = { 'returned', theme.WARN },
    other = { 'elsewhere', theme.DIM },
};

function listings.new(id)
    return { id = id, key = nil, prices = {}, names = {}, names_at = nil };
end

-- name cut (with '..') to fit room pixels.
local function fit(name, room)
    if (imgui.CalcTextSize(name) <= room) then
        return name;
    end
    for n = #name - 1, 1, -1 do
        local s = name:sub(1, n) .. '..';
        if (imgui.CalcTextSize(s) <= room) then
            return s;
        end
    end
    return '..';
end

-- st: listings.new state; rows; index: the game's cursor (from 0); key: changes with the rows; fs:
-- text size; cw: the width to fill.
function listings.draw(st, rows, index, key, fs, cw)
    if (st.key ~= key) then
        st.key, st.prices = key, {};
        for i, r in ipairs(rows) do
            st.prices[i] = fmt.commas(r.price) .. ' G';
        end
    end
    if (#rows == 0) then
        imgui.TextColored(theme.DIM, 'You have no items up for auction.');
        return nil, nil;
    end
    local icon = 18 * fs;
    local line = math.max(imgui.GetFontSize(), icon) + 4 * fs;
    local tag_w = imgui.CalcTextSize('elsewhere');
    local base = imgui.GetCursorPosX();
    -- Each name fits the room before its price (worked out when the rows or the width change).
    local at = ('%s/%s/%s'):fmt(tostring(key), cw, fs);
    if (st.names_at ~= at) then
        st.names_at, st.names = at, {};
        for i, r in ipairs(rows) do
            local room = cw - tag_w - 12 * fs - imgui.CalcTextSize(st.prices[i]) - 8 * fs - (icon + 8 * fs);
            if (r.stack) then
                room = room - imgui.CalcTextSize(('x%d'):fmt(r.stack_size or 1)) - 6 * fs;
            end
            st.names[i] = fit(r.name, room);
        end
    end
    local clicked, hovered = nil, nil;
    for i, r in ipairs(rows) do
        local idx = i - 1;
        local here = idx == index;
        local cx, cy = imgui.GetCursorScreenPos();
        imgui.PushID(i);
        if (imgui.Selectable('##listing', here, 0, { cw, line - 2 * fs })) then
            clicked = idx;
        end
        imgui.PopID();
        if (imgui.IsItemHovered()) then
            hovered = r;
        end
        local tex = icons.get(r.id);
        if (tex ~= nil) then
            imgui.GetWindowDrawList():AddImage(tex, { cx + 2 * fs, cy + 1 }, { cx + 2 * fs + icon, cy + 1 + icon });
        end
        imgui.SameLine(base + icon + 8 * fs);
        imgui.TextColored(here and theme.ACCENT or theme.TEXT, st.names[i]);
        if (r.stack) then
            imgui.SameLine();
            imgui.TextColored(theme.DIM, ('x%d'):fmt(r.stack_size or 1));
        end
        local s = STATUS[r.status] or STATUS.other;
        local price = st.prices[i];
        imgui.SameLine(base + cw - tag_w - 12 * fs - imgui.CalcTextSize(price));
        imgui.TextColored(theme.TEXT, price);
        imgui.SameLine(base + cw - tag_w);
        imgui.TextColored(s[2], s[1]);
    end
    return clicked, hovered;
end

return listings;
