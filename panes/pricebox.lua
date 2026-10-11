--[[
* facelift - panes/pricebox: the number box (part 'box', adapters/numberbox), kept minimal.
*
* An auction house bid or sale: the item and your gil, the amount, quick picks (lowest of the last
* 10, the usual, the last, and for a sale first 'undercut': a gil under the last sale; Tab steps the amount
* through them, Shift+Tab back, and the game doesn't get Tab meanwhile: core/keys), Bid / Sell and
* Cancel, and under them one line on how the amount compares
* with the prices kept for it (db/prices; a bid 3 times the usual price or more, or a sale for a third
* of it or less, needs a second press). Any other box (trade's gil, the delivery box's, an NPC trade's,
* a bazaar price...) as the quantity box is: the amount, 0 and All gil when the box is limited by your
* gil, OK (by the mouse a second press: such a box's answer can act at once in the game) and Cancel. The note goes last so nothing above it moves when it changes. OK is the game's own Enter with the box's number; the
* game then asks its own yes/no for a bid or a sale. Enter in the amount field does the same, and the
* key is kept from reaching the game while it's still held (core/keys).
*
* The game has one number box object for every box it opens, so a new box is one that wasn't up the
* frame before, or whose callback, item or max changed: its steps, picks and the second press start
* afresh. A new box's amount field takes the keyboard at once (its number selected), so typing a
* number replaces it, as in the quantity box.
--]]

local imgui       = require('ui.gui');
local theme       = require('ui.theme');
local fmt         = require('ui.fmt');
local numberentry = require('ui.numberentry');
local prices      = require('db.prices');
local keys        = require('core.keys');
local gametext    = require('core.gametext');

local P = {};

function P.new(spec)
    return { entry = numberentry.new('facelift'), key = nil, frame = nil, armed = nil, picks = {}, picks_key = nil };
end

local function tw(s)
    return (imgui.CalcTextSize(s));
end

-- The quick picks for stats s: { { names, price } }, prices that are the same in one; for a sale,
-- also a gil under the last sale.
local function picks(st, s, refname, ref, sell)
    local key = ('%s/%s/%s'):fmt(tostring(s), tostring(ref), tostring(sell));
    if (st.picks_key == key) then
        return st.picks;
    end
    st.picks_key, st.picks = key, {};
    local all = { { 'low', s.low }, { refname, ref }, { 'last', s.last } };
    if (sell and s.last ~= nil and s.last > 1) then
        table.insert(all, 1, { 'undercut', s.last - 1 }); -- (first: a sale's usual pick)
    end
    for _, c in ipairs(all) do
        local merged = false;
        for _, q in ipairs(st.picks) do
            if (q[2] == c[2]) then
                q[1], merged = q[1] .. ', ' .. c[1], true;
            end
        end
        if (not merged) then
            st.picks[#st.picks + 1] = { c[1], c[2] };
        end
    end
    for i, q in ipairs(st.picks) do
        q[3] = fmt.commas(q[2]) .. '##pick' .. i;
    end
    return st.picks;
end

-- The header: what it is on the left, your gil on the right; the gil number is never cut (it goes
-- to a line of its own when they don't fit).
local function header(base, cw, fs, title, color, sub, gil)
    imgui.TextColored(color, title);
    local used = tw(title);
    if (sub ~= nil) then
        imgui.SameLine();
        imgui.TextColored(theme.DIM, sub);
        used = used + 8 * fs + tw(sub);
    end
    if (gil == nil) then
        return;
    end
    local text = ('you have %s'):fmt(fmt.commas(gil));
    if (used + 12 * fs + tw(text) > cw) then
        text = fmt.commas(gil);
    end
    if (used + 12 * fs + tw(text) > cw) then
        imgui.SetCursorPosX(base + cw - tw(text));
        imgui.TextColored(theme.DIM, text);
        return;
    end
    imgui.SameLine(0, 0);
    imgui.SetCursorPosX(base + cw - tw(text));
    imgui.TextColored(theme.DIM, text);
end

function P.draw(st, w, env)
    local p = w.part.box;
    local m = p.model;
    local fs = env.fs;
    local req = w.reqs.box;
    local cw = math.max(0, w.place.w - 24 * fs);
    local base = imgui.GetCursorPosX();
    local key = ('%x/%x/%d'):fmt(m.cb, m.ctx, m.max);
    if (st.frame ~= env.frame - 1 or (m.cb ~= 0 and st.key ~= key)) then
        st.key, st.armed, st.picks_key = key, nil, nil;
        st.entry = numberentry.new('facelift');
        st.entry.refocus = true; -- (typing a number starts at once, over the box's: as the quantity box)
    end
    st.frame = env.frame;
    if (m.cb == 0) then
        st.armed = nil;
    end

    local ah = (m.kind == 'ahbid' or m.kind == 'ahsell') and m.item ~= nil; -- an auction house item
    local sell = m.kind == 'ahsell';
    local e = ah and prices.get(m.item.id, m.item.stack) or nil;
    local s = prices.stats(e);
    local ref = s ~= nil and (s.recent or s.med) or nil;
    local refname = s ~= nil and s.recent ~= nil and 'last 10' or 'median';

    if (ah) then
        local item = AshitaCore:GetResourceManager():GetItemById(m.item.id);
        header(base, cw, fs, gametext.name(item, m.item.id), theme.ACCENT,
            m.item.stack and ('x%d'):fmt(item ~= nil and item.StackSize or 1) or nil, m.gil);
    else
        header(base, cw, fs, 'Amount', theme.DIM, nil, m.gil);
    end

    -- F for All gil, in a box limited by your gil (its All gil button, below).
    st.entry.keys = (not ah and m.gil ~= nil and m.max == m.gil and m.cb ~= 0 and p.focused) and { f = m.gil } or nil;
    local enter, any_enter = numberentry.amount(st.entry, m, fs, cw, req);
    if (any_enter) then
        keys.swallow_enter(); -- the Enter that did this (good amount or not) mustn't reach the game too
    end
    local v = st.entry.value; -- the amount as of this frame (typed, or the box's)
    if (st.armed ~= nil and st.armed ~= v) then
        st.armed = nil; -- the amount changed: the second press is asked again
    end

    -- A line or two under the buttons, only when there's something to say.
    local note, color = nil, nil;
    if (st.entry.bad) then
        note, color = 'Not a number', theme.WARN;
    elseif (st.entry.over) then
        note, color = m.gil ~= nil and m.max == m.gil and ('You have %s gil'):fmt(fmt.commas(m.gil)) or ('Most is %s'):fmt(fmt.commas(m.max)), theme.WARN;
    elseif (st.armed ~= nil and ah) then
        note, color = ('Press again to %s %s gil'):fmt(sell and 'sell for' or 'bid', fmt.commas(v)), theme.WARN;
    elseif (ah and s ~= nil) then
        note, color = numberentry.verdict(v, ref, s.n, refname, sell and 'sell' or nil);
    end

    -- Quick picks: set the amount, never bid. The prices on the buttons, their names above.
    if (ah and s ~= nil) then
        local ps = picks(st, s, refname, ref, sell);
        local gap = 4 * fs;
        local bw = (cw - gap * (#ps - 1)) / #ps;
        for i, q in ipairs(ps) do
            local x = base + (i - 1) * (bw + gap) + math.max(0, (bw - tw(q[1])) / 2);
            if (i > 1) then
                imgui.SameLine(x);
            else
                imgui.SetCursorPosX(x);
            end
            imgui.TextColored(theme.FAINT, q[1]);
        end
        local size = { bw, 0 };
        for i, q in ipairs(ps) do
            if (i > 1) then
                imgui.SameLine(0, gap);
            end
            if (numberentry.button(q[3], size, q[2] <= m.max, q[2] == v and theme.ACCENT or nil)) then
                req('set', q[2]);
            end
        end
        -- Tab: the next pick after the amount's (the first when it's none of them), Shift+Tab the one
        -- before; only picks that can be used. Into the field's text too, should it be being typed in.
        if (m.cb ~= 0 and p.focused) then
            keys.hold_tab();
            local values = {};
            for i, q in ipairs(ps) do
                values[i] = q[2];
            end
            numberentry.tab(st.entry, v, values, function (n) return n > 0 and n <= m.max; end, req);
        end
    end

    -- Any other box: 0 and All gil when it's limited by your gil (as the quantity box's 1 and All).
    if (not ah and m.gil ~= nil and m.max == m.gil) then
        local gap = 4 * fs;
        local hw = (cw - gap) / 2;
        if (numberentry.button('0##amt_zero', { hw, 0 }, v ~= 0)) then
            req('set', 0);
        end
        imgui.SameLine(0, gap);
        if (numberentry.button(('All gil (%s)##amt_all'):fmt(fmt.commas(m.gil)), { hw, 0 }, v ~= m.gil)) then
            req('set', m.gil);
        end
        -- Tab between them (Shift+Tab back), as the auction house's picks.
        if (m.cb ~= 0 and p.focused) then
            keys.hold_tab();
            numberentry.tab(st.entry, v, { 0, m.gil }, function () return true; end, req);
        end
    end

    -- Bid / Sell (or OK) and Cancel.
    imgui.Separator();
    local open = m.cb ~= 0 and p.focused; -- (not while the chat's input has focus: for looking only)
    local usable = open and not st.entry.over and not st.entry.bad and (not ah or v > 0);
    local hold = w.opt('hold_at') or 0;
    local gate = ah and s ~= nil and s.n >= 3 and hold > 0 and ref ~= nil
        and ((not sell and v >= hold * ref) or (sell and v > 0 and v * hold <= ref));
    local verb = sell and 'Sell' or 'Bid';
    local label = 'OK';
    if (ah) then
        label = v <= 0 and verb or (sell and ('Sell for %s gil'):fmt(fmt.commas(v)) or ('Bid %s gil'):fmt(fmt.commas(v)));
    end
    local h = imgui.GetFontSize() + 12 * fs;
    local pw = (cw - 6 * fs) * 0.62;
    if (ah and v > 0 and tw(label) + 16 * fs > pw) then
        label = ('%s %s'):fmt(verb, fmt.commas(v));
        if (tw(label) + 16 * fs > pw) then
            label = verb;
        end
    end
    if (st.armed ~= nil and ah) then
        local full = label .. ' anyway';
        label = tw(full) + 16 * fs <= pw and full or (verb .. ' anyway');
    elseif (st.armed ~= nil) then
        label = 'Press again';
    end
    local press = numberentry.button(label .. '##ok', { pw, h }, usable, st.armed ~= nil and theme.WARN or theme.ACCENT);
    if (press or (enter and usable)) then
        -- A second press: an auction house price well off the usual one; any other box's OK by the
        -- mouse (Enter in the field is the game's own Enter).
        if ((gate or (not ah and press)) and st.armed == nil) then
            st.armed = v;
        else
            st.armed = nil;
            req('confirm', nil);
        end
    end
    imgui.SameLine(0, 6 * fs);
    if (numberentry.button('Cancel', { cw - pw - 6 * fs, h }, open)) then
        st.armed = nil;
        req('confirm', -1);
    end
    if (note ~= nil) then
        imgui.PushTextWrapPos(base + cw);
        imgui.TextColored(color, note);
        imgui.PopTextWrapPos();
    end
end

return P;
