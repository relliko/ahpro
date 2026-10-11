--[[
* facelift - adapters/ahpath: where you are in the auction house's menus (its first menu auc1: Bid,
* Sell, Sales Status; auc2 and the category menus under Bid: data/ahmenus), for the one-window
* auction house (panes/ahbrowse), and getting to another place the way the keys do.
*
* The game keeps the menus it came through open (hidden under the newer one) and, once a category's
* list is up, keeps the menu it was picked from shown under the list. That menu still takes Enter
* while the list is up (its OnInput 0x1DA730: with the list's slot set only Enter, then OnSelect),
* which asks for its option's list in the open list: the game's own mouse does the same. So another
* category of the same menu is SetCursor + Enter on it. Anything else is reached a key at a time,
* two frames apart, each on a menu that's shown and not closing: Escape (MenuInput 6) on the small
* menus (auc3, auc4), on what's open over the menus (the item list or Sales Status, the Sell picker)
* and on the menus not on the way, then Enter on the options on the way (auc1's Bid opens auc2; its
* Sell the picker; its Sales Status the listings). Nothing while the list is loading, or a price box,
* yes/no, price history or sort menu is up.
*
* Model: chain[1..n] = { name, obj, cursor } the open menus (auc1 first), shallowest first; deep (the
* deepest one's name), cursor (its cursor), list (an item list is open), busy (it's loading).
--]]

local safemem = require('core.safemem');
local sigs    = require('core.sigs');
local menus   = require('core.menus');
local game    = require('core.game');
local AH      = require('data.ahmenus');

local A = {
    sigs = { 'menu.input', 'menu.set_cursor', 'list.state' },
};

local CATS, MENUS = {}, {}; -- the category menus (auc2 and under); all of them with auc1
for _, n in ipairs(AH.menus) do
    MENUS[n] = true;
    if (n ~= 'auc1') then
        CATS[n] = true;
    end
end
A.CATS = CATS;

-- The way to option n of menu name from auc1: { { menu, option }, ... } ending with { name, n }.
local parent = {};
for m, t in pairs(AH.opens) do
    for o, sub in pairs(t) do
        parent[sub] = { m, o };
    end
end
function A.path(name, n)
    local out = { { name, n } };
    local at = name;
    while (parent[at] ~= nil) do
        table.insert(out, 1, parent[at]);
        at = parent[at][1];
    end
    return out;
end

function A.new()
    return { chain = {}, n = 0, deep = nil, cursor = 0, list = false, busy = false };
end

-- The deepest open category menu.
function A.locate(p)
    local best, bd = nil, -1;
    for obj, name in pairs(menus.open()) do
        if (MENUS[name] and (AH.depth[name] or 0) > bd) then
            best, bd = obj, AH.depth[name] or 0;
        end
    end
    if (best == nil) then
        return nil;
    end
    return best, safemem.u32(best + 0x0C) or 0;
end

local function busy()
    local a = sigs.get('list.state');
    local s = a ~= 0 and safemem.read(a, 2) or nil;
    return s == nil or safemem.le16(s, 0) ~= 4;
end

function A.read(p, m)
    m.n = 0;
    for obj, name in pairs(menus.open()) do
        if (MENUS[name]) then
            m.n = m.n + 1;
            local c = m.chain[m.n] or {};
            m.chain[m.n] = c;
            c.name, c.obj, c.cursor = name, obj, menus.cursor(obj) or 0;
        end
    end
    for i = #m.chain, m.n + 1, -1 do
        m.chain[i] = nil;
    end
    table.sort(m.chain, function (a, b) return (AH.depth[a.name] or 0) < (AH.depth[b.name] or 0); end);
    if (m.n == 0) then
        return false;
    end
    local d = m.chain[m.n];
    m.deep, m.cursor = d.name, d.cursor;
    m.list = menus.find('auclist') ~= nil;
    m.busy = m.list and busy();
    return true;
end

local now = A.new();
local wait = 0; -- steps to sit out after a key (the game acts on it in its next update)

-- Whether a menu can take a key now: shown, not closing.
local function ready(obj)
    return obj ~= nil and menus.shown(obj) and menus.closing(obj) == false;
end

local function key(obj, k)
    wait = 2;
    game.call('menu.input', obj, k);
end

--[[
* One step toward option n of menu name (a category's list, the menu it opens, or auc1's Bid / Sell /
* Sales Status), or, n 0, back out to menu name (out of the menus under it): true once there (or that
* last option pressed), false while on the way, nil if it can't go on (something else is up). again:
* pressed even when already there (Sales Status once more: the server's next page, ah_pagination).
--]]
function A.step(name, n, again)
    if (wait > 0) then
        wait = wait - 1;
        return false;
    end
    if (not A.read({}, now)) then
        return false;
    end
    for _, other in ipairs({ 'moneyctr', 'auchisto', 'comyn', 'shopbuy', 'wepsort', 'armsort', 'aucyn' }) do
        if (menus.find(other) ~= nil) then
            return nil;
        end
    end
    -- The small menus first (the item's, a listing's): Escape them.
    for _, small in ipairs({ 'auc3', 'auc4' }) do
        local o = menus.find(small);
        if (o ~= nil) then
            if (ready(o)) then
                key(o, 6);
            end
            return false;
        end
    end
    local list, picker = menus.find('auclist'), menus.find('inventor');
    local d = now.chain[now.n];
    -- Already there: the Sell picker open, or Sales Status (a list over auc1).
    if (name == 'auc1' and n == 2 and picker ~= nil) then
        return true;
    elseif (name == 'auc1' and n == 3 and list ~= nil and d.name == 'auc1' and not again) then
        return true; -- (again: out of it and Sales Status pressed once more, as a player cycles it)
    end
    local way = A.path(name, n);
    local at = {};
    for i, s in ipairs(way) do
        at[s[1]] = i;
    end
    -- What's open over the menus, when it isn't where this goes: the Sell picker, a list (Sales
    -- Status; or a category's, unless its menu is the last on the way).
    if (picker ~= nil) then
        if (ready(picker)) then
            key(picker, 6);
        end
        return false;
    end
    if (list ~= nil and (name == 'auc1' or at[d.name] == nil or at[d.name] < #way)) then
        if (ready(list)) then
            key(list, 6);
        end
        return false;
    end
    if (n == 0 and at[d.name] ~= nil) then
        return true; -- (back in menu name, or above it: nothing deeper)
    end
    if (at[d.name] == nil) then
        if (ready(d.obj)) then
            key(d.obj, 6); -- (a menu off the way: back out of it)
        end
        return false;
    end
    local s = way[at[d.name]];
    if (not ready(d.obj) or (list ~= nil and busy())) then
        return false;
    end
    if (s[1] == name and list ~= nil and d.cursor == n) then
        return true; -- (that category's list already up)
    end
    if (game.call('menu.set_cursor', d.obj, s[2]) and menus.cursor(d.obj) == s[2]) then
        key(d.obj, 5);
        return s[1] == name;
    end
    return false;
end

A.actions = {
    -- The game's cursor to option n of the deepest category menu (the keys moved it onto one hidden
    -- for the era: on past it, as SetCursor).
    cursor = function (p, m, n)
        local d = m.chain[m.n];
        if (d ~= nil and ready(d.obj)) then
            game.call('menu.set_cursor', d.obj, n);
        end
    end,
    -- Toward goal { menu, option } (from panes/ahbrowse, every frame until goal.done): one step.
    go = function (p, m, goal)
        local r = A.step(goal[1], goal[2], goal.again);
        goal.done = r ~= false;
    end,
};

return A;
