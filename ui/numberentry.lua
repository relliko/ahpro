--[[
* facelift - ui/numberentry: an amount, kept minimal: one big field to type it in (commas shown,
* '1.8k' and '2m' understood), + and - step buttons sized to the amounts that matter, and buttons
* that do nothing (drawn faint) when they can't be used. The plain helpers (parse, steps, verdict)
* don't touch ImGui.
*
* Changes are asked for through req('set', n); OK is req('confirm', nil) (the box's own number)
* and Cancel req('confirm', -1).
--]]

local imgui = require('ui.gui');
local theme = require('ui.theme');
local fmt   = require('ui.fmt');

local numberentry = {};

local FAINT_BG = theme.derive('LIGHT', 0.04);
local FIELD_BG = theme.derive('LIGHT', 0.06);

-- Whether digits with commas are grouped in thousands: '1,500' and '12,345,678' are; '2,5' isn't.
local function thousands(int)
    local first = true;
    for part in (int .. ','):gmatch('([^,]*),') do
        if (not part:match(first and '^%d%d?%d?$' or '^%d%d%d$')) then
            return false;
        end
        first = false;
    end
    return true;
end

-- A typed amount as a number: spaces ignored, commas only between thousands, a k or m after it
-- multiplies. nil if it isn't one ('2,5m', a decimal comma, isn't); '' is 0.
function numberentry.parse(s)
    s = tostring(s or ''):gsub('%s', ''):lower();
    if (s == '') then
        return 0;
    end
    if (s:find(',', 1, true)) then
        local int = s:match('^([%d,]+)');
        local rest = int ~= nil and s:sub(#int + 1) or s;
        if (int == nil or not thousands(int) or rest:find(',', 1, true)) then
            return nil;
        end
        s = int:gsub(',', '') .. rest;
    end
    local n, suffix = s:match('^(%d*%.?%d+)([km]?)$');
    n = tonumber(n);
    if (n == nil) then
        return nil;
    end
    n = n * (suffix == 'k' and 1000 or (suffix == 'm' and 1000000 or 1));
    return math.floor(n + 0.5);
end

--[[
* The step sizes to offer: cols powers of ten, the biggest the largest power of ten no more than
* the reference amount (the usual price, else the max) and at least 10^(cols-1), and none over the
* max. 7,446 gil and a usual 180 with 4 columns: 1, 10, 100, 1000.
--]]
function numberentry.steps(max, ref, cols)
    cols = cols or 4;
    local top = math.min(math.max(max, 1), math.max(ref or max, 10 ^ (cols - 1)));
    local p = 1;
    while (p * 10 <= top) do
        p = p * 10;
    end
    local out = {};
    for i = cols - 1, 0, -1 do
        local v = p / 10 ^ i;
        if (v >= 1) then
            out[#out + 1] = v;
        end
    end
    return out;
end

--[[
* One line about the amount against the usual price (ref, from n sales seen; name: what ref is
* called, 'median' or 'last 10'): text and colour, or nil when there's nothing to say (no amount,
* fewer than 3 sales). Buying (side nil), 3 times the usual or more asks whether a zero slipped in;
* selling (side 'sell'), a third of it or less asks whether one is missing.
--]]
function numberentry.verdict(value, ref, n, name, side)
    if (side == 'sell' and value > 0 and ref ~= nil and ref > 0 and n ~= nil and n >= 3) then
        local r = value / ref;
        local at = ('%s %s'):format(name or 'median', fmt.commas(ref));
        if (math.abs(r - 1) < 0.005) then
            return 'at ' .. at, theme.GOOD;
        elseif (r > 1) then
            return ('%d%% over %s'):format(math.floor((r - 1) * 100 + 0.5), at), theme.TEXT;
        elseif (r > 2 / 3) then
            return ('%d%% under %s'):format(math.floor((1 - r) * 100 + 0.5), at), theme.TEXT;
        elseif (r > 1 / 3) then
            return ('%d%% under %s'):format(math.floor((1 - r) * 100 + 0.5), at), theme.WARN;
        end
        local zeros = r <= 1 / 70 and 'Two zeros missing? ' or (r <= 1 / 7 and 'A zero missing? ' or '');
        return ('%s%d%% of %s'):format(zeros, math.max(1, math.floor(r * 100 + 0.5)), at), theme.WARN;
    end
    if (value <= 0 or ref == nil or ref <= 0 or n == nil or n < 3) then
        return nil;
    end
    local r = value / ref;
    local at = ('%s %s'):format(name or 'median', fmt.commas(ref));
    if (math.abs(r - 1) < 0.005) then
        return 'at ' .. at, theme.GOOD;
    elseif (r < 1) then
        return ('%d%% under %s'):format(math.floor((1 - r) * 100 + 0.5), at), theme.GOOD;
    elseif (r < 1.5) then
        return ('%d%% over %s'):format(math.floor((r - 1) * 100 + 0.5), at), theme.TEXT;
    elseif (r < 3) then
        return ('%.1fx %s'):format(r, at), theme.WARN;
    end
    local zeros = r >= 70 and 'Two extra zeros? ' or (r >= 7 and 'Extra zero? ' or '');
    return ('%s%sx %s'):format(zeros, fmt.commas(math.floor(r + 0.5)), at), theme.WARN;
end

-- A button that does nothing (drawn faint) when it can't be used. Returns true when clicked.
function numberentry.button(label, size, usable, text)
    if (not usable) then
        imgui.PushStyleColor(ImGuiCol_Text, theme.FAINT);
        imgui.PushStyleColor(ImGuiCol_Button, FAINT_BG);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, FAINT_BG);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, FAINT_BG);
        imgui.Button(label, size);
        imgui.PopStyleColor(4);
        return false;
    end
    if (text ~= nil) then
        imgui.PushStyleColor(ImGuiCol_Text, text);
    end
    local hit = imgui.Button(label, size);
    if (text ~= nil) then
        imgui.PopStyleColor();
    end
    return hit;
