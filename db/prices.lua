--[[
* facelift - db/prices: every auction house sale facelift has seen (from items' price histories),
* kept for good in one file shared by all your characters, so prices can be shown over time.
*
* The file is a log, one line a sale or a check, tab-separated:
*   item  stack (0 or 1)  date (Unix time)  price  seller  buyer      a sale
*   c  item  stack  time                                              when its price history was read
*   f  item  stack  time                                              forgotten: the lines above for it
* New lines are added to the end; a sale already kept (same item, stack, date, price and names) isn't
* added again, and a check at most once a minute an item. It's read the first time it's needed, and
* what other addons add to it (ahweb, from the website) is read in as it comes.
* With prices.path nil it's kept in memory only.
--]]

local prices = {
    path = nil,    -- the file (set by facelift.lua)
    error = nil,   -- why it couldn't be read or written, if it couldn't
    count = 0,     -- sales kept
};

local HEADER = '# facelift prices 1: item, stack, date, price, seller, buyer; or c, item, stack, time checked (tab-separated)\n';
local items = {};  -- [id * 2 + stack] = { sales = { { price, date, seller, buyer } }, seen = { [sale] = true },
                   --   at = { [date|price] = true }, checked (time or nil), written (last check line), sorted, version }
local loaded = false;

local function key(id, stack)
    return id * 2 + (stack and 1 or 0);
end

local function entry(k)
    local e = items[k];
    if (e == nil) then
        e = { sales = {}, seen = {}, at = {}, sorted = true, version = 0 };
        items[k] = e;
    end
    return e;
end

local function clean(name)
    return (tostring(name or ''):gsub('%c', ''));
end

--[[
* Keeps one sale; false if it was kept already. One missing a name is taken to be a sale kept
* already at the same time and price, if there is one (the game's copy was caught mid-change); and
* the names of one that comes with them fill in a kept sale's missing ones (true: its line is
* written, and reading the file back does the same).
--]]
local function keep(e, price, date, seller, buyer)
    local sig = ('%d|%d|%s|%s'):format(date, price, seller, buyer);
    local at = ('%d|%d'):format(date, price);
    local old = e.at[at];
    if (e.seen[sig] or (old ~= nil and (seller == '' or buyer == ''))) then
        return false;
    end
    e.seen[sig] = true;
    if (old ~= nil and (old.seller == '' or old.buyer == '')) then
        old.seller = old.seller ~= '' and old.seller or seller;
        old.buyer = old.buyer ~= '' and old.buyer or buyer;
        e.version = e.version + 1;
        return true;
    end
    local s = { price = price, date = date, seller = seller, buyer = buyer };
    e.at[at] = old or s;
    e.sales[#e.sales + 1] = s;
    e.sorted, e.version = false, e.version + 1;
    prices.count = prices.count + 1;
    return true;
end

local offset = 0;       -- how much of the file has been read
local next_look = 0;    -- os.clock() when it's next checked for lines another addon added

local function apply(line)
    local id, st, date, price, seller, buyer = line:match('^(%d+)\t([01])\t(%d+)\t(%d+)\t([^\t]*)\t([^\t\r]*)');
    if (id ~= nil) then
        keep(entry(key(tonumber(id), st == '1')), tonumber(price), tonumber(date), seller, buyer);
    else
        local fid, fst = line:match('^f\t(%d+)\t([01])\t');
        if (fid ~= nil) then
            local k = key(tonumber(fid), fst == '1');
            prices.count = prices.count - #(items[k] ~= nil and items[k].sales or {});
            items[k] = nil;
        end
        local cid, cst, t = line:match('^c\t(%d+)\t([01])\t(%d+)');
        if (cid ~= nil) then
            local e = entry(key(tonumber(cid), cst == '1'));
            t = tonumber(t);
            if (e.checked == nil or t > e.checked) then
                e.checked, e.written = t, t;
            end
        end
    end
end

--[[
* Reads the file from where it was last read: all of it the first time, then what's been added
* since (by facelift, or ahweb from the website: a line read twice changes nothing). Only whole
* lines; one still being written is read next time.
--]]
local function catch_up()
    local f = io.open(prices.path, 'rb');
    if (f == nil) then
        return; -- nothing kept yet
    end
    local size = f:seek('end');
    if (size < offset) then
        offset = 0;  -- it was replaced: what's read again is kept once
    end
    f:seek('set', offset);
    local text = f:read('*a') or '';
    f:close();
    local whole = text:match('^.*\n') or '';
    offset = offset + #whole;
    for line in whole:gmatch('[^\n]+') do
        apply(line);
    end
end

local function load()
    loaded, offset = true, 0;
    if (prices.path == nil) then
        return;
    end
    catch_up();
end

-- Takes in lines another addon added to the file, at most every few seconds.
local function look()
    if (prices.path ~= nil and os.clock() >= next_look) then
        next_look = os.clock() + 3;
        catch_up();
    end
end

local function dir_of(path)
    return path:match('^(.*)[/\\][^/\\]*$');
end

local function write(lines)
    if (prices.path == nil) then
        return;
    end
    local ok, err = pcall(function ()
        local dir = dir_of(prices.path);
        if (dir ~= nil and not ashita.fs.exists(dir)) then
            ashita.fs.create_dir(dir);
        end
        local probe = io.open(prices.path, 'r');
        local new = probe == nil;
        if (probe ~= nil) then
            probe:close();
        end
        if (loaded and not new) then
            catch_up();  -- what another addon added first, so what's next is read from past these lines
        end
        local f, why = io.open(prices.path, 'a');
        if (f == nil) then
            error(why);
        end
        if (new) then
            f:write(HEADER);
        end
        f:write(table.concat(lines));
        f:close();
        if (loaded) then
            catch_up();  -- these lines, already kept
        end
    end);
    prices.error = not ok and tostring(err) or nil;
end

--[[
* Keeps item id's sales (stack: whether they were stacks): a list of { price, date, seller, buyer }
* as a price history shows them. Sales that can't be right (no price, a date before 2001 or after
* tomorrow) are left out. Returns how many were new.
--]]
function prices.add(id, stack, sales)
    if (not loaded) then
        load();
    end
    if (id == nil or id <= 0) then
        return 0;
    end
    local e = entry(key(id, stack));
    local now = os.time();
    local lines = {};
    for _, s in ipairs(sales) do
        local price, date = tonumber(s.price) or 0, tonumber(s.date) or 0;
        local seller, buyer = clean(s.seller), clean(s.buyer);
        if (price > 0 and price <= 999999999 and date >= 1000000000 and date <= now + 86400
                and keep(e, price, date, seller, buyer)) then
            lines[#lines + 1] = ('%d\t%d\t%d\t%d\t%s\t%s\n'):format(id, stack and 1 or 0, date, price, seller, buyer);
        end
    end
    if (#lines > 0) then
        write(lines);
    end
    return #lines;
end

-- Notes that item id's price history was read at time t (now if nil), with or without sales.
function prices.check(id, stack, t)
    if (not loaded) then
        load();
    end
    if (id == nil or id <= 0) then
        return;
    end
    t = t or os.time();
    local e = entry(key(id, stack));
    if (e.checked == nil or t > e.checked) then
        e.checked, e.version = t, e.version + 1;
    end
    if (e.written == nil or t - e.written >= 60) then
        e.written = t;
        write({ ('c\t%d\t%d\t%d\n'):format(id, stack and 1 or 0, t) });
    end
end

local function oldest_first(a, b)
    if (a.date ~= b.date) then
        return a.date < b.date;
    end
    return a.price < b.price;
end

-- What's kept for item id, as { sales (oldest first, maybe none), checked (time or nil), version
-- (changes when the rest do) }, or nil if its price history was never seen.
function prices.get(id, stack)
    if (not loaded) then
        load();
    end
    look();
    local e = items[key(id, stack)];
    if (e == nil or (#e.sales == 0 and e.checked == nil)) then
        return nil;
    end
    if (not e.sorted) then
        table.sort(e.sales, oldest_first);
        e.sorted = true;
    end
    return e;
end

local function median(t)
    table.sort(t);
    local n = #t;
    return n % 2 == 1 and t[(n + 1) / 2] or math.floor((t[n / 2] + t[n / 2 + 1]) / 2);
end

--[[
* Numbers about e's sales (from prices.get), worked out once per change: { n, med (median of all),
* recent (median of the last 10, only with more than 10), low (lowest of the last 10), last (the
* latest price), first_date, last_date }, or nil with no sales.
--]]
function prices.stats(e)
    if (e == nil or #e.sales == 0) then
        return nil;
    end
    if (e.stats ~= nil and e.stats_v == e.version) then
        return e.stats;
    end
    local all, recent = {}, {};
    local n = #e.sales;
    for i, s in ipairs(e.sales) do
        all[i] = s.price;
        if (i > n - 10) then
            recent[#recent + 1] = s.price;
        end
    end
    local low = math.huge;
    for _, p in ipairs(recent) do
        low = math.min(low, p);
    end
    e.stats = { n = n, med = median(all), recent = n > 10 and median(recent) or nil, low = low,
                last = e.sales[n].price, first_date = e.sales[1].date, last_date = e.sales[n].date };
    e.stats_v = e.version;
    return e.stats;
end

-- How many items and sales are kept (read from the file the first time).
function prices.summary()
    if (not loaded) then
        load();
    end
    look();
    local n, sales = 0, 0;
    for _, e in pairs(items) do
        if (#e.sales > 0) then
            n = n + 1;
            sales = sales + #e.sales;
        end
    end
    return n, sales;
end

-- Forgets everything kept for item id (stack: its stacks), in the file too (a line that clears what's
-- above it): its next price history fills it again.
function prices.forget(id, stack)
    if (not loaded) then
        load();
    end
    local k = key(id, stack);
    prices.count = prices.count - #(items[k] ~= nil and items[k].sales or {});
    items[k] = nil;
    write({ ('f\t%d\t%d\t%d\n'):format(id, stack and 1 or 0, os.time()) });
end

-- Forgets what's in memory (the next use reads the file again).
function prices.reset()
    items, loaded, prices.count, prices.error = {}, false, 0, nil;
end

return prices;
