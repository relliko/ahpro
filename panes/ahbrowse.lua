--[[
* facelift - panes/ahbrowse: the auction house as one window, from its first menu on: tabs at its top
* for the first menu's Bid, Sell and Sales Status (the one you're in lit; the game's cursor while the
* first menu has focus), then three columns of one size:
*   Bid: the categories (the game's category menus as one tree: adapters/ahpath), the item list
*        (part 'list', adapters/auclist), the item under the mouse (else the selected one): as its
*        tooltip shows it, the prices kept for it (panes/ahprices), the item menu's Price history /
*        Bid / Sort (part 'item', the game's auc3: the game's mouse on that option).
*   Sell: what to do, the bag to pick from (part 'sell', adapters/sellpick: the game's Enter on an
*        item it lets you sell), the item and its prices.
*   Sales Status: your listings (part 'sales', adapters/aucsales), the one under the mouse and its
*        prices, its menu's Price history / Remove (part 'listing', the game's auc4).
* A tab or a category is reached the way the keys get there (adapters/ahpath): a click sets the goal,
* and the window asks for a step every frame until it's there (or 4 seconds pass). A menu of
* categories (Weapons...) shows open in the tree only while the game has it open (so the keys moving
* through the menus above don't open and shut rows under them): a click on it goes into it, as Enter
* does, or, open, back out of it.
*
* The item lookup at the top, beside the tabs (on every tab): a name (part of it) lists the items that match from the server's own
* table of what each category lists (data/ahitems, its item_basic aH column; names the game's own). It
* sends nothing, the matches in the left column: a click on one (or Enter: the first) goes to its
* category the way a click on the category does, through Bid from any other tab (the one
* request the game makes for that, as a player's), then puts the game's cursor on the item once the
* list has come (the game's own SetIndex, local). Nothing is asked about the item itself unless you
* open its history.
*
* Sales Status in pages (Phoenix's ah_pagination: core/ahpages): each press shows the server's next
* 6 of your listings, so the window presses it again by itself (the game's own key, as a player
* cycles it; one every CYCLE s, the server takes one each 1.5 s) while Sales Status is up, and keeps
* each page, until it has them all (a page under 6, or the server back at page 1 after an empty
* one): one list of everything you have up. A page that comes back different (something sold or
* taken down meanwhile) starts the list again. The server tells listings apart only by item, single
* or stack, and price (its Remove deletes one such listing), and only on the page it last showed:
* clicking one from another page presses on to that page, checks its slot still holds the same, and
* then opens its menu (Price history / Remove) as the game's Enter does; if it doesn't, the list
* starts again. That's an option (gather, off at first): otherwise the page shown is the game's own
* list with the server's page and a Next page button beside its count, which presses Sales Status
* again (the game's own key, as a player cycles it). Sales Status: one press per 5 seconds without the
* module (the server refuses it again sooner), one per CYCLE s with it.
--]]

local imgui    = require('ui.gui');
local theme    = require('ui.theme');
local list     = require('ui.list');
local iteminfo = require('ui.iteminfo');
local keys     = require('core.keys');
local numberentry = require('ui.numberentry');
local era      = require('core.era');
local AH       = require('data.ahmenus');
local prices   = require('panes.ahprices');
local listings = require('ui.listings');
local uitabs   = require('ui.tabs');
local icons    = require('ui.icons');
local cog      = require('ui.cog');
local tipsize  = require('ui.tipsize');
local menus    = require('core.menus');
local runtime  = require('windows.runtime');
local gametext = require('core.gametext');
local ahpages  = require('core.ahpages');

local P = {};

local LEFT, MID = 185, 330; -- column widths, times the text size (the right one is the item tooltip's: ui/tipsize)
local SEL = theme.derive('ACCENT', 0.20);
local KEY = theme.derive('ACCENT', 0.32); -- (the game's cursor, where the keys are)
local ITEM_LABELS = { 'History', 'Bid' }; -- auc3's options 1-2 (windowps #391, #388); its 3, Sort, is the list's button
local LISTING_LABELS = { 'History', 'Remove' };    -- auc4's options 1-2 (windowps #391, #393)
local TABS = { 'Bid', 'Sell', 'Sales Status' };    -- auc1's options 1-3
local ERA_HIDE = { aucmagic = { [7] = true } };   -- Geomancy (core/era)

local function hidden(name, n)
    return era.on and ERA_HIDE[name] ~= nil and ERA_HIDE[name][n] == true;
end

-- The lookup's index: { name, lname, id, menu, option, where } for every item a category lists, built
-- the first time a name is typed (the game's names, from Ashita's item data).
local index = nil;
local function build_index()
    local where = {};
    for menu, opts in pairs(AH.cats) do
        for n, cat in pairs(opts) do
            local path = (AH.titles[menu] ~= 'Auction' and (AH.titles[menu] .. ' > ') or '') .. AH.labels[menu][n];
            where[cat] = { menu, n, path };
        end
    end
    index = {};
    local ok, res = pcall(function () return AshitaCore:GetResourceManager(); end);
    if (not ok or res == nil) then
        return;
    end
    for cat, ids in pairs(require('data.ahitems')) do
        local at = where[cat];
        if (at ~= nil) then
            for _, id in ipairs(ids) do
                local item = res:GetItemById(id);
                local name = item ~= nil and gametext.name(item, id) or '';
                if (name ~= '' and name ~= '.') then
                    index[#index + 1] = { name = name, lname = name:lower(), id = id, menu = at[1], option = at[2], where = at[3] };
                end
            end
        end
    end
    table.sort(index, function (a, b) return a.lname < b.lname; end);
end

local MAX_FOUND = 60;

-- The items whose name has q (lower case) in it: those starting with it first; at most MAX_FOUND.
local function lookup(st, q)
    if (st.found_q == q) then
        return st.found;
    end
    if (index == nil) then
        build_index();
    end
    local first, rest = {}, {};
    for _, e in ipairs(index) do
        if (not hidden(e.menu, e.option)) then
            local at = e.lname:find(q, 1, true);
            if (at == 1) then
                first[#first + 1] = e;
            elseif (at ~= nil) then
                rest[#rest + 1] = e;
            end
        end
        if (#first >= MAX_FOUND) then
            break;
        end
    end
    for _, e in ipairs(rest) do
        if (#first >= MAX_FOUND) then
            break;
        end
        first[#first + 1] = e;
    end
    st.found, st.found_q = first, q;
    return first;
end

function P.new(spec)
    local st = { list = list.new('facelift_ahb'), sell = list.new('facelift_ahb_sell'), sales = listings.new('facelift_ahb_sales'),
                 goal = nil, find = { '' }, finding = nil, sp = nil, prices = prices.new(), hover = nil, sales_at = -10 };
    st.list.fixed, st.sell.fixed = true, true; -- (always their rows tall: the window keeps one size)
    return st;
end

-- Frames left to bring the game's cursor in the tree into view after the keys moved it (a few: a menu
-- opening at the tree's end adds its rows this frame, past where ImGui will scroll until the next).
local key_scroll = 0;

-- One line of the tree: a category (leaf) or a menu of them; returns whether it was clicked. here:
-- the list's category (or the one being gone to); key: the game's cursor is on it (its menu has focus).
local CLEAR = { 0, 0, 0, 0 };
local function line(text, depth, here, key, fs, dim, icon, uid)
    local x = imgui.GetCursorPosX();
    imgui.SetCursorPosX(x + depth * 12 * fs);
    local lit = here or key;
    if (lit) then
        imgui.PushStyleColor(ImGuiCol_Header, key and KEY or SEL);
    end
    -- The row: its icon (an item the game lists there), then its name; the selectable's own text is
    -- clear, the name drawn after the icon.
    local is, fh = 16 * fs, imgui.GetFontSize();
    local h = math.max(fh, is);
    imgui.PushStyleColor(ImGuiCol_Text, CLEAR);
    local clicked = imgui.Selectable(text .. '##' .. tostring(depth) .. text .. (uid or ''), lit, 0, { (LEFT - depth * 12) * fs, h });
    imgui.PopStyleColor(lit and 2 or 1);
    local x0, y0 = imgui.GetItemRectMin();
    local dl = imgui.GetWindowDrawList();
    local tex = icon ~= nil and icons.get(icon) or nil;
    local tx = x0 + 2 * fs;
    if (tex ~= nil) then
        dl:AddImage(tex, { tx, y0 + (h - is) / 2 }, { tx + is, y0 + (h + is) / 2 });
    end
    tx = tx + is + 5 * fs;
    dl:AddText({ tx, y0 + (h - fh) / 2 }, imgui.GetColorU32(lit and theme.ACCENT or (dim and theme.DIM or theme.TEXT)), text);
    -- (the game's cursor moved here by the keys and not all in the tree's view: scrolled to it)
    if (key and key_scroll > 0) then
        local _, y0 = imgui.GetItemRectMin();
        local _, y1 = imgui.GetItemRectMax();
        local _, wy = imgui.GetWindowPos();
        local _, wh = imgui.GetWindowSize();
        if (not imgui.IsItemVisible() or y0 < wy or y1 > wy + wh) then
            imgui.SetScrollHereY(0.5);
        else
            key_scroll = 0;
        end
    end
    return clicked;
end

-- The tree under menu name at depth; on: the open menus (by name: always shown open, as the game has
-- them), here_*: the list's category, key_*: the game's cursor (the focused category menu's).
local function tree(st, name, depth, on, fs, here_menu, here_n, key_menu, key_n)
    for n, label in ipairs(AH.labels[name] or {}) do
        if (not hidden(name, n)) then
            local sub = AH.opens[name] ~= nil and AH.opens[name][n] or nil;
            local key = key_menu == name and key_n == n;
            if (sub ~= nil) then
                -- (open only while the game has it open: a click goes in, as Enter, or back out of it)
                local open = on[sub] == true;
                if (line((open and 'v ' or '> ') .. label, depth, false, key, fs, true, not st.no_icons and AH.icons[name][n] or nil)) then
                    st.goal = { name, open and 0 or n, at = os.clock(), done = false };
                end
                if (open) then
                    tree(st, sub, depth + 1, on, fs, here_menu, here_n, key_menu, key_n);
                end
            else
                local here = here_menu == name and here_n == n;
                local going = st.goal ~= nil and st.goal[1] == name and st.goal[2] == n;
                if (line(label, depth, here or going, key, fs, false, not st.no_icons and AH.icons[name][n] or nil) and not here) then
                    st.goal = { name, n, at = os.clock(), done = false };
                end
            end
        end
    end
end

-- A line across the column, cw wide (a Separator would run to the window's edge and widen it).
local function rule(cw, fs)
    local x, y = imgui.GetCursorScreenPos();
    imgui.GetWindowDrawList():AddLine({ x, y + 3 * fs }, { x + cw, y + 3 * fs }, imgui.GetColorU32(theme.FAINT), 1);
    imgui.Dummy({ cw, 6 * fs });
end

local CYCLE = 2.0; -- seconds between Sales Status presses while the pages are gathered

local function new_pages()
    return { pages = {}, last = nil, serial = -1, cur = nil, shown = nil, got = false, at = 0,
             want = nil, hold = 0, note = nil, version = 0 };
end

local function same(a, b)
    return a.id == b.id and a.stack == b.stack and a.price == b.price;
end

--[[
* The pages gathered so far as one list (rows with .page and .slot), or nil without the module. Takes
* the page just shown once all its rows have come; asks for the next while it isn't complete (or a
* listing on another page was clicked); goes to a clicked listing's page and opens it there.
--]]
local function sales_pages(st, w, sp, mode, now)
    if (not ahpages.active or w.opt('gather') ~= 1) then
        return nil;
    end
    st.sp = st.sp or new_pages();
    local S = st.sp;
    local sm = sp.model;
    if (S.serial ~= ahpages.serial) then
        S.serial, S.cur, S.shown, S.got, S.at = ahpages.serial, ahpages.page, ahpages.shown, false, now;
        if (ahpages.wrapped) then
            local hi = 0; -- (past the last page: it was the highest kept before the empty one)
            for pg in pairs(S.pages) do
                hi = math.max(hi, pg);
            end
            S.last = hi;
        end
    end
    -- The page shown: kept once its rows are all in (none still waiting on the server).
    if (not S.got and S.cur ~= nil and sp.live) then
        local ready = #sm.list == S.shown or now - S.at > 2;
        for _, r in ipairs(sm.list) do
            ready = ready and r.status ~= 'other';
        end
        if (ready or now - S.at > 3) then
            local rows = {};
            for i, r in ipairs(sm.list) do
                rows[i] = { id = r.id, name = r.name, lname = r.lname, stack = r.stack, stack_size = r.stack_size,
                            price = r.price, status = r.status, slot = r.slot, page = S.cur };
            end
            local old = S.pages[S.cur];
            local changed = old ~= nil and #old ~= #rows;
            for i = 1, old ~= nil and #rows or 0 do
                changed = changed or not same(old[i], rows[i]);
            end
            if (changed) then
                S.pages, S.last = {}, nil; -- (something sold or was taken down: the pages after it moved)
                S.note = 'Your listings changed: gathering them again.';
            end
            S.pages[S.cur] = rows;
            S.got = true;
            S.version = S.version + 1;
            if (#rows < 6) then
                S.last = #rows == 0 and S.cur - 1 or S.cur;
            end
        end
    end
    local done = S.last ~= nil;
    for pg = 1, S.last or 0 do
        done = done and S.pages[pg] ~= nil;
    end
    -- A listing clicked on another page: there now? its slot still the same: open it.
    local Wt = S.want;
    if (Wt ~= nil and S.got and S.cur == Wt.page and sp.live) then
        local at = nil;
        for i, r in ipairs(sm.list) do
            if (r.slot == Wt.slot) then
                at = (same(r, Wt) and r.status == 'sale') and i or false;
            end
        end
        if (at) then
            w.req('sales', 'choose', at - 1);
        else
            S.pages, S.last = {}, nil;
            S.note = 'That listing has moved: gathering them again.';
        end
        S.want = nil;
    end
    -- The next page: while not complete, or on the way to a clicked listing.
    if ((not done or S.want ~= nil) and S.got and st.goal == nil and mode == 'sales' and now - st.sales_at >= CYCLE) then
        st.goal = { 'auc1', 3, again = true, at = now, done = false };
        st.sales_at, S.hold = now, now + 4;
    end
    if (done and S.want == nil) then
        S.note = nil;
    end
    S.done = done;
    local all = {};
    local hi = S.last;
    if (hi == nil) then
        hi = 0;
        for pg in pairs(S.pages) do
            hi = math.max(hi, pg);
        end
    end
    for pg = 1, hi do
        for _, r in ipairs(S.pages[pg] or {}) do
            all[#all + 1] = r;
        end
    end
    return all;
end

function P.visible(st, w)
    local p = w.part;
    return p.cats.live or p.list.live or p.top.live or p.sell.live or p.sales.live;
end

-- A row of buttons for a small game menu's options (part: the item menu or a listing's), side by
-- side: a click is the game's mouse on that option; Left / Right move the game's cursor along them
-- (its own menu is a column, Up / Down, which still work); the game's cursor lit.
local function buttons(w, part, name, labels, cw, fs, main)
    local bw = (cw - 4 * fs * (#labels - 1)) / #labels;
    -- (an option past the buttons, as auc3's Sort: the game's Up / Down landing on it go on round)
    if (part.focused and part.live) then
        local c = part.model.cursor or 0;
        if (c > #labels) then
            w.req(name, 'point', (part.prev_key == 1) and #labels or 1);
        elseif (c >= 1) then
            part.prev_key = c;
        end
    end
    if (part.focused and part.live) then
        local d = (imgui.IsKeyPressed(ImGuiKey_RightArrow, true) and 1 or 0) - (imgui.IsKeyPressed(ImGuiKey_LeftArrow, true) and 1 or 0);
        local c = part.model.cursor or 0;
        if (d ~= 0 and c >= 1 and c <= #labels) then
            w.req(name, 'point', (c - 1 + d) % #labels + 1);
        end
    end
    for n, label in ipairs(labels) do
        if (n > 1) then
            imgui.SameLine(0, 4 * fs);
        end
        local usable = false;
        if (part.live) then
            for i = 1, part.model.n do
                local o = part.model.opts[i];
                if (o.n == n and o.state ~= 5 and o.state ~= 0x10) then
                    usable = true;
                end
            end
        end
        local key = part.focused and part.model.cursor == n; -- (the game's cursor: where Enter goes)
        if (key) then
            imgui.PushStyleColor(ImGuiCol_Button, KEY);
        end
        local pressed = numberentry.button(label .. '##ahb_' .. name .. n, { bw, 0 }, usable, (key or n == main) and theme.ACCENT or nil);
        if (key) then
            imgui.PopStyleColor(1);
        end
        if (pressed) then
            w.req(name, 'select', n);
        end
    end
end

-- The tabs: auc1's Bid, Sell, Sales Status; mode the one you're in ('bid', 'sell', 'sales').
local MODES = { 'bid', 'sell', 'sales' };
local function tabs(st, w, fs, mode)
    local top = w.part.top;
    local key = top.focused and top.model.cursor or nil; -- (the first menu has focus: its cursor)
    -- The tabs side by side: Left / Right move the first menu's cursor along them (its own menu is a
    -- column, Up / Down, which still work).
    if (key ~= nil and top.live) then
        local d = (imgui.IsKeyPressed(ImGuiKey_RightArrow, true) and 1 or 0) - (imgui.IsKeyPressed(ImGuiKey_LeftArrow, true) and 1 or 0);
        if (d ~= 0 and key >= 1 and key <= #TABS) then
            w.req('top', 'point', (key - 1 + d) % #TABS + 1);
        end
    end
    local items = st.tab_items or {};
    st.tab_items = items;
    for n, label in ipairs(TABS) do
        local it = items[n] or {};
        items[n] = it;
        it.label, it.here, it.key = label, MODES[n] == mode and not top.focused, key == n;
        it.faint = n == 3 and os.clock() - st.sales_at < (ahpages.active and CYCLE or 5);
    end
    local c = uitabs.draw('ahb_tab', items, fs);
    if (c ~= nil and not items[c].here and not items[c].faint) then
        st.goal = { 'auc1', c, at = os.clock(), done = false };
        if (c == 3) then
            st.sales_at, st.sp = os.clock(), nil; -- (pressed by you: the pages gathered afresh)
        end
    end
end

-- The item and its prices at the right (cw wide), or a hint.
local function item_panel(st, show, fs, cw)
    if (show == nil or show.id == nil or show.id == 0) then
        imgui.TextColored(theme.DIM, 'Point at an item.');
        return false;
    end
    iteminfo(show.id, show.stack, fs, imgui.GetCursorPosX() + cw);
    rule(cw, fs);
    prices.prices(st.prices, show.id, show.stack == true, fs, cw, 70);
    rule(cw, fs);
    return true;
end

function P.draw(st, w, env)
    local fs = env.fs;
    local part = w.part;
    local cats, lp, item = part.cats, part.list, part.item;
    local cm, lm = cats.model, lp.model;
    local now = os.clock();
    local mode = (part.sell.live and 'sell') or (part.sales.live and 'sales')
        or (st.sp ~= nil and now < st.sp.hold and 'sales') or (st.next_hold ~= nil and now < st.next_hold and 'sales')
        or 'bid'; -- (between pages: still Sales Status)
    if (part.sales.live and st.sp ~= nil) then
        st.sp.hold = 0;
    end
    if (part.sales.live and st.next_hold ~= nil and now - (st.sales_at or 0) > 0.5) then
        st.next_hold = nil; -- (the next page is up)
    end
    local pages = sales_pages(st, w, part.sales, mode, now);

    -- A tab or category asked for: a step a frame till it's there.
    local g = st.goal;
    if (g ~= nil and (g.done or os.clock() - g.at > 4)) then
        st.goal, g = nil, nil;
    end
    if (g ~= nil and cats.live) then
        w.req('cats', 'go', g);
    end
    -- Sort (the list's button): the game's is the item menu's option 3 (auc3 OnSelect 0x1D9330: its
    -- sort menu, wepsort or armsort, or the list sorted at once): the list's row opened (its Enter),
    -- then that option pressed, as the keys do.
    local so = st.sort;
    if (so ~= nil and now - so.at > 4) then
        st.sort, so = nil, nil;
    end
    if (so ~= nil) then
        if (item.live and item.focused) then
            w.req('item', 'select', 3);
            st.sort = nil;
        elseif (not so.chose and lp.live and lp.focused and lm.index >= 0) then
            w.req('list', 'choose', lm.index);
            so.chose = true;
        end
    end
    -- An item looked up: once its category's list is up with it, the game's cursor on it.
    local f = st.finding;
    if (f ~= nil and os.clock() - f.at > 8) then
        st.finding, f = nil, nil;
    end
    if (f ~= nil and st.goal == nil and lp.live and lp.focused and cm.deep == f.menu and cm.cursor == f.option) then
        for i, r in ipairs(lm.list) do
            if (r.id == f.id) then
                if (lm.index == i - 1) then
                    st.finding = nil;
                else
                    w.req('list', 'point', i - 1);
                end
                break;
            end
        end
    end

    -- The tabs, then three columns of one size: each as tall as the list (its rows always), the
    -- left and right ones scrolling in theirs when longer (nothing in them can resize the window).
    local row_x = imgui.GetCursorPosX();
    local rw = tipsize.content(env.scale, fs); -- (the item column: as wide as the item tooltip everywhere)
    st.no_icons = w.opt('icons') == 0;
    tabs(st, w, fs, mode);
    -- The item lookup, on the tab row (Enter: the first match).
    imgui.SameLine(0, 16 * fs);
    -- (wide: toward the cog at the right, at most 360 the text size)
    local right = row_x + (LEFT + 10 + 10 + MID + 8 + 10 + 10) * fs + rw - imgui.GetFrameHeight() - 16 * fs;
    imgui.PushItemWidth(math.max(160 * fs, math.min(360 * fs, right - imgui.GetCursorPosX())));
    -- (Ctrl+F, while no text field or the game's chat line has the keys: the lookup takes them)
    local typing = runtime.up('chatinput') or menus.find('inline') ~= nil;
    local io = imgui.GetIO();
    if (not typing and not io.WantTextInput and io.KeyCtrl and ImGuiKey_F ~= nil and imgui.IsKeyPressed(ImGuiKey_F, false)) then
        imgui.SetKeyboardFocusHere();
    end
    local find_enter = imgui.InputTextWithHint('##ahb_find', 'Search listings (Ctrl+F)', st.find, 48, ImGuiInputTextFlags_EnterReturnsTrue);
    imgui.PopItemWidth();
    -- The cog at the top right (its settings: rows, icons, Sales Status pages).
    local d = imgui.GetFrameHeight();
    imgui.SameLine(row_x + (LEFT + 10 + 10 + MID + 8 + 10 + 10) * fs + rw - d);
    cog.button('facelift_ahb_cog', d);
    cog.popup('facelift_ahb_cog', 'Auction house', w, fs, cog.theme_picker); -- (its theme: the addon's, ui/cog)
    if (find_enter) then
        keys.swallow_enter(); -- (not the game's Enter too)
    end
    local rows = w.opt('rows');
    local page = (rows ~= nil and rows > 0) and rows or 20;
    local row_h = math.max(imgui.GetFontSize(), 18 * fs) + 4 * fs; -- (ui/list's row)
    local H = imgui.GetFrameHeight() + 5 * fs + page * row_h + 6 * fs;
    local mw = (MID + 24) * fs;

    -- Left: the item lookup and the categories (Bid), or what the tab is for.
    imgui.BeginChild('##ahb_tree', { (LEFT + 10) * fs, H }, 0);
    local q = st.find[1]:lower():gsub('^%s+', ''):gsub('%s+$', '');
    if (#q >= 2) then
        -- The items that match, each with where it's listed; a click (Enter: the first) goes there.
        local found = lookup(st, q);
        if (#found == 0) then
            imgui.TextColored(theme.DIM, 'No item by that name.');
        end
        for i, e in ipairs(found) do
            local going = st.finding ~= nil and st.finding.id == e.id;
            -- (as the tree's rows: the item's own icon, then its name)
            if (line(e.name, 0, going, false, fs, false, e.id, '_found' .. i) or (find_enter and i == 1)) then
                st.goal = { e.menu, e.option, at = os.clock(), done = false };
                st.finding = { id = e.id, menu = e.menu, option = e.option, at = os.clock() };
                st.find[1] = '';
            end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip(e.where);
            end
        end
    elseif (mode == 'bid') then
        local on = {};
        for i = 1, cats.live and cm.n or 0 do
            on[cm.chain[i].name] = true;
        end
        local here_menu = cats.live and lp.live and cm.deep or nil;
        -- The keys: a category menu with focus shows its cursor (moved on past one hidden for the era,
        -- the way it came, as the option menus do).
        local key_menu = cats.focused and cm.deep ~= 'auc1' and cm.deep or nil;
        if (key_menu ~= nil and hidden(key_menu, cm.cursor)) then
            local count = #(AH.labels[key_menu] or {});
            -- (up when it came from the option below, or wrapped round from the top)
            local d = st.key_prev ~= nil and cm.cursor - st.key_prev or 1;
            local up = d == -1 or d > 1;
            local t = cm.cursor;
            repeat
                t = up and (t - 2) % count + 1 or t % count + 1;
            until (not hidden(key_menu, t) or t == cm.cursor);
            w.req('cats', 'cursor', t);
        end
        st.key_prev = key_menu ~= nil and cm.cursor or nil;
        local kid = key_menu ~= nil and (key_menu .. ':' .. cm.cursor) or nil;
        key_scroll = (kid ~= nil and kid ~= st.key_id) and 6 or math.max(0, key_scroll - 1);
        st.key_id = kid;
        tree(st, 'auc2', 0, on, fs, here_menu, cats.live and cm.cursor or nil, key_menu, cm.cursor);
    else
        imgui.PushTextWrapPos(imgui.GetCursorPosX() + LEFT * fs);
        imgui.TextColored(theme.DIM, mode == 'sell' and 'Pick an item from your bag to put up for auction.'
            or 'Your items up for auction. Pick one on sale for its price history, or to take it down.');
        imgui.PopTextWrapPos();
    end
    imgui.EndChild();

    -- Middle: the list for the tab.
    imgui.SameLine(0, 10 * fs);
    imgui.BeginChild('##ahb_mid', { mw - 24 * fs + 8 * fs, H }, 0);
    local show = nil;
    if (mode == 'sell') then
        local sp = part.sell;
        local sm = sp.model;
        st.sell.filter_w = (MID - 90) * fs;
        local clicked, hovered, enter = list.draw(st.sell, sm.list, sm.index, page, sp.handler * 65536 + sm.count, fs, mw);
        if (enter) then
            keys.swallow_enter();
        end
        if (clicked ~= nil) then
            local r = sm.list[clicked + 1];
            w.req('sell', (r ~= nil and not r.faint) and 'choose' or 'point', clicked);
        end
        show = hovered or sm.list[sm.index + 1];
    elseif (mode == 'sales') then
        local sp = part.sales;
        local sm = sp.model;
        local rows, index, key = sm.list, sm.index, sm.version;
        local S = st.sp;
        if (pages ~= nil) then
            -- All the pages as one list: the game's cursor on its row of the page shown.
            local cur = sp.live and sm.list[sm.index + 1] or nil;
            rows, index, key = pages, -1, 'p' .. S.version;
            for i, r in ipairs(pages) do
                if (cur ~= nil and r.page == S.cur and r.slot == cur.slot) then
                    index = i - 1;
                end
            end
        end
        imgui.TextColored(theme.ACCENT, ('%d'):fmt(#rows));
        imgui.SameLine(0, 4 * fs);
        imgui.TextColored(theme.DIM, #rows == 1 and 'item up for auction' or 'items up for auction');
        if (pages ~= nil and (not S.done or S.want ~= nil)) then
            imgui.SameLine(0, 8 * fs);
            imgui.TextColored(theme.FAINT, S.want ~= nil and ('going to page %d...'):fmt(S.want.page)
                or ('page %d...'):fmt((S.cur or 0) + 1));
        end
        if (pages ~= nil and S.note ~= nil) then
            imgui.TextColored(theme.WARN, S.note);
        end
        -- One page at a time (the server's pages, not gathered): which, and Next page.
        if (pages == nil and ahpages.active) then
            imgui.SameLine(0, 8 * fs);
            local of = ahpages.total ~= nil and math.max(1, math.ceil(ahpages.total / 6)) or nil;
            imgui.TextColored(theme.DIM, of ~= nil and ('page %d of %d'):fmt(ahpages.page or 1, of) or ('page %d'):fmt(ahpages.page or 1));
            imgui.SameLine(0, 8 * fs);
            local wait = now - (st.sales_at or -10) < CYCLE or st.goal ~= nil;
            if (wait) then
                imgui.TextColored(theme.FAINT, 'Next page'); -- (the server takes one press each 1.5 s)
            elseif (imgui.SmallButton('Next page##ahb_next')) then
                st.goal = { 'auc1', 3, again = true, at = now, done = false };
                st.sales_at, st.next_hold = now, now + 4;
            end
        end
        local clicked, hovered = listings.draw(st.sales, rows, index, key, fs, mw - 24 * fs);
        if (clicked ~= nil) then
            local r = rows[clicked + 1];
            if (pages == nil) then
                w.req('sales', r ~= nil and r.status == 'sale' and 'choose' or 'point', clicked);
            elseif (r ~= nil and r.page == S.cur and sp.live) then
                for i, x in ipairs(sm.list) do -- (on the page shown: as the game's own list)
                    if (x.slot == r.slot) then
                        w.req('sales', x.status == 'sale' and 'choose' or 'point', i - 1);
                    end
                end
            elseif (r ~= nil and r.status == 'sale') then
                S.want = r; -- (on another page: pressed on to it, then opened there)
            end
        end
        show = ((env.focus == 'auclist') and hovered) or (pages ~= nil and rows[index + 1]) or sm.list[sm.index + 1];
    elseif (lp.live) then
        -- (no count, so the filter and Sort fit the column; not to the window's edge: it sizes itself)
        st.list.filter_w = (MID - 6) * fs - (imgui.CalcTextSize('Sort') + 22 * fs);
        -- (typing while the list has the game's focus starts its filter; Ctrl+F is the lookup's)
        st.list.type_to_filter = lp.focused and not (runtime.up('chatinput') or menus.find('inline') ~= nil);
        local clicked, hovered, enter, sort = list.draw(st.list, lm.list, lm.index, page, lp.handler * 65536 + lm.count, fs, mw, false, 'Sort');
        if (sort and #lm.list > 0) then
            st.sort = { at = now, chose = false }; -- (the game's Sort is the item menu's: opened, then pressed)
        end
        if (enter) then
            keys.swallow_enter();
        end
        local at = list.index_of(lm.list, hovered);
        if (clicked ~= nil) then
            w.req('list', 'choose', clicked);
        elseif (lp.focused and at ~= nil and at ~= st.hover and at ~= lm.index) then
            w.req('list', 'point', at);
        end
        st.hover = at;
        local follow = env.focus == 'auclist' or env.focus == 'auc3';
        show = (follow and hovered) or lm.list[lm.index + 1];
        if (#lm.list == 0) then
            imgui.TextColored(theme.DIM, cm.busy and 'Loading...' or 'Nothing up for sale here.');
        end
    else
        imgui.TextColored(theme.DIM, st.goal ~= nil and 'Opening...' or 'Pick a category at the left.');
    end
    imgui.EndChild();
    w.item = show;

    -- Right: the item, its prices, and the menu for it.
    imgui.SameLine(0, 10 * fs);
    imgui.BeginChild('##ahb_item', { rw + 10 * fs, H }, 0);
    local cw = rw;
    imgui.Dummy({ cw, 1 });
    if (item_panel(st, show, fs, cw)) then
        if (mode == 'bid') then
            buttons(w, item, 'item', ITEM_LABELS, cw, fs, 2);
            if (not item.live) then
                imgui.TextColored(theme.DIM, 'Click the item to bid on it.');
            end
        elseif (mode == 'sales') then
            buttons(w, part.listing, 'listing', LISTING_LABELS, cw, fs, 1);
            if (not part.listing.live) then
                imgui.TextColored(theme.DIM, 'Click one on sale for its menu.');
            end
        else
            imgui.TextColored(theme.DIM, 'Click it to set its price.');
        end
    end
    imgui.EndChild();
end

return P;
