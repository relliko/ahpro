--[[
* facelift - ui/gametex: the game's own textures, drawn by ImGui as they are (Ashita's ImGui takes a
* D3D8 texture pointer, as facelift's own textures are passed). A pointer read from the game's memory
* is used only when it really is a texture: its vtable is the one facelift's own texture has (a 4x4
* one made for that, once). Checked again every second per pointer.
--]]

local ffi       = require('ffi');
local safemem   = require('core.safemem');
local datfont   = require('core.datfont');
local nameicons = require('ui.nameicons');

local gt = {
    why = nil, -- why game textures can't be used, once that's known
};

local keep, vt, tried = nil, nil, false;
local seen = {}; -- [pointer] = { ok, when }

local function ref()
    if (not tried) then
        tried = true;
        local ok, t = pcall(function ()
            local px = {};
            for i = 0, 15 do
                px[i] = { 255, 255, 255, 0 };
            end
            return nameicons.make(datfont.dds(4, 4, px));
        end);
        if (ok and t ~= nil) then
            keep = t;
            local a = tonumber(ffi.cast('uint32_t', t));
            vt = a ~= nil and a ~= 0 and safemem.u32(a) or nil;
        end
        if (vt == nil or vt == 0) then
            vt = nil;
            gt.why = 'facelift\'s own texture couldn\'t be made';
        end
    end
    return vt;
end

-- Whether ptr is a texture ImGui can draw.
function gt.valid(ptr)
    if (ptr == nil or ptr == 0) then
        return false;
    end
    local s = seen[ptr];
    local t = os.clock();
    if (s ~= nil and t - s[2] < 1) then
        return s[1];
    end
    local v = ref();
    local ok = v ~= nil and safemem.u32(ptr) == v;
    if (s == nil) then
        s = {};
        seen[ptr] = s;
    end
    s[1], s[2] = ok, t;
    return ok;
end

function gt.unload()
    keep, vt, tried, seen = nil, nil, false, {};
end

return gt;
