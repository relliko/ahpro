--[[
* facelift - adapters/auchisto: an item's price history at the auction house (menu 'auchisto'), a
* scroll list (adapters/scrolllist) with:
*   +0x898 the item's id (word)   +0x58 the list asked for (6 singles, 7 stacks)
* Each row is 0x54 bytes; its +0x48 points at a sale: +4 price, +8 date (Unix time, shown in local
* time), +0x0C seller and +0x1C buyer (16 characters each), as the search server sends them (10 at
* most). The game asks for the history as the menu opens (the item menu's Price history closes the
* list first), so it's empty until the item lists' loading state (list.state) says loaded (4). Its
* Enter writes the sale to your own chat log.
*
* The game reads a sale's text once, when it fills its rows; the memory the rows point at doesn't
* stay put after that (seen in game: names and dates came and went). So a list is read as soon as
* it's loaded, every frame until two readings that look right agree, and then kept as it is while
* it's the same list; later readings only fill in names it had blank. /facelift trace logs what
* the game has there as it changes.
--]]

local safemem    = require('core.safemem');
local sigs       = require('core.sigs');
local scrolllist = require('adapters.scrolllist');
local menus      = require('core.menus');
local trace      = require('dev.trace');

local A = {
    sigs = { 'auchisto.vtable', 'auchisto.slot', 'list.state', 'list.set_index' },
};

function A.new()
    return { page = 0, top = 0, count = 0, rows = 0, cursor = 1, index = 0, id = 0, stack = false, busy = true,
             steady = false, list = {}, version = 0,
             cache = { key = nil, loading = false, kept = false, cand = nil, tries = 0, age = 0 } };
end

local function name(block, at)
    local s = block:sub(at + 1, at + 16);
    local z = s:find('\0', 1, true);
    return z ~= nil and s:sub(1, z - 1) or s;
end

-- Oldest first, as the game lists them (so its arrow keys move the same way here), sales at the
-- same time in the game's order.
local function older(a, b)
    if (a.date ~= b.date) then
        return a.date < b.date;
    end
    return a.row < b.row;
end

local function hex(s)
    return (s:gsub('.', function (c) return ('%02X'):format(c:byte()); end));
end

