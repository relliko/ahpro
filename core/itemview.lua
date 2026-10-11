--[[
* facelift - core/itemview: what the game's item tooltip shows for an item, line for line (research
* notes-tooltip.md, 'Item tooltip: what the game draws'), as a view ui/iteminfo draws:
*   icon, tint (the game's colour for it: a linkshell's), stack (the max stack, shops and stacks)
*   name: the item's log name, its first letter upper-cased ('Empress band'), name_color
*   badges: Aug, Rare, Ex, Tmp, Alt, each { label, pic (the game's sprite, when it can be read) }
*   typeline: weapons '(Sword)', armor '[Ring]', then the races ('All Races '), then 'Su3'
*   desc: the description's lines (the game's own wrapping when from the tooltip, else one text)
*   lv: 'Lv.1 All Jobs' (weapons and armor), aug: the augments' lines
*   right: the right-aligned lines, { text, color }: the per-type line ('<6/7 0:00/[16:00:00, 0:15]>',
*   '<{fire} STG:12>', '<name>'...), the crafter's signature '[name]', '<Item Level:119>'.
* Colours are the game's (0x80 a channel is full).
*
* from_tooltip(h): the game's tooltip handler (iteminfo / itemxinf), whatever item it shows: the text
* it rebuilds every frame (+0x2C the per-type line in the colour +0x338, +0xAC the signature, +0x12C
* the Lv line, +0x1B8 the augments, +0x278 the item level), the item's record as the game parsed it
* (h+0x1C: its fields through the pointers at +0x14B4.., the description pre-wrapped at [+8], s8 +4
* lines, their lengths u32 +0x10..), its badge sprites (h+0x358..+0x368) and tint (h+0x28). Exact,
* for any item, the server's own item data included (the game reads its DAT overlay).
*
* from_item(id, ext, bag, slot): an item the game's tooltip isn't on (a row facelift's list offers),
* from Ashita's item data and the item's extra data (ext: its 0x1C bytes, or nil), by the same rules:
* the Lv line, the item level, a charged item's line (13BBF0: charges left/max, time until usable,
* the recast and the use delay, from extra data kind 1: [1] charges, +4 next use, +8 usable after
* equipping, Vana'diel time). Augments and the per-type lines of other kinds come only from the game.
--]]

local safemem  = require('core.safemem');
local sigs     = require('core.sigs');
local gametext = require('core.gametext');

local V = {};

V.WHITE, V.GREEN, V.YELLOW, V.AUG = 0x80808080, 0x80509050, 0x80909040, 0x80808050;

local JOBS = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN',
               'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' };
-- Weapons: by skill; armor: the first slot bit in this order; races: an exact match, else the first
-- sharing a bit (GetString 0x0C; every race string ends with a space).
local SKILLS = { [1] = '(Hand-to-Hand)', [2] = '(Dagger)', [3] = '(Sword)', [4] = '(Great Sword)', [5] = '(Axe)',
                 [6] = '(Great Axe)', [7] = '(Scythe)', [8] = '(Polearm)', [9] = '(Katana)', [10] = '(Great Katana)',
                 [11] = '(Club)', [12] = '(Staff)', [25] = '(Archery)', [26] = '(Marksmanship)', [27] = '(Throwing)',
                 [41] = '(String Instr.)', [42] = '(Wind Instr.)', [45] = '(Handbell)', [48] = '(Fishing Tackle)' };
local SLOTS = { { 0x10, '[Head]' }, { 0x20, '[Body]' }, { 0x80, '[Legs]' }, { 0x40, '[Hands]' }, { 0x2000, '[Ring]' },
                { 0x800, '[Ear]' }, { 0x200, '[Neck]' }, { 0x8000, '[Back]' }, { 0x400, '[Waist]' }, { 0x100, '[Feet]' } };
local RACES = { { 0x1FE, 'All Races ' }, { 0x12A, 'All \226\153\130 ' }, { 0xD4, 'All \226\153\128 ' }, { 0x06, 'H ' },
                { 0x02, 'H\226\153\130 ' }, { 0x04, 'H\226\153\128 ' }, { 0x18, 'E ' }, { 0x08, 'E\226\153\130 ' },
                { 0x10, 'E\226\153\128 ' }, { 0x60, 'T ' }, { 0x20, 'T\226\153\130 ' }, { 0x40, 'T\226\153\128 ' },
                { 0x100, 'G ' }, { 0x80, 'M ' } };