end

function numberentry.new(id)
    return { id = id, buf = { '' }, typing = false, over = false, bad = false, value = 0, flag_at = nil };
end

--[[
* The amount: one big field, as wide as its number needs so 'gil' sits by it. Not being typed in, it
* shows the box's number with commas. Typed in, a good number is written to the box every frame
* (and on the frame it's left, so a last keystroke or Escape's undo counts). One that isn't a number
* or is over max isn't written: the box keeps its own, and st.bad / st.over stay set (OK can't be
* used) until the text is fixed or the box's number changes elsewhere. A number over max already in
* the box (another addon may put one there) is flagged the same way. st.value is the amount as of
* this frame. Returns true on Enter in the field with a good number.
--]]
function numberentry.amount(st, m, fs, cw, req)
    imgui.PushFont(imgui.GetFont(), imgui.GetFontSize() * 1.6);
    local unit = st.unit or 'gil'; -- (what the number counts: st.unit, '' none)
    local flagged = st.bad or st.over;
    if (not st.typing and not flagged) then
        st.buf[1] = fmt.commas(m.value);
    end
    local fw = math.max(imgui.CalcTextSize('0,000,000'), imgui.CalcTextSize(st.buf[1])) + 16 * fs;
    imgui.PushItemWidth(math.max(40 * fs, math.min(fw, cw - (unit ~= '' and imgui.CalcTextSize(unit) + 8 * fs or 0))));
    imgui.PushStyleColor(ImGuiCol_Text, flagged and theme.WARN or theme.ACCENT);
    imgui.PushStyleColor(ImGuiCol_FrameBg, FIELD_BG);
    if (st.refocus) then
        st.refocus = false;
        imgui.SetKeyboardFocusHere();
    end
    local enter = imgui.InputText('##' .. st.id .. '_amount' .. (st.gen or ''), st.buf, 32,
        bit.bor(ImGuiInputTextFlags_AutoSelectAll, ImGuiInputTextFlags_EnterReturnsTrue));
    st.typing = imgui.IsItemActive();
    local left = imgui.IsItemDeactivated();
    imgui.PopStyleColor(2);
    imgui.PopItemWidth();
    if (unit ~= '') then
        imgui.SameLine(0, 8 * fs);
        imgui.TextColored(theme.DIM, unit);
    end
    imgui.PopFont();
    st.value = m.value;
    -- A letter in st.keys typed into the field ({ f = the most }: F for All) is that pick, not text.
    if (st.keys ~= nil and (st.typing or enter or left)) then
        local hit = nil;
        for c in st.buf[1]:gmatch('%a') do
            hit = st.keys[c:lower()];
            if (hit ~= nil) then
                break;
            end
        end
        if (hit ~= nil) then
            if (hit ~= m.value) then
                req('set', hit);
            end
            st.buf[1], st.value, st.bad, st.over = fmt.commas(hit), hit, false, false;
            -- (as Tab: the field being typed in would write its own text back when left: a new one)
            st.gen, st.typing, st.refocus = (st.gen or 0) + 1, false, true;
            return false, enter;
        end
    end
    if (st.typing or enter or left) then
        local n = numberentry.parse(st.buf[1]);
        if (n == nil or n > m.max) then
            st.bad, st.over, st.flag_at = n == nil, n ~= nil, m.value;
        else
            st.bad, st.over, st.value = false, false, n;
            if (n ~= m.value) then
                req('set', n);
            end
        end
    elseif (flagged and m.value ~= st.flag_at) then
        st.bad, st.over = false, false; -- the box's number changed elsewhere (arrows, a step)
    end
    if (not st.typing and not st.bad and not st.over and (m.value < 0 or m.value > m.max)) then
        st.bad, st.over, st.flag_at = m.value < 0, m.value > m.max, m.value;
    end
    if (enter and (st.bad or st.over)) then
        st.refocus = true; -- still typing: fix it there
    end
    return enter and not st.bad and not st.over, enter;
