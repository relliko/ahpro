--[[
* facelift - ui/gameicons: the element icons the game puts in its text (core/gametext; fire, ice,
* wind, earth, lightning, water, light, dark) as one ImGui texture, made from the game's own images
* (core/datfont) the first time a text needs one. If it can't be made, gameicons.why says why and
* the text shows the element's name instead.
--]]

local ffi = require('ffi');
local datfont = require('core.datfont');
local nameicons = require('ui.nameicons');

local gi = {
    why = nil,
};

local tried = false;
local keep = nil; -- the texture (released when dropped)
local tex = nil;
local uv = {};    -- [1..8] = { uv_min, uv_max }

local function load()
    tried = true;
    local f, why = datfont.elements_from_game();
    if (f == nil) then
        gi.why = why;
        return;
    end
    local ok, t = pcall(nameicons.make, f.dds);
    if (not ok or t == nil) then
        gi.why = 'the texture couldn\'t be made';
        return;
    end
    keep = t;
    tex = tonumber(ffi.cast('uint32_t', t));
    for k = 1, f.w / 16 do
        -- Half a texel in, so the next icon doesn't bleed in.
        uv[k] = { { ((k - 1) * 16 + 0.5) / f.w, 0.5 / f.h }, { (k * 16 - 0.5) / f.w, 15.5 / f.h } };
    end
    gi.why = nil;
end

-- The texture (as ImGui takes it) and each icon's { uv_min, uv_max }, or nil.
function gi.get()
    if (not tried) then
        local ok, err = pcall(load);
        if (not ok) then
            gi.why = tostring(err);
        end
    end
    return tex, uv;
end

function gi.unload()
    keep, tex, tried, uv = nil, nil, false, {};
end

return gi;