local function has(v, b) return math.floor(v / b) % 2 == 1; end

local function typeline(kind, skill, slots, races, sup)
    local t = nil;
    if (kind == 4) then
        t = SKILLS[skill] or '';
    elseif (kind == 5) then
        t = '';
        for _, s in ipairs(SLOTS) do
            if (has(slots, s[1])) then
                t = s[2];
                break;
            end
        end
    else
        return nil;
    end
    local r = nil;
    for _, e in ipairs(RACES) do
        if (e[1] == races) then
            r = e[2];
            break;
        end
    end
    if (r == nil) then
        for _, e in ipairs(RACES) do
            if (races ~= 0 and bit.band(e[1], races) ~= 0) then
                r = e[2];
                break;
            end
        end
    end
    t = t .. (r or '');
    if (sup ~= nil and sup > 0) then
        t = t .. ('Su%d'):format(sup);
    end
    return t;
end

-- 'Lv.%d ' and the jobs ('All Jobs', or 'WAR/MNK/...'), as 0x13AE30.
local function lvline(level, jobs)
    if (jobs == nil or jobs == 0) then
        return nil;
    end
    if (jobs == 0x7FFFFE) then
        return ('Lv.%d All Jobs'):format(level or 0);
    end
    local out = {};
    for j = 1, 22 do
        if (has(jobs, 2 ^ j)) then
            out[#out + 1] = JOBS[j];
        end
    end
    return ('Lv.%d %s'):format(level or 0, table.concat(out, '/'));
end

-- The name as the tooltip writes it: the log name, its first letter upper-cased.
local function name(item, id)
    local n = nil;
    pcall(function () n = item.LogNameSingular[1]; end);
    if (type(n) ~= 'string' or n == '') then
        pcall(function () n = item.Name[1]; end);
    end
    local t = type(n) == 'string' and n ~= '' and gametext.text(n) or ('item %d'):format(id or 0);
    return t:sub(1, 1):upper() .. t:sub(2);
end

-- A text buffer of the game's (char*, up to n bytes) as raw bytes, or nil when empty.
local function buffer(p, n)
    local s = safemem.read(p, n);
    local z = s ~= nil and s:find('\0', 1, true) or nil;
    if (z == nil or z == 1) then
        return nil;
    end
    return s:sub(1, z - 1);
end

-- Whether the item in bag / slot is worn (Ashita's equipment: container * 256 + index).
local function worn(bag, slot)
    if (slot == nil or slot == 0) then
        return false;
    end
    local ok, w = pcall(function ()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        for s = 0, 15 do
            local e = inv:GetEquippedItem(s);
            if (e ~= nil and e.Index == bag * 256 + slot) then
                return true;
            end
        end
        return false;
    end);
    return ok and w == true;
end

local BADGES = { { 'Aug', 0x364 }, { 'Rare', 0x358 }, { 'Ex', 0x35C }, { 'Tmp', 0x360 }, { 'Alt', 0x368 } };

-- The badges (13CC50): Aug when the extra data is augments (kind 2 or 3), Rare flags 0x8000, Ex 0x4000,
-- Tmp in the temporary bag (3, and no more after it), Alt flags 0x10; with the game's sprites (h's).
local function badges(flags, ext0, bag, h)
    local out = {};
    local function add(which)
        for _, b in ipairs(BADGES) do
            if (b[1] == which) then
                local sp = h ~= nil and safemem.u32(h + b[2]) or nil;
                local pic = sp ~= nil and sp ~= 0 and require('adapters.menuopts').picture(sp) or nil;
                out[#out + 1] = { label = which, pic = pic };
            end
        end
    end
    local aug = ext0 == 2 or ext0 == 3;
    if (aug) then add('Aug'); end
    if (has(flags, 0x8000)) then add('Rare'); end
    if (has(flags, 0x4000)) then add('Ex'); end
    if (bag == 3) then
        add('Tmp');
        return out;
    end
    if (has(flags, 0x10)) then add('Alt'); end
    return out;
end

-- The game's tooltip handler's sprites for the badges, for items it isn't on (the same sprites).
local function tooltip_handler()
    local slot = sigs.get('iteminfo.slot');
    local h = slot ~= 0 and safemem.u32(slot) or nil;
    return h ~= nil and h ~= 0 and h or nil;
end

function V.from_tooltip(h)
    local hd = safemem.read(h, 0x3A8);
    if (hd == nil) then
        return nil;
    end
    local id, slot = safemem.le16(hd, 0x24), hd:byte(0x27);
    local IR = safemem.le32(hd, 0x1C);
    if (id == 0 or IR == 0) then
        return nil;
    end
    local bag, extp = safemem.le32(hd, 0x340), safemem.le32(hd, 0x348);
    local ptrs = safemem.read(IR + 0x14B4, 0x34);
    if (ptrs == nil) then
        return nil;
    end
    local function field(off, n) -- the record's field through its pointer at IR + off
        local p = safemem.le32(ptrs, off - 0x14B4);
        local s = p ~= 0 and safemem.read(p, n) or nil;
        if (s == nil) then
            return 0;
        end
        return n == 1 and s:byte(1) or safemem.le16(s, 0);
    end
    local kind, flags, stack = field(0x14B4, 2), field(0x14BC, 2), field(0x14C0, 2);
    local slots, races, sup = field(0x14D4, 2), field(0x14D8, 2), field(0x14E0, 1);
    local skill = kind == 4 and field(0x14E4, 2) or 0;
    local ext0 = extp ~= 0 and (safemem.read(extp, 1) or '\0'):byte(1) or 0;
    local item = AshitaCore:GetResourceManager():GetItemById(id);
    local v = { id = id, tint = safemem.le32(hd, 0x28), from_game = true };
    v.stack = (hd:byte(0x371) ~= 0 and stack > 1) and stack or nil;
    v.name = name(item, id);
    v.name_color = hd:byte(0x371) ~= 0 and V.YELLOW or (worn(bag, slot) and V.GREEN or V.WHITE);
    v.badges = badges(flags, ext0, bag, h);
    v.typeline = typeline(kind, skill, slots, races, sup);
    -- The description, as the game wrapped it.
    local text = safemem.u32(IR + 8);
    local hdr = safemem.read(IR + 4, 0x0C + 4 * 20);
    local count = hdr ~= nil and hdr:byte(1) or 0;
    count = count < 0x80 and math.min(count, 20) or 0;
    v.desc = {};
    if (count > 0 and text ~= nil and text ~= 0) then
        local total = 0;
        for n = 0, count - 1 do
            total = total + safemem.le32(hdr, 0x0C + 4 * n) + 1;
        end
        local raw = safemem.read(text, math.min(total, 0x1000)) or '';
        local at = 1;
        for n = 0, count - 1 do
            local len = safemem.le32(hdr, 0x0C + 4 * n);
            v.desc[#v.desc + 1] = raw:sub(at, at + len - 1);
            at = at + len;
            if (raw:sub(at, at) == '\n') then
                at = at + 1;
            end
        end
        v.wrapped = true;
    end
    local hide = hd:byte(0x375);
    v.lv = buffer(h + 0x12C, 0x8C);
    v.aug = buffer(h + 0x1B8, 0xC0);
    v.right = {};
    local l2c = hide % 2 == 0 and buffer(h + 0x2C, 0x80) or nil;
    local lac = math.floor(hide / 2) % 2 == 0 and buffer(h + 0xAC, 0x80) or nil;
    local l278 = buffer(h + 0x278, 0xC0);
    if (l2c ~= nil) then v.right[#v.right + 1] = { text = l2c, color = safemem.le32(hd, 0x338) }; end
    if (lac ~= nil) then v.right[#v.right + 1] = { text = lac, color = V.WHITE }; end
    if (l278 ~= nil) then v.right[#v.right + 1] = { text = l278, color = V.WHITE }; end
    return v;
end

-- A time as the game writes it (0x1C93C0): '1:04:05' from an hour on, else '4:05'.
local function hms(s)
    s = math.max(0, math.floor(s));
    if (s >= 3600) then
        return ('%d:%02d:%02d'):format(math.floor(s / 3600), math.floor(s / 60) % 60, s % 60);
    end
    return ('%d:%02d'):format(math.floor(s / 60), s % 60);
end

-- The game's time in Vana'diel seconds (the clock the extra data's times are on), or nil.
local function now()
    local cb, co = sigs.get('clock.base'), sigs.get('clock.offset');
    local c = cb ~= 0 and safemem.u32(cb) or nil;
    local t = c ~= nil and c ~= 0 and safemem.u32(c + 0x0C) or nil;
    local o = co ~= 0 and safemem.u32(co) or nil;
    return (t ~= nil and o ~= nil) and (t + o) % 0x100000000 or nil;
end

function V.from_item(id, ext, bag, slot)
    local item = AshitaCore:GetResourceManager():GetItemById(id);
    if (item == nil) then
        return nil;
    end
    local function f(k) local ok, x = pcall(function () return item[k]; end); return ok and type(x) == 'number' and x or 0; end
    local kind, flags = f('Type'), f('Flags');
    local v = { id = id, from_game = false };
    v.name = name(item, id);
    v.name_color = worn(bag or 0, slot) and V.GREEN or V.WHITE;
    v.badges = badges(flags, ext ~= nil and ext:byte(1) or 0, bag, tooltip_handler());
    v.typeline = typeline(kind, f('Skill'), f('Slots'), f('Races'), f('SuperiorLevel'));
    local d = nil;
    pcall(function () d = item.Description[1]; end);
    v.desc = (type(d) == 'string' and d ~= '') and { d } or {};
    v.wrapped = false;
    v.right = {};
    if (kind == 4 or kind == 5) then
        local skill = f('Skill');
        if (not (kind == 4 and (skill == 0xFF or skill == 48))) then
            v.lv = lvline(f('Level'), f('Jobs'));
        end
        -- A charged item's line (0x13BBF0).
        local max = f('MaxCharges');
        if (max > 0) then
            local left, t = max, f('CastDelay');
            local clock = now();
            if (ext ~= nil and ext:byte(1) == 1 and clock ~= nil) then
                left = ext:byte(2);
                local function rem(o)
                    local x = (safemem.le32(ext, o) - clock) % 0x100000000;
                    return x >= 0x80000000 and 0 or x;
                end
                t = rem(4);
                if (worn(bag or 0, slot)) then
                    t = math.max(t, rem(8));
                else
                    t = math.max(t, f('CastDelay'));
                end
                if (left == 0) then
                    t = 0;
                end
            end
            local text = max == 0xFF and '\226\136\158' or ('%d/%d'):format(left, max);
            text = ('<%s %s/[%s, %s]>'):format(text, hms(t), hms(f('RecastDelay')), hms(f('CastDelay')));
            v.right[#v.right + 1] = { text = text, color = left == 0 and 0x80804020 or (left == max and 0x80407090 or V.WHITE),
                                      utf8 = true };
        end
        local il = f('ItemLevel');
        if (il > 0) then
            v.right[#v.right + 1] = { text = ('<Item Level:%d>'):format(il), color = V.WHITE, utf8 = true };
        end
    end
    return v;
end

--[[
* Where the game's own record of a carried item is: { ext (its extra data, 0x1C bytes), slot, bag,
* rec }, from the record (a container item, 0x2C bytes: +2 its slot, +0x10 its extra data); its bag
* from its place among the bags (gd + 0x9868 + bag * 0xDEC, bags 0..17; the game's 0x0EB4F0). nil
* for no record.
--]]
function V.where(rec, out)
    local b = rec ~= nil and rec >= 0x10000 and safemem.read(rec, 0x2C) or nil;
    if (b == nil) then
        return nil;
    end
    out = out or {};
    out.rec, out.ext, out.slot, out.bag = rec, b:sub(0x11, 0x2C), b:byte(3), nil;
    local gd = safemem.u32(sigs.get('party.gd'));
    if (gd ~= nil and gd ~= 0) then
        local off = rec - (gd + 0x9868);
        local bag = math.floor(off / 0xDEC);
        if (off >= 0 and bag <= 17) then
            out.bag = bag;
        end
    end
    return out;
end

-- The game's colour (0x80 a channel is full) as ImGui's.
function V.color(c)
    local function ch(x) return math.min(1, x * 2 / 255); end
    return { ch(math.floor(c / 65536) % 256), ch(math.floor(c / 256) % 256), ch(c % 256), 1 };
end

return V;
