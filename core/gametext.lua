--[[
* facelift - core/gametext: the game's strings (item names and descriptions...) as ImGui text. They
* are Shift-JIS with the game's own additions, and ImGui wants UTF-8: raw, a character outside ASCII
* shows as '?' and swallows the ones after it. The game's additions:
*   0x85 row   Windows-1252 0x80-0xBF at 0x8540-0x8580, 0xC0-0xFF at 0x859F-0x85DE (accents)
*   0xEF 0x1F-0x26  the element icons: fire, ice, wind, earth, lightning, water, light, dark
*   0xEF 0x27/0x28  the auto-translate marks; 0xEF 0x29-0x2E On and Off (Ashita's chat.symbols)
* gametext.runs(s): the string as runs, kept per string: a UTF-8 string, a number (an element icon,
* 1-8, in the order above) or false (a line break); runs.icons counts the icons and runs.text is
* the whole string as UTF-8 (icons by name). Nothing here touches the game.
--]]

local ffi = require('ffi');

local gametext = {};

gametext.ELEMENTS = { 'Fire', 'Ice', 'Wind', 'Earth', 'Lightning', 'Water', 'Light', 'Dark' };

pcall(ffi.cdef, [[
    int __stdcall MultiByteToWideChar(uint32_t cp, uint32_t flags, const char* s, int n, uint16_t* w, int wn);
    int __stdcall WideCharToMultiByte(uint32_t cp, uint32_t flags, const uint16_t* w, int wn, char* s, int n,
        const char* def, int* used);
]]);

local function utf8(cp)
    if (cp < 0x80) then
        return string.char(cp);
    elseif (cp < 0x800) then
        return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64);
    end
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64);
end

-- Windows-1252's 0x80-0x9F (0xA0-0xFF are Latin-1, the same numbers as Unicode).
local CP1252 = {
    [0x80] = 0x20AC, [0x82] = 0x201A, [0x83] = 0x0192, [0x84] = 0x201E, [0x85] = 0x2026, [0x86] = 0x2020,
    [0x87] = 0x2021, [0x88] = 0x02C6, [0x89] = 0x2030, [0x8A] = 0x0160, [0x8B] = 0x2039, [0x8C] = 0x0152,
    [0x8E] = 0x017D, [0x91] = 0x2018, [0x92] = 0x2019, [0x93] = 0x201C, [0x94] = 0x201D, [0x95] = 0x2022,
    [0x96] = 0x2013, [0x97] = 0x2014, [0x98] = 0x02DC, [0x99] = 0x2122, [0x9A] = 0x0161, [0x9B] = 0x203A,
    [0x9C] = 0x0153, [0x9E] = 0x017E, [0x9F] = 0x0178,
};

-- The game's row 0x85 as UTF-8, or nil.
local function row85(t)
    local b = nil;
    if (t >= 0x40 and t <= 0x7E) then
        b = t + 0x40;
    elseif (t == 0x80) then
        b = 0xBF;
    elseif (t >= 0x9F and t <= 0xDE) then
        b = t + 0x21;
    end
    if (b == nil) then
        return nil;
    end
    local cp = b >= 0xA0 and b or CP1252[b];
    return cp and utf8(cp) or nil;
end

-- Shift-JIS bytes as UTF-8 (Windows' code page 932), or '?' each. Full-width ASCII (the game's help
-- text writes 'Auction：') and the full-width space come out as plain ASCII, which every font has.
local wbuf, obuf = nil, nil;
local function sjis(bytes)
    local ok, r = pcall(function ()
        wbuf = wbuf or ffi.new('uint16_t[8]');
        obuf = obuf or ffi.new('char[32]');
        local n = ffi.C.MultiByteToWideChar(932, 0, bytes, #bytes, wbuf, 8);
        if (n <= 0) then
            return nil;
        end
        if (n == 1 and wbuf[0] >= 0xFF01 and wbuf[0] <= 0xFF5E) then
            return string.char(wbuf[0] - 0xFEE0);
        elseif (n == 1 and wbuf[0] == 0x3000) then
            return ' ';
        end
        local m = ffi.C.WideCharToMultiByte(65001, 0, wbuf, n, obuf, 32, nil, nil);
        return m > 0 and ffi.string(obuf, m) or nil;
    end);
    return ok and r or '?';
end

local function lead(b)
    return (b >= 0x81 and b <= 0x9F) or (b >= 0xE0 and b <= 0xEF) or (b >= 0xFA and b <= 0xFC);
end

local SPECIAL = { [0x27] = '{', [0x28] = '}', [0x29] = 'On', [0x2A] = 'Off', [0x2B] = 'On', [0x2C] = 'Off',
                  [0x2D] = 'On', [0x2E] = 'Off' };

local function parse(s)
    local runs, buf, all = { icons = 0 }, {}, {};
    local function flush()
        if (#buf > 0) then
            local t = table.concat(buf);
            runs[#runs + 1] = t;
            all[#all + 1] = t;
            buf = {};
        end
    end
    local i, n = 1, #s;
    while (i <= n) do
        local b = s:byte(i);
        if (b == 0x0A or b == 0x07) then
            flush();
            runs[#runs + 1] = false;
            all[#all + 1] = '\n';
            i = i + 1;
        elseif (b == 0x1E or b == 0x1F) then
            i = i + 2;                                  -- a colour code and its argument
        elseif (b < 0x20) then
            i = i + 1;
        elseif (b < 0x80) then
            buf[#buf + 1] = string.char(b);
            i = i + 1;
        elseif (lead(b) and i < n) then
            local t = s:byte(i + 1);
            if (b == 0xEF and t >= 0x1F and t <= 0x26) then
                flush();
                runs[#runs + 1] = t - 0x1E;
                runs.icons = runs.icons + 1;
                all[#all + 1] = gametext.ELEMENTS[t - 0x1E];
            elseif (b == 0xEF) then
                buf[#buf + 1] = SPECIAL[t] or '';
            elseif (b == 0x85) then
                buf[#buf + 1] = row85(t) or '';
            else
                buf[#buf + 1] = sjis(s:sub(i, i + 1));
            end
            i = i + 2;
        else
            buf[#buf + 1] = sjis(s:sub(i, i));          -- half-width katakana
            i = i + 1;
        end
    end
    flush();
    runs.text = table.concat(all);
    return runs;
end

local cache, ncache = {}, 0;

function gametext.runs(s)
    s = s or '';
    local r = cache[s];
    if (r == nil) then
        if (ncache >= 500) then
            cache, ncache = {}, 0;
        end
        r = parse(s);
        cache[s], ncache = r, ncache + 1;
    end
    return r;
end

-- The string as UTF-8, icons by name.
function gametext.text(s)
    return gametext.runs(s).text;
end

-- An item's name (item: its resource, or nil) as UTF-8, or 'item <id>'. Every window names items
-- with this.
function gametext.name(item, id)
    local n = item ~= nil and item.Name ~= nil and item.Name[1] or nil;
    return n ~= nil and gametext.text(n) or ('item %d'):format(id or 0);
end

return gametext;
