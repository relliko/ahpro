--[[
* facelift - panes/ahprices: the prices facelift has kept for an item (db/prices): how many sales,
* over what dates, the median of them all and of the last 10, the last price, and a graph, under how
* long ago its price history was last checked (it may have sold since: amber after a week). The
* item is the one in the window this follows (w.lead): the price history's, or the auction list's
* under the mouse (else the one selected).
--]]

local imgui  = require('ui.gui');
local theme  = require('ui.theme');
local fmt    = require('ui.fmt');
local graph  = require('ui.pricegraph');
local prices = require('db.prices');
local gametext = require('core.gametext');

local P = {};

function P.new(spec)
    return { graph = {}, key = nil, s = nil, ago = nil, ago_at = nil };
end

local DAY = 86400;

-- When its price history was last checked: 'checked 3 days ago', coloured by how old.
local function checked(st, e, fs)
    if (e.checked == nil) then
        return;
    end
    local age = math.max(0, os.time() - e.checked);
    local at = ('%d/%d'):fmt(e.checked, math.floor(age / 30));
    if (st.ago_at ~= at) then
        st.ago_at, st.ago = at, fmt.ago(age);
    end
    local old = age >= 7 * DAY;
    imgui.TextColored(theme.DIM, 'checked');
    imgui.SameLine(0, 4 * fs);
    imgui.TextColored(age < DAY and theme.GOOD or (old and theme.WARN or theme.DIM), st.ago);
    if (old) then
        imgui.SameLine(0, 6 * fs);
        imgui.TextColored(theme.WARN, '(may be out of date)');
    end
end

-- The item the window being followed is on: id, stack; or nil.
local function item_of(lead)
    if (lead.id == 'ahhisto') then
        local m = lead.part.list.model;
        return m.id ~= 0 and m.id or nil, m.stack;
    end
    local r = lead.item;
    if (r ~= nil and r.id ~= nil and r.id ~= 0) then
        return r.id, r.stack == true;
    end
    return nil;
end

-- What's said about the sales (db/prices stats, as text), worked out when they change.
local function stats(e)
    local s = prices.stats(e);
    return {
        n = ('%d'):fmt(s.n), sales = s.n == 1 and 'sale seen' or 'sales seen',
        from = os.date('%y/%m/%d', s.first_date) or '?', to = os.date('%y/%m/%d', s.last_date) or '?',
        med = fmt.commas(s.med), recent = s.recent ~= nil and fmt.commas(s.recent) or nil,
        last = fmt.commas(s.last),
    };
end

-- Nothing to show beside an empty Sales Status or sell picker (there's no item to point at).
function P.visible(st, w)
    local lead = w.lead;
    if (lead ~= nil and (lead.id == 'ahsales' or lead.id == 'ahsellpick')) then
        local p = lead.part ~= nil and lead.part.list or nil;
        return p ~= nil and p.model.list ~= nil and #p.model.list > 0;
    end
    return true;
end

local function body(st, w, env)
    local fs = env.fs;
    local cw = math.max(0, w.place.w - 24 * fs);
    local id, stack = item_of(w.lead);
    if (id == nil) then
        imgui.TextColored(theme.DIM, 'Point at an item to see its prices.');
        return;
    end
    local item = AshitaCore:GetResourceManager():GetItemById(id);
    imgui.TextColored(theme.ACCENT, gametext.name(item, id));
    if (stack) then
        imgui.SameLine();
        imgui.TextColored(theme.DIM, ('x%d'):fmt(item ~= nil and item.StackSize or 1));
    end
    P.prices(st, id, stack, fs, cw);
end

-- Item id's prices (stack: of a stack) as this window shows them under its name, cw wide: when they
-- were checked, the sales' numbers and the graph (also drawn by panes/ahbrowse). st: P.new()'s.
function P.prices(st, id, stack, fs, cw, gh)
    local e = prices.get(id, stack);
    if (e == nil) then
        imgui.PushTextWrapPos(imgui.GetCursorPosX() + cw);
        imgui.TextColored(theme.DIM, 'No sales seen yet. Its price history keeps them when you open it.');
        imgui.PopTextWrapPos();
        return;
    end
    checked(st, e, fs);
    if (#e.sales == 0) then
        imgui.TextColored(theme.DIM, 'No sales on record.');
        return;
    end
    local key = ('%d/%s/%d'):fmt(id, tostring(stack), e.version);
    if (st.key ~= key) then
        st.key, st.s = key, stats(e);
    end
    local s = st.s;
    imgui.TextColored(theme.ACCENT, s.n);
    imgui.SameLine(0, 4 * fs);
    imgui.TextColored(theme.DIM, s.sales);
    imgui.SameLine(0, 10 * fs);
    imgui.TextColored(theme.DIM, s.from == s.to and s.from or (s.from .. ' to ' .. s.to));
    imgui.TextColored(theme.DIM, 'median');
    imgui.SameLine(0, 4 * fs);
    imgui.TextColored(theme.GOOD, s.med);
    if (s.recent ~= nil) then
        imgui.SameLine(0, 10 * fs);
        imgui.TextColored(theme.DIM, 'last 10');
        imgui.SameLine(0, 4 * fs);
        imgui.TextColored(theme.TEXT, s.recent);
    end
    imgui.SameLine(0, 10 * fs);
    imgui.TextColored(theme.DIM, 'last');
    imgui.SameLine(0, 4 * fs);
    imgui.TextColored(theme.TEXT, s.last);
    graph.draw(st.graph, e.sales, key, cw, (gh or 130) * fs, fs);
    -- Clearing what's kept for it (asks once more: a second click within 4 s).
    local sure = st.clear_key == key and os.clock() - (st.clear_at or -10) < 4;
    if (imgui.SmallButton((sure and 'Click again to clear' or 'Clear kept prices') .. '##facelift_prices_clear')) then
        if (sure) then
            prices.forget(id, stack);
            st.clear_key = nil;
        else
            st.clear_key, st.clear_at = key, os.clock();
        end
    end
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip("Forgets the sales kept for this item; its next price history fills them again.");
    end
end

-- Beside the price history (where the price box docks below this), always as tall as with its
-- prices and graph, so the box doesn't move when the history comes in.
function P.draw(st, w, env)
    local y0 = imgui.GetCursorPosY();
    body(st, w, env);
    if (w.lead ~= nil and w.lead.id == 'ahhisto') then
        local lhs = imgui.GetTextLineHeightWithSpacing();
        local sp = lhs - imgui.GetTextLineHeight();
        local target, cur = y0 + 4 * lhs + 130 * env.fs + sp, imgui.GetCursorPosY();
        if (cur < target) then
            imgui.Dummy({ 1, target - cur - sp });
        end
    end
end

return P;
