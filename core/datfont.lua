--[[
* facelift - core/datfont: the pictures the game puts in front of names (the linkshell pearl, party,
* GM, mentor...), read from the game's own data file, for ui/nameicons to make a texture of. Only
* reads files; nothing here touches the game.
*
* They're glyphs 0x8E-0xB1 of the game's font 'font    fontshp ' (a type-0x31 resource in the
* menu DAT: file 0x9A76, ROM/119/51.DAT on the English client). Its records hold each glyph's
* texture and cell (u, v, w, h in texels; its quad in font units). The icons' texture 'menu
* ustatshd' (type 0x20, same DAT) is 256x256 DXT3 with the game's alpha: about 0x80 is opaque (the
* game draws them with MODULATE4X alpha, an alpha test and MODULATE2X colour). Here that's made what
* ImGui's plain blending needs: under 0x33 clear (the game's test), else doubled. The linkshell
* pearl (0x92), which the game tints with the shell's colour at double brightness, is doubled in
* colour too, so tinting it with the colour looks the same.
--]]

local ffi = require('ffi');

local band, rshift = bit.band, bit.rshift;

local datfont = {
    FILE_ID = 0x9A76,         -- the menu DAT (the English language table's first file)
    FALLBACK = 'ROM/119/51.DAT',
    FIRST = 0x8E, LAST = 0xB1, -- the icon glyphs
    PEARL = 0x92,
    TEXTURE = 'menu    ustatshd',
    FONT = 'font    fontshp ',
};

local function u16(s, o)
    local a, b = s:byte(o + 1, o + 2);
    return a + b * 256;
end
local function s16(s, o)
    local v = u16(s, o);
    return v >= 0x8000 and v - 0x10000 or v;
end
local function u32(s, o)
    local a, b, c, d = s:byte(o + 1, o + 4);
    return a + b * 256 + c * 65536 + d * 16777216;
end

local function read(path)
    local f = io.open(path, 'rb');
    if (f == nil) then
        return nil;
    end
    local s = f:read('*a');
    f:close();
    return s;
end

-- The game's folder (where FFXiMain.dll is), ending in a slash, or nil.
function datfont.game_dir()
    local ok, dir = pcall(function ()
        pcall(ffi.cdef, [[
            void* __stdcall GetModuleHandleA(const char* name);
            uint32_t __stdcall GetModuleFileNameA(void* module, char* out, uint32_t size);
        ]]);
        local m = ffi.C.GetModuleHandleA('FFXiMain.dll');
        if (m == nil) then
            return nil;
        end
        local buf = ffi.new('char[520]');
        local n = ffi.C.GetModuleFileNameA(m, buf, 520);
        if (n == 0 or n >= 520) then
            return nil;
        end
        return (ffi.string(buf, n):gsub('[^\\/]*$', ''));
    end);
    return ok and dir or nil;
end

-- A file id's path in the main ROM, through VTABLE.DAT and FTABLE.DAT (an entry is folder * 128 +
-- file), or nil.
function datfont.rom_path(dir, id)
    local v, f = read(dir .. 'VTABLE.DAT'), read(dir .. 'FTABLE.DAT');
    if (v == nil or f == nil or #v <= id or #f < id * 2 + 2 or v:byte(id + 1) ~= 1) then
        return nil;
    end
    local e = u16(f, id * 2);
    return ('%sROM/%d/%d.DAT'):format(dir, rshift(e, 7), band(e, 0x7F));
end

--[[
* The resource for which fn(offset, type, size) is true, as its offset and size, or nil. Each starts
* with 16 bytes: a name (4), then a dword with the type in its low 7 bits and the size / 16 in the
* next 19.
--]]
local function find(s, fn)
    local o = 0;
    while (o + 16 <= #s) do
        local v = u32(s, o + 4);
        local typ, size = band(v, 0x7F), band(rshift(v, 7), 0x7FFFF) * 16;
        if (size < 16 or o + size > #s) then
            return nil;
        end
        if (fn(o, typ, size)) then
            return o, size;
        end
        o = o + size;
    end
    return nil;
end

-- The icon glyphs' cells from the font: [code] = { u, v, w, h, x0, y0, x1, y1 (quad, font units) },
-- part 0 of each record (as DrawNameText draws them).
local function cells(s)
    local o, size = find(s, function (o, typ)
        return typ == 0x31 and s:sub(o + 17, o + 32) == datfont.FONT;
    end);
    if (o == nil) then
        return nil, 'no font';
    end
    local stop = o + size;
    local p = o + 32;
    local ntex = s:byte(p + 1);
    p = p + 1 + 16 * ntex;
    if (p + 2 > stop) then
        return nil, 'font too short';
    end
    local nrec = u16(s, p);
    p = p + 2;
    local out = {};
    for r = 0, nrec - 1 do
        if (p + 1 > stop) then
            return nil, 'font too short';
        end
        local nparts = s:byte(p + 1);
        p = p + 1;
        for k = 0, nparts - 1 do
            if (p + 61 > stop) then
                return nil, 'font too short';
            end
            local code = 0x20 + r;
            if (k == 0 and code >= datfont.FIRST and code <= datfont.LAST) then
                local x0, y0, x1, y1 = 1e9, 1e9, -1e9, -1e9;
                for c = 0, 3 do
                    local x, y = s16(s, p + c * 4), s16(s, p + c * 4 + 2);
                    x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y);
                end
                out[code] = { u = s16(s, p + 20), v = s16(s, p + 22), w = s16(s, p + 16), h = s16(s, p + 18),
                              x0 = x0, y0 = y0, x1 = x1, y1 = y1, tex = s:sub(p + 46, p + 61):lower() };
            end
            p = p + 61;
        end
    end
    for code = datfont.FIRST, datfont.LAST do
        local c = out[code];
        if (c == nil or c.tex ~= datfont.TEXTURE) then
            return nil, ('glyph %02X not on the icon texture'):format(code);
        end
    end
    return out;
end

-- The DDS header (128 bytes) of a w x h 32-bit BGRA image, written bytewise into buf.
local function header(buf, w, h)
    local function put(o, v)
        buf[o], buf[o + 1], buf[o + 2], buf[o + 3] = v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256,
            math.floor(v / 16777216) % 256;
    end
    for i = 0, 127 do
        buf[i] = 0;
    end
    buf[0], buf[1], buf[2], buf[3] = 0x44, 0x44, 0x53, 0x20;   -- 'DDS '
    put(4, 124);                                               -- the header's size
    put(8, 0x100F);                                            -- caps, height, width, pitch, pixel format
    put(12, h);
    put(16, w);
    put(20, w * 4);
    put(76, 32);                                               -- the pixel format's size
    put(80, 0x41);                                             -- RGB with alpha
    put(88, 32);
    put(92, 0x00FF0000);
    put(96, 0x0000FF00);
    put(100, 0x000000FF);
    put(104, 0xFF000000);
    put(108, 0x1000);                                          -- a texture
end

-- A DDS file (a string) of a w x h image from px[0 .. w*h-1] = { r, g, b, a } (0-255).
function datfont.dds(w, h, px)
    local buf = ffi.new('uint8_t[?]', 128 + w * h * 4);
    header(buf, w, h);
    for i = 0, w * h - 1 do
        local p = px[i];
        local at = 128 + i * 4;
        buf[at], buf[at + 1], buf[at + 2], buf[at + 3] = p[3], p[2], p[1], p[4];
    end
    return ffi.string(buf, 128 + w * h * 4);
end

--[[
* The icons from the menu DAT at path: { dds (a DDS file in memory, a string), w, h, cells, pearl },
* or nil and why. pearl: the linkshell pearl's own texels { w, h, px[0 ..] = { r, g, b, a } }, its
* colour as stored (not doubled) and its alpha as shown, for ui/nameicons to colour per shell.
--]]
function datfont.load(path)
    local s = read(path);
    if (s == nil) then
        return nil, 'can\'t read ' .. path;
    end
    local glyphs, why = cells(s);
    if (glyphs == nil) then
        return nil, why;
    end
    local o = find(s, function (o, typ)
        return typ == 0x20 and s:sub(o + 18, o + 33):lower() == datfont.TEXTURE;
    end);
    if (o == nil) then
        return nil, 'no icon texture';
    end
    local p = o + 16;
    local w, h = u32(s, p + 21), u32(s, p + 25);
    local q = p + 17 + 40;
    if (s:byte(p + 1) ~= 0xA1 or s:sub(q + 1, q + 4) ~= '3TXD' or w < 4 or h < 4 or w > 1024 or h > 1024
            or w % 4 ~= 0 or h % 4 ~= 0 or u32(s, q + 4) ~= w * h or q + 12 + w * h > #s) then
        return nil, 'icon texture isn\'t 32-bit DXT3';
    end
    local src = ffi.cast('const uint8_t*', s) + q + 12;
    local buf = ffi.new('uint8_t[?]', 128 + w * h * 4);
    header(buf, w, h);
    local pearl = glyphs[datfont.PEARL];
    local praw = pearl ~= nil and { w = pearl.w, h = pearl.h, px = {} } or nil;
    local col = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } };
    local function rgb565(c, t)
        local r, g, b = rshift(c, 11), band(rshift(c, 5), 63), band(c, 31);
        t[1], t[2], t[3] = r * 8 + rshift(r, 2), g * 4 + rshift(g, 4), b * 8 + rshift(b, 2);
    end
    local blk = 0;
    for by = 0, h - 4, 4 do
        for bx = 0, w - 4, 4 do
            local b = src + blk * 16;
            blk = blk + 1;
            rgb565(b[8] + b[9] * 256, col[1]);
            rgb565(b[10] + b[11] * 256, col[2]);
            for i = 1, 3 do
                col[3][i] = math.floor((2 * col[1][i] + col[2][i]) / 3);
                col[4][i] = math.floor((col[1][i] + 2 * col[2][i]) / 3);
            end
            local idx = b[12] + b[13] * 256 + b[14] * 65536 + b[15] * 16777216;
            for i = 0, 15 do
                local x, y = bx + band(i, 3), by + rshift(i, 2);
                local n = band(rshift(b[rshift(i, 1)], band(i, 1) * 4), 15);           -- 4-bit alpha
                local c = col[band(rshift(idx, i * 2), 3) + 1];
                local k = 2;
                if (pearl ~= nil and x >= pearl.u and x < pearl.u + pearl.w and y >= pearl.v and y < pearl.v + pearl.h) then
                    k = 4; -- doubled (and k / 2 below)
                    praw.px[(y - pearl.v) * pearl.w + x - pearl.u] = { c[1], c[2], c[3], n <= 2 and 0 or math.min(255, n * 34) };
                end
                local at = 128 + (y * w + x) * 4;
                buf[at] = math.min(255, c[3] * k / 2);
                buf[at + 1] = math.min(255, c[2] * k / 2);
                buf[at + 2] = math.min(255, c[1] * k / 2);
                buf[at + 3] = n <= 2 and 0 or math.min(255, n * 34);
            end
        end
    end
    return { dds = ffi.string(buf, 128 + w * h * 4), w = w, h = h, cells = glyphs, pearl = praw };
end

-- This game's menu DAT (found through FTABLE, else the English client's path), or nil and why.
local function menu_dat()
    local dir = datfont.game_dir();
    if (dir == nil) then
        return nil, 'the game\'s folder wasn\'t found';
    end
    return datfont.rom_path(dir, datfont.FILE_ID) or (dir .. datfont.FALLBACK);
