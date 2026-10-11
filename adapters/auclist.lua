--[[
* facelift - adapters/auclist: the auction house item list (menu 'auclist'), a scroll list
* (adapters/scrolllist) with:
*   +0x898 mode (0 browsing a category, 1 your Sales Status boxes; only 0 is handled)
* Each row is 0x54 bytes; its +0x48 points at the entry: +0 kind (3 single, 4 stack),
* +4 item id (word), +8 how many are for sale as singles, +0xC as stacks; the game shows that as "[n]".
* Choosing a row opens the item's page (the auc3 menu), like the game's Enter.
*
* A single item's name is coloured as the game colours it when it draws the row (FFXiMain 0x1F54FA;
* the colour isn't stored in the row): equipment you're wearing green (0x80509050, 0x131FA0), and
* equipment your main job can wear now yellow (0x80909040; 0x132050: race, job, level, superior
* level). Worked out here from Ashita's player, inventory and item data. Not copied: the game's
* check of slots blocked by a status (Encumbrance), and its scroll colours (known spells green,
* learnable yellow).
--]]

local safemem    = require('core.safemem');
local sigs       = require('core.sigs');
local menus      = require('core.menus');
local scrolllist = require('adapters.scrolllist');
local gametext   = require('core.gametext');

local A = {
    sigs = { 'auclist.vtable', 'auclist.slot', 'list.set_index' },
};

function A.new()
    return { page = 0, top = 0, count = 0, rows = 0, cursor = 1, index = 0, list = {}, version = 0,
             cache = { rows = 0, count = -1, age = 0 } };
end

local GREEN  = { 0.63, 1.00, 0.63, 1.00 }; -- 0x80509050 (0x80 is full in the game's colours)
local YELLOW = { 1.00, 1.00, 0.50, 1.00 }; -- 0x80909040

-- The player as the game's colours need it: main job and its level, race, and the ids of the items
-- worn; nil if Ashita can't say.
local function wearer()
    local ok, w = pcall(function ()
        local mm = AshitaCore:GetMemoryManager();
        local player, inv = mm:GetPlayer(), mm:GetInventory();
        local w = { job = player:GetMainJob(), level = player:GetMainJobLevel(),
                    race = mm:GetEntity():GetRace(mm:GetParty():GetMemberTargetIndex(0)), worn = {} };
        for slot = 0, 15 do
            local e = inv:GetEquippedItem(slot);
            local at = e ~= nil and e.Index or 0; -- container * 256 + index
            if (at % 256 ~= 0) then
                local it = inv:GetContainerItem(math.floor(at / 256) % 256, at % 256);
                if (it ~= nil and it.Id ~= 0) then
                    w.worn[it.Id] = true;
                end
            end
        end
        return w;
    end);
    if (not ok or w == nil or type(w.job) ~= 'number' or type(w.level) ~= 'number' or type(w.race) ~= 'number') then
        return nil;
    end
    return w;
end

-- A single item's name colour as the game gives it, or nil for the usual one. k: the item (about()).
local function name_color(k, w)
    if (w == nil or k.level == 0) then
        return nil;
    end
    if (w.worn[k.id]) then
        return GREEN;
    end
    if (bit.band(k.races, bit.lshift(1, w.race)) ~= 0 and bit.band(k.jobs, bit.lshift(1, w.job)) ~= 0
            and k.level <= w.level and k.su == 0) then
        return YELLOW;
    end
    return nil;
end

-- Items' names and records by id (they don't change; the biggest categories have 400-odd).
local known = {};
local function about(res, id)
    local k = known[id];
    if (k == nil) then
        local item = res:GetItemById(id);
        local name = gametext.name(item, id);
        k = { id = id, name = name, lname = name:lower(), stack_size = item ~= nil and item.StackSize or 1,
              level = item ~= nil and item.Level or 0, jobs = item ~= nil and item.Jobs or 0,
              races = item ~= nil and item.Races or 0, su = item ~= nil and item.SuperiorLevel or 0 };
        known[id] = k;
    end
    return k;
end

-- The rows as { id, stack, n, name, lname, stack_size, color }, re-read when the list changes and
-- every few frames (the counts arrive after the list). The entries the rows point at are read in one
-- go when they lie one after another (0x10 apart), else one by one.
local function entries(m)
    local c = m.cache;
    c.age = c.age + 1;
    if (c.rows == m.rows and c.count == m.count and c.age < 15) then
        return;
    end
    c.rows, c.count, c.age = m.rows, m.count, 0;
    m.list = {};
    m.version = m.version + 1;
    if (m.rows == 0 or m.count <= 0 or m.count > 4000) then
        return;
    end
    local block = safemem.read(m.rows, m.count * 0x54);
    if (block == nil) then
        return;
    end
    local first = safemem.le32(block, 0x48);
    local together = first ~= 0;
    for i = 1, m.count - 1 do
        if (not together) then
            break;
        end
        together = safemem.le32(block, i * 0x54 + 0x48) == first + i * 0x10;
    end
    local all = together and safemem.read(first, m.count * 0x10) or nil;
    local res = AshitaCore:GetResourceManager();
    local w = wearer();
    for i = 0, m.count - 1 do
        local e, at = all, i * 0x10;
        if (e == nil) then
            local node = safemem.le32(block, i * 0x54 + 0x48);
            e, at = node ~= 0 and safemem.read(node, 0x10) or nil, 0;
        end
        local kind = e ~= nil and safemem.le32(e, at) or 0;
        local row = { kind = kind, id = 0, n = nil, name = '?', lname = '?' };
        if (kind == 3 or kind == 4) then
            row.id = safemem.le16(e, at + 4);
            row.stack = kind == 4;
            row.n = safemem.le32(e, at + (kind == 4 and 0x0C or 0x08));
            local k = about(res, row.id);
            row.name, row.lname, row.stack_size = k.name, k.lname, k.stack_size;
            row.color = kind == 3 and name_color(k, w) or nil;
        end
        m.list[i + 1] = row;
    end
end

-- The list's own fields into m (not the rows); false if the handler isn't the auction list
-- browsing a category.
local function check(p, m)
    local h = p.handler;
    if (h == nil or h == 0 or safemem.u32(h) ~= sigs.get('auclist.vtable') or safemem.u32(h + 0x08) ~= p.obj) then
        return false;
    end
    local mode = safemem.read(h + 0x898, 1);
    return mode ~= nil and mode:byte(1) == 0 and scrolllist.read(h, p.obj, m);
end

-- Fills m, rows too; false if the handler isn't the auction list browsing a category.
function A.read(p, m)
    if (not check(p, m)) then
        return false;
    end
    entries(m);
    return true;
end

-- The list's menu and handler while another window has focus, or nil (it must be open).
function A.locate(p)
    local slot = sigs.get('auclist.slot');
    local h = slot ~= 0 and safemem.u32(slot) or nil;
    local obj = h ~= nil and h ~= 0 and safemem.u32(h + 0x08) or nil;
    if (obj == nil or obj == 0 or menus.open()[obj] ~= 'auclist') then
        return nil;
    end
    return obj, h;
end

local now = {};

A.actions = {
    -- Row i (from 0): the game's cursor there (the mouse over it).
    point = function (p, m, i)
        if (check(p, now) and i >= 0 and i < now.count) then
            scrolllist.point(p.handler, i);
        end
    end,
    -- Row i (from 0): what the game's Enter does on it.
    choose = function (p, m, i)
        if (not check(p, now) or i < 0 or i >= now.count) then
            return;
        end
        scrolllist.choose(p.handler, i);
    end,
};

return A;
