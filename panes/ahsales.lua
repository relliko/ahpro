--[[
* facelift - panes/ahsales: Sales Status (part 'list', adapters/aucsales): your listings with their
* prices and where they stand, and the info of the one under the mouse (else the selected one)
* below. A click on one that's on sale is the game's Enter on it (its small menu opens); on any
* other it just moves the game's cursor there. The item shown is left in w.item for the prices
* window.
--]]

local imgui    = require('ui.gui');
local theme    = require('ui.theme');
local listings = require('ui.listings');
local iteminfo = require('ui.iteminfo');
local tooltip  = require('ui.tooltip');

local P = {};

function P.new(spec)
    return { rows = listings.new('facelift_sales') };
end

function P.draw(st, w, env)
    local p = w.part.list;
    local m = p.model;
    local fs = env.fs;
    local cw = math.max(0, w.place.w - 24 * fs);
    imgui.TextColored(theme.ACCENT, ('%d'):fmt(#m.list));
    imgui.SameLine(0, 4 * fs);
    imgui.TextColored(theme.DIM, #m.list == 1 and 'item up for auction' or 'items up for auction');
    imgui.Separator();
    local clicked, hovered = listings.draw(st.rows, m.list, m.index, m.version, fs, cw);
    if (clicked ~= nil) then
        local r = m.list[clicked + 1];
        w.req('list', r ~= nil and r.status == 'sale' and 'choose' or 'point', clicked);
    end
    local follow = env.focus == 'auclist';
    local show = (follow and hovered) or m.list[m.index + 1];
    w.item = show;
    if (show ~= nil) then
        if (tooltip.covered()) then
            tooltip.offer(show.id, show.stack, env.frame); -- the tooltip window shows it
        else
            imgui.Separator();
            iteminfo(show.id, show.stack, fs, imgui.GetCursorPosX() + cw);
        end
    end
end

return P;
