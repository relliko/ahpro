--[[
* facelift - ui/sales: an item's last sales (the auction house's price history) as rows of date,
* seller, buyer and price under a line of lowest, median and highest price, with the game's cursor
* highlighted. Columns are as wide as their widest text. Plain rows in; the clicked row out.
*
* A sale: { price, date (Unix time), seller, buyer, row (its place in the game's list, from 0) }.
--]]

local imgui = require('ui.gui');
local theme = require('ui.theme');
local fmt   = require('ui.fmt');

local sales = {};

-- A list's own state: what was worked out for the rows it last drew.
function sales.new(id)
    return { id = id, key = nil, cells = {}, summary = nil, cols = { 0, 0, 0, 0 }, sum_w = 0 };
end

local function tw(s)
    return (imgui.CalcTextSize(s));
end

-- The rows' text, the columns' widths and the summary, once per list and text size.
local function cells(st, rows, key, fs)
    if (st.key == key) then
        return;
    end
    st.key = key;
    st.cells = {};
    local cols = st.cols;
    cols[1], cols[2], cols[3], cols[4] = tw('Date'), tw('Seller'), tw('Buyer'), tw('Price');
    local prices = {};
    for i, r in ipairs(rows) do
        local c = {
            date = os.date('%y/%m/%d', r.date) or '?',
            seller = r.seller ~= '' and r.seller or nil,
            buyer = r.buyer ~= '' and r.buyer or nil,
            price = fmt.commas(r.price) .. ' G',
        };
        st.cells[i] = c;
        cols[1] = math.max(cols[1], tw(c.date));
        cols[2] = math.max(cols[2], tw(c.seller or '-'));
        cols[3] = math.max(cols[3], tw(c.buyer or '-'));
        cols[4] = math.max(cols[4], tw(c.price));
        prices[i] = r.price;
    end
    st.summary = nil;
    if (#prices > 0) then
        table.sort(prices);
        local n = #prices;
        local mid = n % 2 == 1 and prices[(n + 1) / 2] or math.floor((prices[n / 2] + prices[n / 2 + 1]) / 2);
        local s = { ('%d'):fmt(n), n == 1 and 'sale' or 'sales', fmt.commas(prices[1]), fmt.commas(mid), fmt.commas(prices[n]) };
        st.summary = s;
        st.sum_w = tw(s[1]) + tw(s[2]) + tw('low') + tw(s[3]) + tw('median') + tw(s[4]) + tw('high') + tw(s[5]) + 54 * fs;
    end
end

--[[
* Draws the sales in the current window. st: sales.new state; rows; index: the game's cursor (a
* row, from 0); key: anything that changes when the rows or the text size do; fs: text size;
* min_w: the narrowest the table may be. Returns the clicked sale or nil, true if it was a double
* click, and the width it took (for what goes under it).
--]]
function sales.draw(st, rows, index, key, fs, min_w)
    cells(st, rows, key, fs);
    if (st.summary == nil) then
        imgui.TextColored(theme.DIM, 'No sales to show.');
        return nil, false, min_w;
    end
    local cols, pad, gap = st.cols, 4 * fs, 16 * fs;
    local x_seller = pad + cols[1] + gap;
    local x_buyer = x_seller + cols[2] + gap;
    local need = x_buyer + cols[3] + gap + cols[4] + pad;
    local cw = math.max(need, min_w, st.sum_w);
    x_buyer = x_buyer + (cw - need) / 2; -- room to spare goes between the names
    local price_end = cw - pad;
    local base = imgui.GetCursorPosX();

    local s = st.summary;
    imgui.TextColored(theme.ACCENT, s[1]);
    imgui.SameLine(0, 4 * fs);
    imgui.TextColored(theme.DIM, s[2]);
    imgui.SameLine(0, 12 * fs);
    imgui.TextColored(theme.DIM, 'low');
    imgui.SameLine(0, 4 * fs);
    imgui.TextColored(theme.TEXT, s[3]);
    imgui.SameLine(0, 10 * fs);
    imgui.TextColored(theme.DIM, 'median');
    imgui.SameLine(0, 4 * fs);
    imgui.TextColored(theme.GOOD, s[4]);
    imgui.SameLine(0, 10 * fs);
    imgui.TextColored(theme.DIM, 'high');
    imgui.SameLine(0, 4 * fs);
    imgui.TextColored(theme.TEXT, s[5]);
    imgui.Separator();

    imgui.SetCursorPosX(base + pad);
    imgui.TextColored(theme.FAINT, 'Date');
    imgui.SameLine(base + x_seller);
    imgui.TextColored(theme.FAINT, 'Seller');
    imgui.SameLine(base + x_buyer);
    imgui.TextColored(theme.FAINT, 'Buyer');
    imgui.SameLine(base + price_end - tw('Price'));
    imgui.TextColored(theme.FAINT, 'Price');

    local line = imgui.GetFontSize() + 4 * fs;
    local size = { cw, line };
    local clicked, double = nil, false;
    for i, r in ipairs(rows) do
        local c = st.cells[i];
        local here = r.row == index;
        imgui.PushID(i);
        if (imgui.Selectable('##sale', here, ImGuiSelectableFlags_AllowDoubleClick, size)) then
            clicked = r;
            double = imgui.IsMouseDoubleClicked(0);
        end
        imgui.PopID();
        local tc = here and theme.ACCENT or theme.TEXT;
        imgui.SameLine(base + pad);
        imgui.TextColored(here and theme.ACCENT or theme.DIM, c.date);
        imgui.SameLine(base + x_seller);
        imgui.TextColored(c.seller and tc or theme.FAINT, c.seller or '-');
        imgui.SameLine(base + x_buyer);
        imgui.TextColored(c.buyer and tc or theme.FAINT, c.buyer or '-');
        imgui.SameLine(base + price_end - tw(c.price));
        imgui.TextColored(theme.GOOD, c.price);
    end
    return clicked, double, cw;
end

return sales;
