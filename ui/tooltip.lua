--[[
* facelift - ui/tooltip: the item tooltip as one thing for every window. The game has one item
* tooltip (menu iteminfo) that every screen fills; facelift's tooltip window (windows/iteminfo) is
* drawn over it, so items look the same everywhere. A facelift list offers the row under the mouse
* (or its cursor's) with tooltip.offer, and the tooltip shows that instead of the game's item while
* it's offered. A list draws an item itself only where the game opened no tooltip at all
* (tooltip.covered() false).
--]]

local menus = require('core.menus');

local tt = {};

local offer = { id = 0, stack = false, frame = -10 };

-- A list's item for the tooltip this frame (frame: the pane's env.frame).
function tt.offer(id, stack, frame, src)
    offer.id, offer.stack, offer.frame, offer.src = id or 0, stack == true, frame or 0, src;
end

-- The item offered this frame or the last, as id, stack and where it is (ui/iteminfo's src: its
-- extra data, bag and slot), or nil.
function tt.take(frame)
    if (offer.id ~= 0 and offer.frame >= (frame or 0) - 1) then
        return offer.id, offer.stack, offer.src;
    end
    return nil;
end

-- Whether the game has its tooltip open now (then facelift's tooltip window, or the game's own when
-- that's off, shows the item).
function tt.covered()
    return menus.find('iteminfo') ~= nil;
end

return tt;
