--[[
* facelift - ui/list: a scrolling item list with a filter box, item icons, a count on the right, and
* the selected row kept in view. Plain rows in, the clicked and hovered rows out.
*
* A row: { id, name, lname (lowercase name), stack, stack_size, n (count, nil = none shown), pic (a
* game picture for its icon, when it's not an item: a spell's),
* faint (drawn faint: can't be chosen), color (the name's own colour, as the game gives it), tint (the
* icon's colour as the game gives it: a linkshell item's, core/lsitem), sub (a second, quieter line
* under the name: a spell's cost), wait (right is a recast running: amber), locked (a padlock at the
* right: a job trait you're too low for) }.
*
* st.fixed (set by the pane): always page rows tall, even with fewer rows.
* st.rich (set by the pane): roomier rows with bigger icons, each two lines tall (the sub on the second),
* the selected row marked by an accent bar at its left (the spell and ability lists).
--]]

local imgui   = require('ui.gui');
local theme   = require('ui.theme');
local icons   = require('ui.icons');
local gamepic = require('ui.gamepic');

local list = {};

-- A list's own state: the filter text and the row last scrolled to.
function list.new(id)
    return { id = id, filter = { '' }, last_index = -1, key = nil };
end

--[[
* Draws the list body in the current window. st: list.new state; rows; index: the selected row (from
* 0); page: rows shown at once; key: anything that changes when it's a different list (the selected
* row is scrolled to again); fs: text size; ww: the window's width; head: what the top shows instead
* of how many rows there are ('30/30', a bag's count; false: nothing, the filter from the start); button: a small button's label at the end of
* the header line, or nil; geom: { w, sx, X, W } when the rows carry the game's columns (r.cells: the
* row laid out as the game does, sx screen px a game UI px; without sx its columns' width w fills the
* list; X[c] / W[c] the columns' own left and width, screen px from the row's left, when the pane has
* fitted them to their text), else nil. Returns the clicked
* row's index (from 0) or nil, the hovered row or nil, true on Enter in the filter (the pane keeps
* that Enter from the game: the game's list would act on its own cursor), and true when the button
* was pressed.
--]]
local ta = { 0, 0 };
local NATIONS = { [0] = { 0.62, 0.16, 0.16, 0.9 }, [1] = { 0.18, 0.30, 0.66, 0.9 }, [2] = { 0.22, 0.52, 0.22, 0.9 } };

--[[
* A player record's tab stops (screen px from the cell's left), at the text size now: '[' then the
* main job slot ('WAR00'), '/', the sub job slot, ']', the race ('Hum'), then the rank; and the
* width it all takes. Kept per text size.
--]]
local stops_at, stops = nil, nil;
function list.record_stops()
    local fh = imgui.GetFontSize();
    if (stops_at ~= fh) then
        local w = function (t) return imgui.CalcTextSize(t); end;
        local s = {};
        s.main = w('[');
        s.slash = s.main + w('WAR00') + w('M.') * 0 + 1;
        s.sub = s.slash + w('/') + 1;
        s.close = s.sub + w('WAR00') + 1;
        s.race = s.close + w(']') + 2;
        s.rank = s.race + w('Hum') + 4;
        s.width = s.rank + fh * 1.3;
        stops, stops_at = s, fh;
    end
    return stops;
end

-- A rank on its nation's crest, as the game draws it ('menu pname': the crest 27 + nation, the digits
-- 30 + d over its right part); a box in the nation's colour when those can't be drawn. At (x, y), as
-- tall as the text (h).
local function rank(dl, b, x, y, h)
    local crest = gamepic.sprite('sprites.ui', 3, 27 + (b.nation or 0));
    local x0, y0, x1, y1 = gamepic.bounds(crest);
    if (x0 ~= nil and y1 > y0) then
        local k = h * 1.2 / (y1 - y0);
        if (gamepic.draw(dl, crest, x - x0 * k, y - h * 0.1 - y0 * k, k, 0xFFFFFFFF)) then
            -- The digits over the crest's right part (the game: 6 px into the 16 px crest, 6 apart).
            local n = b.n;
            local digits = n >= 10 and { math.floor(n / 10) % 10, n % 10 } or { n };
            local dx = x + (x1 - x0) * k * (n >= 10 and 0.25 or 0.4);
            for _, d in ipairs(digits) do
                local g = gamepic.sprite('sprites.ui', 3, 30 + d);
                local gx0, gy0 = gamepic.bounds(g);
                if (gx0 ~= nil) then
                    gamepic.draw(dl, g, dx - gx0 * k, y + h * 0.28 - gy0 * k, k, 0xFFFFFFFF);
                end
                dx = dx + 6 * k;
            end
            return;
        end
    end
    local nc = NATIONS[b.nation] or theme.DIM;
    dl:AddRectFilled({ x, y + 1 }, { x + h, y + 1 + h }, imgui.GetColorU32(nc), theme.r(2));
    local t = tostring(b.n);
    dl:AddText({ x + (h - imgui.CalcTextSize(t)) / 2, y }, imgui.GetColorU32(theme.TEXT), t);
