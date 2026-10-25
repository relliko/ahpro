--[[
* facelift - db/asks: the price you last asked for each item you put up at the auction house (one
* for selling it singly, one for a stack), kept for good in one file shared by all your characters,
* so the next sale's price box can start there (panes/pricebox).
*
* The file is a log, one line an asking price, tab-separated:
*   item  stack (0 or 1)  time (Unix)  price
* A line is added only when an item's price changes; the latest line for an item is its price. It's
* read the first time it's needed. With asks.path nil it's kept in memory only.
--]]

local asks = {
    path = nil,   -- the file (set by facelift.lua and ahpro.lua, beside prices.tsv)
    error = nil,  -- why it couldn't be read or written, if it couldn't
};

local HEADER = '# facelift asking prices 1: item, stack, time, price (tab-separated)\n';
local kept = {};  -- [id * 2 + stack] = price
local loaded = false;

local function key(id, stack)
    return id * 2 + (stack and 1 or 0);
end

local function load()
    loaded = true;
    if (asks.path == nil) then
        return;
    end
    local f = io.open(asks.path, 'r');
    if (f == nil) then
        return; -- nothing kept yet
    end
    for line in f:lines() do
        local id, st, price = line:match('^(%d+)\t([01])\t%d+\t(%d+)');
        if (id ~= nil) then
            kept[key(tonumber(id), st == '1')] = tonumber(price);
        end
    end
    f:close();
end

local function write(line)
    if (asks.path == nil) then
        return;
    end
    local ok, err = pcall(function ()
        local dir = asks.path:match('^(.*)[/\\][^/\\]*$');
        if (dir ~= nil and not ashita.fs.exists(dir)) then
            ashita.fs.create_dir(dir);
        end
        local probe = io.open(asks.path, 'r');
        local new = probe == nil;
        if (probe ~= nil) then
            probe:close();
        end
        local f, why = io.open(asks.path, 'a');
        if (f == nil) then
            error(why);
        end
        if (new) then
            f:write(HEADER);
        end
        f:write(line);
        f:close();
    end);
    asks.error = not ok and tostring(err) or nil;
end

-- The price you last asked for item id (stack: a stack of it), or nil.
function asks.get(id, stack)
    if (not loaded) then
        load();
    end
    return id ~= nil and kept[key(id, stack)] or nil;
end

-- Keeps price as what you asked for item id (stack: a stack of it). Prices the auction house
-- wouldn't take (none, or over 999,999,999) aren't kept.
function asks.set(id, stack, price)
    if (not loaded) then
        load();
    end
    price = tonumber(price);
    if (id == nil or id <= 0 or price == nil or price < 1 or price > 999999999) then
        return;
    end
    price = math.floor(price);
    local k = key(id, stack);
    if (kept[k] == price) then
        return;
    end
    kept[k] = price;
    write(('%d\t%d\t%d\t%d\n'):format(id, stack and 1 or 0, os.time(), price));
end

-- Forgets what's in memory (the next use reads the file again).
function asks.reset()
    kept, loaded, asks.error = {}, false, nil;
end

return asks;
