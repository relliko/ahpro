--[[
* facelift - panes/sellpick: the Sell flow's item picker (part 'list', adapters/sellpick) as a
* filterable list: items the game won't let you sell are faint and can't be picked; the info of the
* item under the mouse (else the selected one) below. The item is left in w.item for the prices
* window, so what it has sold for shows before you pick it.
--]]

local imgui    = require('ui.gui');
local list     = require('ui.list');
local iteminfo = require('ui.iteminfo');
local tooltip  = require('ui.tooltip');
local keys     = require('core.keys');

local P = {};

function P.new(spec)
    return { list = list.new('facelift_sell') };
end

function P.draw(st, w, env)
    local p = w.part.list;
    local m = p.model;
    local fs, ww = env.fs, w.place.w;
    local page = m.page > 1 and m.page or 10;
    local clicked, hovered, enter = list.draw(st.list, m.list, m.index, page, p.handler * 65536 + m.count, fs, ww);
    if (enter) then
        keys.swallow_enter();
    end
    if (clicked ~= nil) then
        local r = m.list[clicked + 1];
        w.req('list', (r ~= nil and not r.faint) and 'choose' or 'point', clicked);
    end
    local show = hovered or m.list[m.index + 1];
    w.item = show;
    if (show ~= nil and show.id ~= 0) then
        if (tooltip.covered()) then
            tooltip.offer(show.id, show.stack, env.frame); -- the tooltip window shows it
        else
            imgui.Separator();
            iteminfo(show.id, show.stack, fs, imgui.GetCursorPosX() + ww - 24 * fs);
        end
    end
end

return P;
