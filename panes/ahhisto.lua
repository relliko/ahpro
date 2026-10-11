--[[
* facelift - panes/ahhisto: an item's price history (part 'list', adapters/auchisto) with the item's
* info below it, where the auction list shows it. A click puts the game's cursor on a sale; a double
* click is the game's Enter on it (it writes the sale to your chat log). Each list of sales, once
* it reads the same twice, goes into the prices kept (db/prices) for the prices window, with the
* time it was checked (also when there are none).
--]]

local imgui    = require('ui.gui');
local theme    = require('ui.theme');
local sales    = require('ui.sales');
local iteminfo = require('ui.iteminfo');
local tooltip  = require('ui.tooltip');
local prices   = require('db.prices');

local P = {};

function P.new(spec)
    return { sales = sales.new('facelift_hist'), wide = nil, wide_fs = nil };
end

-- As wide as the table can get (15-letter names, a big price) from the start, so the windows beside
-- it don't move when the sales come in.
local function widest(st, fs)
    if (st.wide_fs ~= fs) then
        local name = imgui.CalcTextSize(('M'):rep(15));
        st.wide_fs = fs;
        st.wide = 4 * fs + imgui.CalcTextSize('00/00/00') + 16 * fs + name + 16 * fs + name + 16 * fs
            + imgui.CalcTextSize('99,999,999 G') + 4 * fs;
    end
    return st.wide;
end

function P.draw(st, w, env)
    local p = w.part.list;
    local m = p.model;
    if (m.steady and not m.busy and m.id ~= 0 and st.kept ~= m.version) then
        st.kept = m.version;
        prices.add(m.id, m.stack, m.list);
        prices.check(m.id, m.stack);
    end
    local fs = env.fs;
    -- The table is at least as wide as the window's own minimum (less its padding); wider if it needs.
    local cw = math.max(0, w.place.w - 24 * fs, widest(st, fs));
    local base = imgui.GetCursorPosX();
    if (m.count == 0 or m.busy) then
        imgui.TextColored(theme.DIM, m.busy and 'Asking the auction house...' or 'No sales on record.');
        imgui.Dummy({ cw, 0 });
    elseif (#m.list == 0) then
        imgui.TextColored(theme.DIM, 'Reading the sales...');
        imgui.Dummy({ cw, 0 });
    else
        local sale, double;
        sale, double, cw = sales.draw(st.sales, m.list, m.index, ('%d/%s'):fmt(m.version, fs), fs, cw);
        if (sale ~= nil) then
            w.req('list', double and 'choose' or 'point', sale.row);
        end
    end
    if (m.id ~= 0) then
        if (tooltip.covered()) then
            tooltip.offer(m.id, m.stack, env.frame); -- the tooltip window shows it
        else
            imgui.Separator();
            iteminfo(m.id, m.stack, fs, base + cw);
        end
    end
end

return P;