end

-- The icons from this game's own files: datfont.load on its menu DAT, or nil and why.
function datfont.from_game()
    local path, why = menu_dat();
    if (path == nil) then
        return nil, why;
    end
    return datfont.load(path);
end

--[[
* The element icons the game puts in text (its characters 0xEF 0x1F-0x26: fire, ice, wind, earth,
* lightning, water, light, dark; core/gametext): 'font    el...' (16x16 DXT3 in the menu DAT) side by
* side in one image, { dds, w, h }, or nil and why. Drawn like the font's glyphs: colour as stored,
* alpha doubled (the game's 0x80 is opaque).
--]]
datfont.ELEMENTS = { 'font    elfire  ', 'font    elice   ', 'font    elwind  ', 'font    elearth ',
                     'font    elthunde', 'font    elwater ', 'font    elholy  ', 'font    eldark  ' };

function datfont.elements(path)
    local s = read(path);
    if (s == nil) then
        return nil, 'can\'t read ' .. path;
    end
    local W, H = 16 * #datfont.ELEMENTS, 16;
    local px = {};
    for k, name in ipairs(datfont.ELEMENTS) do
        local o = find(s, function (o, typ)
            return typ == 0x20 and s:sub(o + 18, o + 33):lower() == name;
        end);
        if (o == nil) then
            return nil, 'no ' .. name;
        end
        local p = o + 16;
        local q = p + 17 + 40;
        if (s:byte(p + 1) ~= 0xA1 or s:sub(q + 1, q + 4) ~= '3TXD' or u32(s, p + 21) ~= 16 or u32(s, p + 25) ~= 16
                or q + 12 + 256 > #s) then
            return nil, name .. ' isn\'t a 16x16 DXT3 image';
        end
        local blk = 0;
        for by = 0, 12, 4 do
            for bx = 0, 12, 4 do
                local b = q + 12 + blk * 16;
                blk = blk + 1;
                local cols = {};
                for i, c in ipairs({ u16(s, b + 8), u16(s, b + 10) }) do
                    local r, g, bl = rshift(c, 11), band(rshift(c, 5), 63), band(c, 31);
                    cols[i] = { r * 8 + rshift(r, 2), g * 4 + rshift(g, 4), bl * 8 + rshift(bl, 2) };
                end
                cols[3], cols[4] = {}, {};
                for i = 1, 3 do
                    cols[3][i] = math.floor((2 * cols[1][i] + cols[2][i]) / 3);
                    cols[4][i] = math.floor((cols[1][i] + 2 * cols[2][i]) / 3);
                end
                local idx = u32(s, b + 12);
                for i = 0, 15 do
                    local x, y = bx + band(i, 3), by + rshift(i, 2);
                    local a = band(rshift(s:byte(b + 1 + rshift(i, 1)), band(i, 1) * 4), 15) * 17;
                    local c = cols[band(rshift(idx, i * 2), 3) + 1];
                    px[y * W + (k - 1) * 16 + x] = { c[1], c[2], c[3], math.min(255, a * 2) };
                end
            end
        end
    end
    return { dds = datfont.dds(W, H, px), w = W, h = H };
end

-- The element icons from this game's own files, or nil and why.
function datfont.elements_from_game()
    local path, why = menu_dat();
    if (path == nil) then
        return nil, why;
    end
    return datfont.elements(path);
end

return datfont;