end

-- A row's cells in the game's columns, from the row's left (cx, cy), sx screen px a UI px; or, with
-- geom_x / geom_w (columns laid out to fit their text: from the list's geom), at those.
local geom_x, geom_w = nil, nil;
local function cells(r, cx, cy, sx, icon, line, selected)
    local dl = imgui.GetWindowDrawList();
    local fh = imgui.GetFontSize();
    local X, W = geom_x, geom_w;
    local edge = cx; -- where the row's last drawn cell ends: the next starts after it (no overlaps)
    if (r.status ~= nil) then
        -- A player row: the game's status icon at the row's left (an icon-shaped picture in its first
        -- two columns: the anonymous '?'...; the wide ones there are the game's blank), else a badge
        -- for its status.
        local drawn = false;
        for _, c in ipairs(r.cells) do
            if (c.kind == 'pic' and c.col ~= nil and c.col <= 1) then
                local x0, y0, x1, y1 = gamepic.bounds(c.pic);
                if (x0 ~= nil and y1 > y0 and x1 - x0 <= 2 * (y1 - y0)) then
                    local k = fh / math.max(y1 - y0, x1 - x0);
                    drawn = gamepic.draw(dl, c.pic, cx + 1 - x0 * k, cy + (line - (y1 - y0) * k) / 2 - y0 * k, k, 0xFFFFFFFF);
                    if (drawn) then
                        break;
                    end
                end
            end
        end
        if (r.status and not drawn) then
            local t = r.status[2];
            local tw = imgui.CalcTextSize(t);
            local bw = math.max(fh, tw + 6);
            local by = cy + (line - fh) / 2;
            dl:AddRectFilled({ cx + 1, by }, { cx + 1 + bw, by + fh }, imgui.GetColorU32(r.status[3]), theme.r(fh / 2));
            dl:AddText({ cx + 1 + (bw - tw) / 2, by - 1 }, imgui.GetColorU32(theme.TEXT), t);
        end
        edge = cx + fh + 4;
    end
    for _, c in ipairs(r.cells) do
        local x = cx + (X ~= nil and X[c.col] or c.x * sx);
        if (c.kind ~= 'right') then
            x = math.max(x, edge);
        end
        local none = c.faint or r.faint;
        local col = c.color ~= nil and (none and { c.color[1], c.color[2], c.color[3], 0.45 } or c.color)
            or (none and theme.FAINT or (selected and c.kind == 'text' and theme.ACCENT or theme.TEXT));
        if (c.kind == 'icon') then
            local tex = c.id ~= 0 and ((r.tint ~= nil and icons.tinted(c.id, r.tint)) or icons.get(c.id)) or nil;
            if (tex ~= nil) then
                dl:AddImage(tex, { x, cy + 1 }, { x + icon, cy + 1 + icon });
                edge = math.max(edge, x + icon + 4);
            end
        elseif (c.kind == 'pic') then
            local x0, y0, x1, y1 = gamepic.bounds(c.pic);
            if ((r.status == nil or (c.col or 0) > 1) and x0 ~= nil and y1 > y0) then
                local k = math.min(icon / (y1 - y0), sx * 1.5);
                if (gamepic.draw(dl, c.pic, x - x0 * k, cy + (line - (y1 - y0) * k) / 2 - y0 * k, k, imgui.GetColorU32(col))) then
                    edge = math.max(edge, x + (x1 - x0) * k + 4);
                end
            end
        elseif (c.parts ~= nil) then
            -- A player record in tab stops, as the game lays it out: '[', the main job slot, '/', the
            -- sub job slot, ']', the race, then the rank on its nation's crest.
            ta[2] = cy + (line - fh) / 2 - 1;
            local p, u = c.parts, imgui.GetColorU32(col);
            local stops = list.record_stops();
            local function put(t, at) ta[1] = x + at; dl:AddText(ta, u, t); end
            put('[' .. p.m, 0);
            put(p.main, stops.main + (p.m ~= '' and imgui.CalcTextSize('M.') or 0));
            put('/', stops.slash);
            put(p.sub, stops.sub);
            put(']', stops.close);
            put(p.race, stops.race);
            if (c.badge ~= nil) then
                rank(dl, c.badge, x + stops.rank, cy + (line - fh) / 2, fh);
            end
            edge = math.max(edge, x + stops.width + 6);
        else
            ta[2] = cy + (line - fh) / 2 - 1;
            local tw = imgui.CalcTextSize(c.text);
            ta[1] = c.kind == 'right' and ((X ~= nil and cx + X[c.col] + W[c.col] - 2 * sx or cx + (c.x + c.w - 2) * sx) - tw) or x;
            dl:AddText(ta, imgui.GetColorU32(col), c.text);
            edge = math.max(edge, ta[1] + tw + 6);
            if (c.badge ~= nil) then
                -- A rank box, in the nation's colour (San d'Oria red, Bastok blue, Windurst green).
                local bx, bs = ta[1] + tw + 4, fh;
                local nc = NATIONS[c.badge.nation] or theme.DIM;
                dl:AddRectFilled({ bx, ta[2] + 1 }, { bx + bs, ta[2] + 1 + bs }, imgui.GetColorU32(nc), theme.r(2));
                local t = tostring(c.badge.n);
                dl:AddText({ bx + (bs - imgui.CalcTextSize(t)) / 2, ta[2] }, imgui.GetColorU32(theme.TEXT), t);
                edge = math.max(edge, bx + bs + 6);
            end
        end
    end
end

function list.draw(st, rows, index, page, key, fs, ww, head, button, geom)
    if (st.key ~= key) then
        st.key, st.last_index = key, -1;
    end
    if (head == false) then
        -- (no count: the filter box from the line's start)
    elseif (head ~= nil and st.rich) then
        imgui.TextColored(theme.ACCENT, head); -- (the list's name, then how many: dim)
        imgui.SameLine(0, 6 * fs);
        imgui.TextColored(theme.DIM, ('%d'):fmt(#rows));
    elseif (head ~= nil) then
        imgui.TextColored(theme.ACCENT, head);
    else
        imgui.TextColored(theme.ACCENT, ('%d'):fmt(#rows));
        imgui.SameLine(0, 4 * fs);
        imgui.TextColored(theme.DIM, 'items');
    end
    if (head ~= false) then
        imgui.SameLine();
    end
    if (st.type_to_filter) then -- (the pane's say: typing now goes to the filter)
        st.seed = list.typed(st.type_skip);
    end
    local enter = list.filter(st, fs, button);
    local pressed = false;
    if (button ~= nil) then
        imgui.SameLine();
        pressed = imgui.SmallButton(button);
    end
    local f = (st.filter[1] or ''):lower();

    -- (rich: every row two text lines tall, whether it has a sub or not, so lists of each kind are the
    -- same size; a row without one is centred)
    local rich = st.rich == true;
    local icon = (rich and 22 or 18) * fs;
    local line = rich and (imgui.GetFontSize() * 1.85 + 8 * fs) or (math.max(imgui.GetFontSize(), icon) + 4 * fs);
    local iy = rich and (line - 2 * fs - icon) / 2 or 1; -- (the icon's top in the row)
    -- (st.fixed: always page rows tall, however many there are: the window doesn't change size)
    local child_h = (st.fixed and page or math.max(math.min(#rows, page), 1)) * line + 6 * fs;
    local clicked, hovered = nil, nil;
    imgui.BeginChild(st.id .. '_rows', { ww - 24 * fs, child_h }, 0);
    local n_x = imgui.GetContentRegionAvail() - 36 * fs;
    for i, r in ipairs(rows) do
        if (f == '' or r.lname:find(f, 1, true)) then
            local idx = i - 1;
            local selected = idx == index;
            local cx, cy = imgui.GetCursorScreenPos();
            local ry = imgui.GetCursorPosY(); -- in the list's content (scrolling included)
            imgui.PushID(i);
            if (imgui.Selectable('##row', selected, 0, { 0, line - 2 * fs })) then
                clicked = idx;
            end
            imgui.PopID();
            if (imgui.IsItemHovered()) then
                hovered = r;
            end
            -- The selected row kept in view as the game's own list does it: scrolled only when it
            -- would leave the view, to the edge it left by (centred when the list is new).
            if (selected and st.last_index ~= index) then
                local top = imgui.GetScrollY();
                if (st.last_index < 0) then
                    imgui.SetScrollHereY(0.5);
                elseif (ry < top) then
                    imgui.SetScrollHereY(0.0);
                elseif (ry + line > top + child_h) then
                    imgui.SetScrollHereY(1.0);
                end
            end
            if (geom ~= nil and r.cells ~= nil) then
                geom_x, geom_w = geom.X, geom.W;
                cells(r, cx, cy, geom.sx or ((n_x + 36 * fs) / geom.w), icon, line - 2 * fs, selected);
            end
            local tex = (geom == nil or r.cells == nil) and r.id ~= 0 and not r.noicon
                and ((r.tint ~= nil and icons.tinted(r.id, r.tint)) or icons.get(r.id)) or nil;
            if (geom ~= nil and r.cells ~= nil) then
                -- (drawn in the game's columns above)
            elseif (tex ~= nil) then
                imgui.GetWindowDrawList():AddImage(tex, { cx + 2 * fs, cy + iy }, { cx + 2 * fs + icon, cy + iy + icon });
            elseif (r.banner ~= nil) then
                -- A header row's picture (a bar: 'Storage Options'), as tall as the row.
                local x0, y0, x1, y1 = gamepic.bounds(r.banner);
                if (x0 ~= nil and y1 > y0) then
                    local k = (line - 4 * fs) / (y1 - y0);
                    gamepic.draw(imgui.GetWindowDrawList(), r.banner, cx + 2 * fs - x0 * k, cy + 1 - y0 * k, k, 0xFFFFFFFF);
                end
            elseif (r.pic ~= nil) then
                -- The game's own picture for it (a spell's or an ability's icon), fitted to the icon's place.
                local x0, y0, x1, y1 = gamepic.bounds(r.pic);
                if (x0 ~= nil and y1 > y0 and x1 > x0) then
                    local k = icon / math.max(y1 - y0, x1 - x0);
                    gamepic.draw(imgui.GetWindowDrawList(), r.pic, cx + 2 * fs - x0 * k, cy + iy - y0 * k, k, r.faint and 0x80FFFFFF or 0xFFFFFFFF);
                end
            end
            if (rich and selected) then
                -- The game's cursor: an accent bar at the row's left.
                imgui.GetWindowDrawList():AddRectFilled({ cx, cy }, { cx + 2 * fs, cy + line - 2 * fs }, imgui.GetColorU32(theme.ACCENT));
            end
            if (geom == nil or r.cells == nil) then
                imgui.SameLine(icon + (rich and 12 or 8) * fs);
                if (rich and r.sub == nil) then
                    imgui.SetCursorPosY(imgui.GetCursorPosY() + (line - 2 * fs - imgui.GetFontSize()) / 2);
                end
                local none = (r.n ~= nil and r.n == 0) or r.faint;
                local c = r.color;
                if (c ~= nil) then
                    c = none and { c[1], c[2], c[3], 0.45 } or c; -- (a new table only for these few rows)
                else
                    c = none and theme.FAINT or (selected and theme.ACCENT or theme.TEXT);
                end
                imgui.TextColored(c, r.name);
                if (r.stack) then
                    imgui.SameLine();
                    imgui.TextColored(none and theme.FAINT or theme.DIM, ('x%d'):fmt(r.stack_size or 1));
                end
                if (r.n ~= nil) then
                    imgui.SameLine(n_x);
                    imgui.TextColored(none and theme.FAINT or theme.GOOD, ('%3d'):fmt(r.n));
                elseif (r.right ~= nil) then
                    -- Text at the right (a price, a level, a recast...), ending at the row's right edge.
                    imgui.SameLine(math.max(icon + 8 * fs, n_x + 36 * fs - imgui.CalcTextSize(r.right) - 4 * fs));
                    imgui.TextColored(r.wait and theme.WARN or (none and theme.FAINT or theme.TEXT), r.right);
                end
                if (r.locked) then
                    -- A padlock at the row's right (a trait you're too low for): a rounded shackle, the body over its foot.
                    local dl = imgui.GetWindowDrawList();
                    local lw, lh = 10 * fs, 12 * fs;
                    local x, y = cx + n_x + 36 * fs - lw - 6 * fs, cy + (line - 2 * fs - lh) / 2;
                    local col = imgui.GetColorU32(theme.DIM);
                    dl:AddRect({ x + 2 * fs, y }, { x + lw - 2 * fs, y + lh * 0.75 }, col, (lw - 4 * fs) / 2, 0, 1.5 * fs);
                    dl:AddRectFilled({ x, y + lh * 0.45 }, { x + lw, y + lh }, col, 1.5 * fs);
                end
                if (rich and r.sub ~= nil) then
                    -- The second line (a cost), smaller and quieter, under the name.
                    local size = imgui.GetFontSize() * 0.85;
                    imgui.GetWindowDrawList():AddText(imgui.GetFont(), size, { cx + icon + 12 * fs, cy + imgui.GetFontSize() + 2 * fs },
                        imgui.GetColorU32(none and theme.FAINT or theme.DIM), r.sub);
                end
            end
        end
    end
    if (#rows == 0) then
        imgui.TextColored(theme.DIM, 'Nothing here.');
    end
    imgui.EndChild();
    st.last_index = index;
    return clicked, hovered, enter, pressed;
end

-- The filter box (to the line's end, less room for a small button labelled button); true on Enter.
-- The index (from 0) of row r among rows, or nil (r nil or not one of them): for a hovered row.
function list.index_of(rows, r)
    if (r == nil) then
        return nil;
    end
    for i, x in ipairs(rows) do
        if (x == r) then
            return i - 1;
        end
    end
    return nil;
end

--[[
* A letter or digit just typed (lower case; nil if none), for typing into a field that isn't active:
* only when no text field has the keys (ImGui's WantTextInput), and not with Ctrl or Alt held (a
* shortcut: the auction house's Ctrl+F). skip: letters left to something else.
--]]
local TYPED = nil;
function list.typed(skip)
    local io = imgui.GetIO();
    if (io.WantTextInput or io.KeyCtrl or io.KeyAlt) then
        return nil;
    end
    if (TYPED == nil) then
        TYPED = {};
        for _, c in ipairs({ 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S',
                             'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' }) do
            local k = rawget(_G, 'ImGuiKey_' .. c);
            if (k ~= nil) then
                TYPED[#TYPED + 1] = { k, c:lower() };
            end
        end
    end
    for _, t in ipairs(TYPED) do
        if ((skip == nil or not skip[t[2]]) and imgui.IsKeyPressed(t[1], false)) then
            return t[2];
        end
    end
    return nil;
end

function list.filter(st, fs, button)
    local room = button ~= nil and imgui.CalcTextSize((button:gsub('##.*$', ''))) + 2 * 8 * fs + 6 * fs or 0;
    -- (st.filter_w: its own width, for a list in a column of a window that sizes itself to what's in
    -- it: to the line's end there would widen that window every frame)
    imgui.PushItemWidth(st.filter_w or (button ~= nil and -room or -1));
    -- (st.seed: a character typed while the field wasn't active (st.type_to_filter): the field takes the
    -- keys from here, starting with it; ImGui may hand the field that same key too: not twice)
    local seed = st.seed;
    st.seed = nil;
    if (seed ~= nil) then
        st.filter[1] = (st.filter[1] or '') .. seed;
        imgui.SetKeyboardFocusHere();
    end
    local before = st.filter[1];
    local enter = imgui.InputTextWithHint('##' .. st.id .. '_filter', 'filter', st.filter, 48, ImGuiInputTextFlags_EnterReturnsTrue);
    if (seed ~= nil and st.filter[1] == before .. seed) then
        st.filter[1] = before;
    end
    imgui.PopItemWidth();
    return enter;
end

return list;
