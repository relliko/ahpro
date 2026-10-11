--[[
* facelift - ui/nameicons: the game's name icons (core/datfont: the linkshell pearl, party, GM,
* mentor...) as one ImGui texture, made the first time names are drawn with icons on. If it can't
* be made, names show without icons and nameicons.why says why.
--]]

local ffi = require('ffi');
local datfont = require('core.datfont');

local ni = {
    why = nil, -- why there are no icons, once that's known
};

local tried = false;
local keep = nil;            -- the texture (released when dropped)
local tex, uv, cells = nil, nil, nil;
local pearl_src = nil;       -- the pearl's own texels (core/datfont)
local pearls, npearls = {}, 0; -- [colour] = { big, small } textures (false: couldn't be made), and how many
local MAX_PEARLS = 32;

-- A texture from a DDS file in memory, on the game's device; nil if it can't be made.
function ni.make(dds)
    local d3d = require('d3d8');
    local C = ffi.C;
    local data = ffi.new('uint8_t[?]', #dds);
    ffi.copy(data, dds, #dds);
    local ptr = ffi.new('IDirect3DTexture8*[1]');
    -- Its own size, one level, no filtering and no colour key.
    if (C.D3DXCreateTextureFromFileInMemoryEx(d3d.get_device(), data, #dds, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
            C.D3DFMT_A8R8G8B8, C.D3DPOOL_MANAGED, 1, 1, 0, nil, nil, ptr) ~= C.S_OK) then
        return nil;
    end
    return d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
end

local function load()
    tried = true;
    local f, why = datfont.from_game();
    if (f == nil) then
        ni.why = why;
        return;
    end
    local ok, t = pcall(ni.make, f.dds);
    if (not ok or t == nil) then
        ni.why = 'the texture couldn\'t be made';
        return;
    end
    keep = t;
    tex = tonumber(ffi.cast('uint32_t', t));
    cells, uv = f.cells, {};
    pearl_src = f.pearl;
    for code, c in pairs(f.cells) do
        -- Half a texel in from the cell's edges, so its neighbours don't bleed in.
        uv[code] = { { (c.u + 0.5) / f.w, (c.v + 0.5) / f.h }, { (c.u + c.w - 0.5) / f.w, (c.v + c.h - 0.5) / f.h } };
    end
    ni.why = nil;
end

-- The texture (as ImGui takes it), each glyph's { uv_min, uv_max } and cell (core/datfont), or nil.
function ni.get()
    if (not tried) then
        local ok, err = pcall(load);
        if (not ok) then
            ni.why = tostring(err);
        end
    end
    return tex, uv, cells;
end

--[[
* The linkshell pearl in a shell's colour (ls: 0x00BBGGRR), as the game draws it: its picture times
* twice the colour, each channel clipped (MODULATE2X), so its bright parts burn to the colour; alpha
* doubled. Made once per colour, at its own size and at half (a box filter), as the game draws small
* icons from smaller copies. The texture for an icon s px across, or nil.
--]]
local function pearl_px(c, r, g, b)
    local out = {};
    for i = 0, c.w * c.h - 1 do
        local p = c.px[i] or { 0, 0, 0, 0 };
        out[i] = { math.min(255, 2 * p[1] * r / 255), math.min(255, 2 * p[2] * g / 255), math.min(255, 2 * p[3] * b / 255), p[4] };
    end
    return out;
end

local function half(px, w, h)
    local out = {};
    local hw, hh = math.floor(w / 2), math.floor(h / 2);
    for y = 0, hh - 1 do
        for x = 0, hw - 1 do
            local r, g, b, a = 0, 0, 0, 0;
            for j = 0, 1 do
                for i = 0, 1 do
                    local p = px[(y * 2 + j) * w + x * 2 + i];
                    r, g, b, a = r + p[1] * p[4], g + p[2] * p[4], b + p[3] * p[4], a + p[4];
                end
            end
            out[y * hw + x] = a > 0 and { r / a, g / a, b / a, a / 4 } or { 0, 0, 0, 0 };
        end
    end
    return out, hw, hh;
end

function ni.pearl(ls, s)
    if (pearl_src == nil or ls == nil) then
        return nil;
    end
    local e = pearls[ls];
    if (e == nil) then
        if (npearls >= MAX_PEARLS) then
            return nil;
        end
        e = false;
        pcall(function ()
            local px = pearl_px(pearl_src, ls % 256, math.floor(ls / 256) % 256, math.floor(ls / 65536) % 256);
            local small, hw, hh = half(px, pearl_src.w, pearl_src.h);
            local big_t = ni.make(datfont.dds(pearl_src.w, pearl_src.h, px));
            local small_t = ni.make(datfont.dds(hw, hh, small));
            if (big_t ~= nil and small_t ~= nil) then
                e = { big = big_t, small = small_t, big_id = tonumber(ffi.cast('uint32_t', big_t)), small_id = tonumber(ffi.cast('uint32_t', small_t)) };
            end
        end);
        pearls[ls], npearls = e, npearls + 1;
    end
    if (not e) then
        return nil;
    end
    return s <= pearl_src.w * 0.7 and e.small_id or e.big_id;
end

-- On unload: the textures go.
function ni.unload()
    tex, uv, cells, keep, tried, pearl_src = nil, nil, nil, nil, false, nil;
    pearls, npearls = {}, 0;
end

return ni;
