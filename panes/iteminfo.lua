--[[
* facelift - panes/iteminfo: the item tooltip (ui/iteminfo, as every window draws an item), for the
* game's item, or for the row a facelift list offers (ui/tooltip) when the spec says it takes offers.
--]]

local imgui    = require('ui.gui');
local iteminfo = require('ui.iteminfo');
local tooltip  = require('ui.tooltip');

local P = {};

function P.new(spec)
    return {};
end

-- The item to show: the row a facelift list offers, else the game's (and where it's from: the game's
-- tooltip itself, line for line).
local function item(w, env)
    local p = w.part.tip;
    local m = p.model;
    if (w.spec.offers) then
        local id, stack, src = tooltip.take(env.frame);
        if (id ~= nil) then
            if (id == m.id and src ~= nil and src.rec ~= nil and src.rec + 0x10 == m.ext) then
                return id, stack, { handler = p.handler }; -- (the very item the game's tooltip is on)
            end
            return id, stack, src;
        end
    end
    return m.id, false, { handler = p.handler };
end

function P.visible(st, w)
    return (item(w, w.env)) ~= 0;
end

function P.draw(st, w, env)
    local fs = env.fs;
    local id, stack, src = item(w, env);
    iteminfo(id, stack, fs, imgui.GetCursorPosX() + w.place.w - 24 * fs, src);
end

return P;
