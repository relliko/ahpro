--[[
* facelift - ui/icons (from allrecipes)
* Items' own icons, from the game's data (the resource manager's bitmap), as textures ImGui can
* draw. Each is made once and kept; one that can't be made gives nil.
--]]

local ffi = require('ffi');

local icons = {
    cache  = { },   -- [item id] = texture
    failed = { },   -- [item id] = true when it couldn't be made
};

local function make(id)
    local d3d = require('d3d8');
    local C = ffi.C;
    local item = AshitaCore:GetResourceManager():GetItemById(id);
    if (item == nil or item.Bitmap == nil or (item.ImageSize or 0) <= 0) then
        return nil;
    end
    local ptr = ffi.new('IDirect3DTexture8*[1]');
    if (C.D3DXCreateTextureFromFileInMemoryEx(d3d.get_device(), item.Bitmap, item.ImageSize, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
            C.D3DFMT_A8R8G8B8, C.D3DPOOL_MANAGED, C.D3DX_DEFAULT, C.D3DX_DEFAULT, 0xFF000000, nil, nil, ptr) ~= C.S_OK) then
        return nil;
    end
    return d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
end

--[[
* An item's icon in the game's colour c (0x80RRGGBB, 0x80 is as drawn), as the game draws a linkshell
* item's (core/lsitem): each pixel times the colour twice over (the game's 2x), kept to full. A copy of
* the icon with that done to its pixels (ImGui can't draw brighter than a picture).
--]]
local function make_tinted(id, c)
    local tex = make(id);
    if (tex == nil) then
        return nil;
    end
    local ok, desc = tex:GetLevelDesc(0);
    if (ok ~= ffi.C.S_OK or desc == nil) then
        return nil;
    end
    local res, lock = tex:LockRect(0, nil, 0);
    if (res ~= ffi.C.S_OK or lock == nil) then
        return nil;
    end
    local fr = math.floor(c / 65536) % 256 * 2 / 255;
    local fg = math.floor(c / 256) % 256 * 2 / 255;
    local fb = c % 256 * 2 / 255;
    local bits = ffi.cast('uint8_t*', lock.pBits);
    for y = 0, desc.Height - 1 do
        local row = bits + y * lock.Pitch;
        for x = 0, desc.Width - 1 do
            local p = row + x * 4; -- (A8R8G8B8: B, G, R, A in memory)
            p[0] = math.min(255, math.floor(p[0] * fb + 0.5));
            p[1] = math.min(255, math.floor(p[1] * fg + 0.5));
            p[2] = math.min(255, math.floor(p[2] * fr + 0.5));
        end
    end
    tex:UnlockRect(0);
    return tex;
end

local tint_cache, tint_failed = {}, {};

-- An item's icon in the game's colour c (a linkshell item's: core/lsitem) as ImGui takes it, or nil.
function icons.tinted(id, c)
    local key = id * 0x100000000 + c;
    local tex = tint_cache[key];
    if (tex == nil and not tint_failed[key]) then
        local ok, t = pcall(make_tinted, id, c);
        if (ok and t ~= nil) then
            tex = t;
            tint_cache[key] = t;
        else
            tint_failed[key] = true;
        end
    end
    return tex ~= nil and tonumber(ffi.cast('uint32_t', tex)) or nil;
end

-- A status's icon (the game's own picture, from the resource manager), the same way.
local function make_status(id)
    local d3d = require('d3d8');
    local C = ffi.C;
    local s = AshitaCore:GetResourceManager():GetStatusIconByIndex(id);
    if (s == nil or s.Bitmap == nil) then
        return nil;
    end
    local ptr = ffi.new('IDirect3DTexture8*[1]');
    if (C.D3DXCreateTextureFromFileInMemoryEx(d3d.get_device(), s.Bitmap, -1, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
            C.D3DFMT_A8R8G8B8, C.D3DPOOL_MANAGED, C.D3DX_DEFAULT, C.D3DX_DEFAULT, 0xFF000000, nil, nil, ptr) ~= C.S_OK) then
        return nil;
    end
    return d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
end

local status_cache, status_failed = {}, {};

-- A status's icon as ImGui takes it, or nil.
function icons.status(id)
    local tex = status_cache[id];
    if (tex == nil and not status_failed[id]) then
        local ok, t = pcall(make_status, id);
        if (ok and t ~= nil) then
            tex = t;
            status_cache[id] = t;
        else
            status_failed[id] = true;
        end
    end
    return tex ~= nil and tonumber(ffi.cast('uint32_t', tex)) or nil;
end

-- Whether a status's icon data says its timer isn't shown (the game shows no time and no pulse for
-- it); false when that can't be told.
local hides = {};
function icons.status_hides_timer(id)
    local v = hides[id];
    if (v == nil) then
        local ok, h = pcall(function ()
            local s = AshitaCore:GetResourceManager():GetStatusIconByIndex(id);
            return s ~= nil and s.HideTimer;
        end);
        v = ok and type(h) == 'number' and h == 0xFF;
        hides[id] = v;
    end
    return v;
end

-- An item's icon as ImGui takes it, or nil.
function icons.get(id)
    local tex = icons.cache[id];
    if (tex == nil and not icons.failed[id]) then
        local ok, t = pcall(make, id);
        if (ok and t ~= nil) then
            tex = t;
            icons.cache[id] = t;
        else
            icons.failed[id] = true;
        end
    end
    return tex ~= nil and tonumber(ffi.cast('uint32_t', tex)) or nil;
end

return icons;
