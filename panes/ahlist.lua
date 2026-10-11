--[[
* facelift - panes/ahlist: the auction list (part 'list', adapters/auclist) with the info of the item
* under the mouse, or else the selected one, below it. That item is left in w.item for the windows
* that follow this one (the prices window). The mouse counts only while the list or its item menu
* has focus: over the price box, it stays on the item being bid on.
--]]

local imgui    = require('ui.gui');
local list     = require('ui.list');
local iteminfo = require('ui.iteminfo');
local tooltip  = require('ui.tooltip');
local keys     = require('core.keys');

local P = {};

function P.new(spec)
    return { list = list.new('facelift_auc') };
end

function P.draw(st, w, env)
    local p = w.part.list;
    local m = p.model;
    local fs, ww = env.fs, w.place.w;
    -- Rows shown: the player's choice, else as many as the game shows (10 if that looks wrong).
    local rows = w.opt('rows');
    local page = (rows ~= nil and rows > 0) and rows or (m.page > 1 and m.page or 10);
    local clicked, hovered, enter = list.draw(st.list, m.list, m.index, page, p.handler * 65536 + m.count, fs, ww);
    if (enter) then
        keys.swallow_enter();
    end
    local at = list.index_of(m.list, hovered);
    if (clicked ~= nil) then
        w.req('list', 'choose', clicked);
    elseif (p.focused and at ~= nil and at ~= st.hover and at ~= m.index) then
        w.req('list', 'point', at); -- the game's cursor follows the mouse (not while its item menu is up)
    end
    st.hover = at;
    local follow = env.focus == 'auclist' or env.focus == 'auc3';
    local show = (follow and hovered) or m.list[m.index + 1];
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
