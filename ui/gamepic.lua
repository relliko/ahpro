--[[
* facelift - ui/gamepic: a game picture (a sprite read by adapters/menuopts.picture: its quads on the
* game's textures, ui/gametex) drawn with ImGui: each quad at (x, y) plus its place in the sprite,
* times k (one turned in its texture with its four corners' coordinates); the label's glyphs in tint,
* their dark copy (shadow) as a shade, anything else as it is.
--]]

local imgui   = require('ui.gui');
local theme   = require('ui.theme');
local gametex = require('ui.gametex');

local G = {};

local SHADE = { 0, 0, 0, 0.55 };
local a, b, uv0, uv1 = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };
-- A turned part's four corners and their texture coordinates (AddImageQuad).
local p1, p2, p3, p4 = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };
local t1, t2, t3, t4 = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };
local shade_u32, shade_v = nil, -1;

-- Draws picture L on dl at (x, y) (screen px) at scale k; tint (ImGui U32) for its glyphs, col (ImGui
-- U32) for the rest (the colour the game draws the sprite in; default as it is). False when none of it
-- could be drawn.
function G.draw(dl, L, x, y, k, tint, col)
    if (L == nil) then
        return false;
    end
    if (shade_v ~= theme.version) then
        shade_u32, shade_v = imgui.GetColorU32(SHADE), theme.version;
    end
    local drawn = false;
    for _, q in ipairs(L.quads) do
        if (gametex.valid(q.tex)) then
            a[1], a[2] = x + q.x0 * k, y + q.y0 * k;
            b[1], b[2] = x + q.x1 * k, y + q.y1 * k;
            uv0[1], uv0[2], uv1[1], uv1[2] = q.u0, q.v0, q.u1, q.v1;
            local c = col or 0xFFFFFFFF;
            if (q.shadow) then
                c = shade_u32;
            elseif (q.glyph) then
                c = tint or 0xFFFFFFFF;
            end
            local r = q.rot;
            if (r ~= nil) then
                -- Turned in its texture: each corner its own coordinates.
                p1[1], p1[2], p2[1], p2[2] = a[1], a[2], b[1], a[2];
                p3[1], p3[2], p4[1], p4[2] = b[1], b[2], a[1], b[2];
                t1[1], t1[2], t2[1], t2[2], t3[1], t3[2], t4[1], t4[2] = r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8];
                dl:AddImageQuad(q.tex, p1, p2, p3, p4, t1, t2, t3, t4, c);
            else
                dl:AddImage(q.tex, a, b, uv0, uv1, c);
            end
            drawn = true;
        end
    end
    return drawn;
end

--[[
* A sprite of one of the game's sprite sets as a picture (read as the option menus' are), or nil: the
* set's object is word k at the sets' global (sig: 'sprites.ui' at 0x1C8C30, 'icons.sets' at 0x220CF0),
* sprite n is word n of the table the object points at.
--]]
local cache = {};
function G.sprite(sig, set, n)
    local key = ('%s/%d/%d'):format(sig, set, n);
    local P = cache[key];
    if (P == nil) then
        local safemem, sigs = require('core.safemem'), require('core.sigs');
        local g = sigs.get(sig);
        local so = g ~= 0 and safemem.u32(g + set * 4) or nil;
        local tb = so ~= nil and so ~= 0 and safemem.u32(so) or nil;
        local sp = tb ~= nil and tb ~= 0 and safemem.u32(tb + n * 4) or nil;
        P = sp ~= nil and sp ~= 0 and require('adapters.menuopts').picture(sp) or false;
        if (P) then
            cache[key] = P;
        end
    end
    return P or nil;
end

-- The picture's extent in its sprite (x0, y0, x1, y1, sprite px), or nil when it has none.
function G.bounds(L)
    if (L == nil or #L.quads == 0) then
        return nil;
    end
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge;
    for _, q in ipairs(L.quads) do
        x0, y0 = math.min(x0, q.x0), math.min(y0, q.y0);
        x1, y1 = math.max(x1, q.x1), math.max(y1, q.y1);
    end
    return x0, y0, x1, y1;
end

return G;
