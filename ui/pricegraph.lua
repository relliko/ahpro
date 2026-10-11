--[[
* facelift - ui/pricegraph: sales as dots over time (price up, date across; dates in the tooltips), joined in order, with a
* line at the median and the price range on the left. Prices far off the median (over 3
* times it, or under a third) sit at the top or bottom edge in a fainter dot, so one odd sale
* doesn't flatten the rest. Hovering a dot names the sale.
*
* graph.layout is the arithmetic, kept apart from ImGui so it can be tested.
--]]

local imgui = require('ui.gui');
local theme = require('ui.theme');
local fmt   = require('ui.fmt');

local graph = {};

local function median(sorted)
    local n = #sorted;
    if (n == 0) then
        return 0;
    end
    return n % 2 == 1 and sorted[(n + 1) / 2] or (sorted[n / 2] + sorted[n / 2 + 1]) / 2;
end

--[[
* Where each sale goes in a plot w by h (0,0 top left), m in from each edge so dots and labels
* aren't cut: sales = { { price, date }, ... } oldest first. Returns { pts = { { x, y, sale, off } },
* lo, hi (the lowest and highest usual prices) and y_lo, y_hi (where they are), flat (all one
* price: dots across the middle), med, y_med, t0, t1 (dates at the left and right) }; off is set
* for a sale outside lo..hi, put at the top or bottom.
--]]
function graph.layout(sales, w, h, m)
    m = m or 0;
    local out = { pts = {}, lo = 0, hi = 0, y_lo = h - m, y_hi = m, flat = false, med = 0, y_med = h / 2, t0 = 0, t1 = 0 };
    local n = #sales;
    if (n == 0) then
        return out;
    end
    local ps = {};
    for i, s in ipairs(sales) do
        ps[i] = s.price;
    end
    table.sort(ps);
    local med = median(ps);
    local lo, hi = ps[1], ps[n];
    if (n >= 3) then
        -- The axis spans the prices within 3 times the median either way; the rest sit at its ends.
        lo, hi = nil, nil;
        for _, p in ipairs(ps) do
            if (p >= med / 3 and p <= med * 3) then
                lo, hi = lo or p, p;
            end
        end
    end
    local t0, t1 = sales[1].date, sales[n].date;
    out.lo, out.hi, out.med, out.t0, out.t1, out.flat = lo, hi, med, t0, t1, hi <= lo;
    local function y(p)
        if (p > hi) then
            return m;
        elseif (p < lo) then
            return h - m;
        elseif (out.flat) then
            return h / 2;
        end
        return h - m - (p - lo) / (hi - lo) * (h - 2 * m);
    end
    out.y_lo, out.y_hi, out.y_med = y(lo), y(hi), y(med);
    for i, s in ipairs(sales) do
        local x = t1 > t0 and m + (s.date - t0) / (t1 - t0) * (w - 2 * m) or w / 2;
        out.pts[i] = { x, y(s.price), s, s.price < lo or s.price > hi };
    end
    return out;
end

local DOT = theme.derive('ACCENT', 1);
local OFF = theme.derive('FAINT', 1);
local JOIN = theme.derive('DIM', 0.45);
local MED = theme.derive('GOOD', 0.5);
local BG = theme.derive('LIGHT', 0.035);

--[[
* Draws the graph at the cursor, w wide and h tall (screen px), with st (any table) to keep its
* layout until key changes. Returns the hovered sale or nil.
--]]
function graph.draw(st, sales, key, w, h, fs)
    if (st.key ~= key or st.w ~= w or st.h ~= h) then
        st.key, st.w, st.h = key, w, h;
        local probe = graph.layout(sales, 1, 1);
        st.lo_s, st.hi_s = fmt.commas(math.floor(probe.lo + 0.5)), fmt.commas(math.floor(probe.hi + 0.5));
        st.left = math.max(imgui.CalcTextSize(st.lo_s), imgui.CalcTextSize(st.hi_s)) + 6 * fs;
        st.foot = 0;
        st.L = graph.layout(sales, w - st.left - 8 * fs, h - st.foot - 8 * fs, math.max(6 * fs, imgui.GetFontSize() / 2 + 1));
    end
    local L, left = st.L, st.left;
    local x0, y0 = imgui.GetCursorScreenPos();
    local px, py = x0 + left, y0 + 4 * fs;           -- the plot's top left
    local pw, ph = w - left - 8 * fs, h - st.foot - 8 * fs;
    local dl = imgui.GetWindowDrawList();
    local c = imgui.GetColorU32;

    dl:AddRectFilled({ px, py }, { px + pw, py + ph }, c(BG), theme.r(3 * fs));
    -- Price labels level with their prices (one when they're all the same).
    local half = imgui.GetFontSize() / 2;
    dl:AddText({ x0, py + L.y_hi - half }, c(theme.DIM), st.hi_s);
    if (not L.flat) then
        dl:AddText({ x0, py + L.y_lo - half }, c(theme.DIM), st.lo_s);
    end
    if (L.med >= L.lo and L.med <= L.hi) then
        dl:AddLine({ px, py + L.y_med }, { px + pw, py + L.y_med }, c(MED), 1);
    end
    local prev = nil;
    for _, p in ipairs(L.pts) do
        if (prev ~= nil) then
            dl:AddLine({ px + prev[1], py + prev[2] }, { px + p[1], py + p[2] }, c(JOIN), 1);
        end
        prev = p;
    end
    local mx, my = imgui.GetMousePos();
    local near, best = nil, (8 * fs) ^ 2;
    for _, p in ipairs(L.pts) do
        dl:AddCircleFilled({ px + p[1], py + p[2] }, 2.5 * fs, c(p[4] and OFF or DOT));
        local d = (mx - px - p[1]) ^ 2 + (my - py - p[2]) ^ 2;
        if (d < best) then
            near, best = p, d;
        end
    end
    imgui.Dummy({ w, h });
    if (near ~= nil and imgui.IsItemHovered()) then
        dl:AddCircle({ px + near[1], py + near[2] }, 5 * fs, c(theme.TEXT), 0, 1.5);
        local s = near[3];
        local who = (s.seller ~= '' or s.buyer ~= '') and ('\n%s to %s'):fmt(s.seller ~= '' and s.seller or '?', s.buyer ~= '' and s.buyer or '?') or '';
        imgui.SetTooltip(('%s  %s G%s'):fmt(os.date('%y/%m/%d %H:%M', s.date) or '?', fmt.commas(s.price), who));
        return s;
    end
    return nil;
end

return graph;