end

--[[
* + and - buttons in two rows, one column a step size (sizes: from numberentry.steps; the column
* of the game's own arrow step in the accent), stepping from value. + can't be used when it would
* pass max, - at 0.
--]]
function numberentry.stepper(m, value, sizes, fs, cw, req)
    local cols = #sizes;
    if (cols == 0) then
        return;
    end
    local gap = 4 * fs;
    local size = { (cw - gap * (cols - 1)) / cols, 0 };
    -- Too narrow for the longest label: fewer columns, the smallest steps left out.
    while (cols > 1 and imgui.CalcTextSize('+100K') + 16 * fs > size[1]) do
        sizes = { unpack(sizes, 2) };
        cols = #sizes;
        size[1] = (cw - gap * (cols - 1)) / cols;
    end
    for row = 1, 2 do
        local plus = row == 1;
        for i, n in ipairs(sizes) do
            if (i > 1) then
                imgui.SameLine(0, gap);
            end
            local label = (n >= 1000000 and ('%dM'):format(n / 1000000)) or (n >= 1000 and ('%dK'):format(n / 1000)) or ('%d'):format(n);
            local usable = (plus and value + n <= m.max) or (not plus and value > 0);
            imgui.PushID(row * 100 + i);
            if (numberentry.button((plus and '+' or '-') .. label, size, usable, n == m.step and theme.ACCENT or nil)) then
                req('set', plus and value + n or math.max(0, value - n));
            end
            imgui.PopID();
        end
    end
end

-- Up / Down (held: repeating) while the field is being typed in: the amount a step up / down, within
-- lo..hi, as the game's own Up and Down do in its box (the field keeps those keys from the game).
function numberentry.arrows(st, v, step, lo, hi, req)
    if (not st.typing) then
        return; -- (the game has the keys then, and does the same itself)
    end
    local d = (imgui.IsKeyPressed(ImGuiKey_UpArrow, true) and step or 0) - (imgui.IsKeyPressed(ImGuiKey_DownArrow, true) and step or 0);
    local n = math.max(lo, math.min(hi, v + d));
    if (d == 0 or n == v) then
        return;
    end
    req('set', n);
    st.buf[1] = fmt.commas(n);
    st.bad, st.over = false, false;
    -- (as Tab: the field being typed in would write its own text back when left: a new one, focused)
    st.gen, st.typing, st.refocus = (st.gen or 0) + 1, false, true;
end

-- Tab: the amount to the next of values after its own (the first when it's none of them), Shift+Tab
-- the one before; only those ok(n) allows. Into the field's text too, should it be being typed in.
-- (The pane keeps Tab from the game meanwhile: core/keys.hold_tab.)
function numberentry.tab(st, v, values, ok, req)
    if (not imgui.IsKeyPressed(ImGuiKey_Tab, false)) then
        return;
    end
    local back = imgui.IsKeyDown(ImGuiKey_LeftShift) or imgui.IsKeyDown(ImGuiKey_RightShift);
    local n, at = #values, nil;
    for i, x in ipairs(values) do
        if (x == v) then
            at = i;
        end
    end
    local i = at or (back and n + 1 or 0);
    for _ = 1, n do
        i = back and (i - 2) % n + 1 or i % n + 1;
        local x = values[i];
        if (ok(x)) then
            req('set', x);
            st.buf[1] = fmt.commas(x);
            st.bad, st.over = false, false;
            if (st.typing) then
                -- The field being typed in keeps its own copy of the text and writes it back when
                -- it's left (Tab leaves it), which would undo the pick: a new field, focused, instead.
                st.gen, st.typing, st.refocus = (st.gen or 0) + 1, false, true;
            end
            return;
        end
    end
end

return numberentry;
