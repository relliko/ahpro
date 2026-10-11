--[[
* facelift - core/hide
* Hiding the game's own window under a new one. The manager draws menus layer by layer, 0 to 8,
* each menu on the layer in its +0x60 byte (0x15F6A0); a menu on another layer is never drawn.
* The only other reader is the list insert when a menu opens (0x15DB10): a signed compare puts
* layers >= 5 ahead of new menus, which would keep focus on the hidden one. 0xFF is -1 there, so
* the hidden menu keeps its place and new menus (the item menu over the list) still get focus.
* Nothing else about it changes: it stays open, focused and working.
*
* Except closing: the game finishes a menu's close only while drawing it (0x117520 counts down the
* close and marks the menu closed, and only the draw calls it), so a covered menu that's asked to
* close would stay in the list for good. A closing menu is never covered, and one that was is put
* back at the end of the frame, so the game can finish (and show its own close).
*
* hide.cover(obj, owner) every frame a new window covers the menu; hide.end_frame() puts back any
* that weren't covered this frame (if still open), hide.uncover(owner) gives back an owner's menus
* this frame (a window that failed), and hide.restore_all() puts back all of them.
--]]

local safemem = require('core.safemem');
local menus   = require('core.menus');

local hide = {};

local HIDDEN_LAYER = 0xFF;
local hidden = {};  -- [obj] = its own layer
local covered = {}; -- [obj] = the frame it was last covered in
local owners = {};  -- [obj] = who covered it
local frame = 0;

function hide.cover(obj, owner)
    if (obj == nil or obj == 0) then
        return;
    end
    -- +0x60 the layer, +0x6E closing.
    local cur = safemem.read(obj + 0x60, 0x0F);
    if (cur == nil or cur:byte(0x0F) ~= 0) then
        return;
    end
    covered[obj], owners[obj] = frame, owner;
    if (hidden[obj] == nil) then
        if (cur:byte(1) == HIDDEN_LAYER) then
            return; -- hidden by someone else; theirs to put back
        end
        hidden[obj] = cur:byte(1);
    end
    if (cur:byte(1) ~= HIDDEN_LAYER) then
        ashita.memory.write_uint8(obj + 0x60, HIDDEN_LAYER);
    end
end

function hide.uncover(owner)
    for obj, o in pairs(owners) do
        if (o == owner) then
            covered[obj], owners[obj] = nil, nil;
        end
    end
end

local function put_back(all)
    for obj, layer in pairs(hidden) do
        if (all or covered[obj] ~= frame) then
            -- Only while it's still in the game's list (closing counts): a closed menu's memory may
            -- be gone, and opening sets the layer anew.
            if (menus.listed(obj)) then
                local cur = safemem.read(obj + 0x60, 1);
                if (cur ~= nil and cur:byte(1) == HIDDEN_LAYER) then
                    ashita.memory.write_uint8(obj + 0x60, layer);
                end
            end
            hidden[obj], covered[obj], owners[obj] = nil, nil, nil;
        end
    end
end

function hide.end_frame()
    put_back(false);
    frame = frame + 1;
end

function hide.restore_all()
    put_back(true);
    frame = frame + 1;
end

-- Whether facelift has this menu hidden.
function hide.is_hidden(obj)
    return hidden[obj] ~= nil;
end

return hide;