-- The game's rows as sales, sorted, and a string that's the same for the same sales.
local function read_sales(m)
    local list = {};
    if (m.rows == 0 or m.count <= 0 or m.count > 100) then
        return list, '';
    end
    local block = safemem.read(m.rows, m.count * 0x54);
    if (block == nil) then
        return list, '';
    end
    local log = trace.on() and {} or nil;
    for i = 0, m.count - 1 do
        local node = safemem.le32(block, i * 0x54 + 0x48);
        local e = node ~= 0 and safemem.read(node, 0x2C) or nil;
        if (e ~= nil) then
            list[#list + 1] = { price = safemem.le32(e, 4), date = safemem.le32(e, 8),
                                seller = name(e, 0x0C), buyer = name(e, 0x1C), row = i };
        end
        if (log ~= nil) then
            log[#log + 1] = ('row %d %s\n  entry %08X %s'):format(i, hex(block:sub(i * 0x54 + 1, i * 0x54 + 0x54)), node, e and hex(e) or '-');
        end
    end
    if (log ~= nil) then
        trace.state('auchisto', ('item %d count %d rows %08X\n%s'):format(m.id, m.count, m.rows, table.concat(log, '\n')));
    end
    table.sort(list, older);
    local sig = {};
    for i, r in ipairs(list) do
        sig[i] = ('%d|%d|%s|%s'):format(r.price, r.date, r.seller, r.buyer);
    end
    return list, table.concat(sig, ';');
end

-- Whether a reading looks like sales: prices, dates from 2001 to tomorrow, names of letters only
-- (or blank).
local function sane(list)
    local tomorrow = os.time() + 86400;
    for _, r in ipairs(list) do
        if (r.price <= 0 or r.price > 999999999 or r.date < 1000000000 or r.date > tomorrow
                or not r.seller:match('^%a*$') or not r.buyer:match('^%a*$')) then
            return false;
        end
    end
    return true;
end

local SETTLE = 60; -- readings (frames) before a list that never reads the same twice is shown anyway

--[[
* The sales as { price, date, seller, buyer, row (the game's row, from 0) }, oldest first. A list
* (its rows, count and item; a new load) is read every frame until two sane readings agree, then
* kept (m.steady); after that it's read every few frames only to fill in blank names. A list that
* never settles is shown as last read after SETTLE frames, but not steady (not kept in db/prices).
--]]
local function sales(m)
    local c = m.cache;
    local key = ('%d/%d/%d'):format(m.rows, m.count, m.id);
    if (m.busy) then
        c.loading = true;
    end
    if (c.key ~= key or (c.loading and not m.busy)) then
        c.key, c.loading, c.kept, c.cand, c.tries, c.age = key, m.busy, false, nil, 0, 0;
        m.list, m.steady = {}, false;
        m.version = m.version + 1;
    end
    if (m.busy) then
        return;
    end
    if (c.kept) then
        c.age = c.age + 1;
        if (c.age < 15 and not trace.on()) then -- every frame while tracing
            return;
        end
        c.age = 0;
    end
    local list, sig = read_sales(m);
    local ok = sane(list);
    if (not c.kept) then
        c.tries = c.tries + 1;
        if (ok and sig == c.cand) then
            m.list, m.steady, c.kept = list, true, true;
            m.version = m.version + 1;
        elseif (c.tries >= SETTLE) then
            m.list, m.steady, c.kept = list, false, true;
            m.version = m.version + 1;
        elseif (ok) then
            c.cand = sig;
            if (#m.list == 0 and #list > 0) then
                m.list = list; -- shown meanwhile
                m.version = m.version + 1;
            end
        end
        return;
    end
    -- Kept: only names it had blank, from a sane reading of the same sale in the same row.
    if (not ok) then
        return;
    end
    local by_row = {};
    for _, r in ipairs(list) do
        by_row[r.row] = r;
    end
    local filled = false;
    for _, s in ipairs(m.list) do
        local r = by_row[s.row];
        if (r ~= nil and r.date == s.date and r.price == s.price) then
            if (s.seller == '' and r.seller ~= '') then
                s.seller, filled = r.seller, true;
            end
            if (s.buyer == '' and r.buyer ~= '') then
                s.buyer, filled = r.buyer, true;
            end
        end
    end
    if (filled) then
        m.version = m.version + 1;
    end
end

-- The list's own fields into m (not the sales); false if the handler isn't the price history.
local function check(p, m)
    local h = p.handler;
    if (h == nil or h == 0 or safemem.u32(h) ~= sigs.get('auchisto.vtable') or safemem.u32(h + 0x08) ~= p.obj) then
        return false;
    end
    local s = safemem.read(h + 0x58, 4);
    local id = safemem.read(h + 0x898, 2);
    local state = safemem.read(sigs.get('list.state'), 2);
    if (s == nil or id == nil or state == nil or not scrolllist.read(h, p.obj, m)) then
        return false;
    end
    m.id, m.stack, m.busy = safemem.le16(id, 0), safemem.le32(s, 0) == 7, safemem.le16(state, 0) ~= 4;
    return true;
end

-- The history's menu and handler while another menu has focus (the Sell flow's price box), or nil.
function A.locate(p)
    local slot = sigs.get('auchisto.slot');
    local h = slot ~= 0 and safemem.u32(slot) or nil;
    local obj = h ~= nil and h ~= 0 and safemem.u32(h + 0x08) or nil;
    if (obj == nil or obj == 0 or menus.open()[obj] ~= 'auchisto') then
        return nil;
    end
    return obj, h;
end

-- Fills m, sales too; false if the handler isn't the price history.
function A.read(p, m)
    if (not check(p, m)) then
        return false;
    end
    sales(m);
    return true;
end

local now = {};

A.actions = {
    -- Sale i (from 0): the game's cursor goes there.
    point = function (p, m, i)
        if (check(p, now) and i >= 0 and i < now.count) then
            scrolllist.point(p.handler, i);
        end
    end,
    -- Sale i (from 0): what the game's Enter does on it (writes it to your chat log).
    choose = function (p, m, i)
        if (check(p, now) and i >= 0 and i < now.count) then
            scrolllist.choose(p.handler, i);
        end
    end,
};

return A;
