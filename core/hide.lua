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
* And menus the game opens again every frame (the region map's points boxes, from the map's Update):
* opening a menu that's open copies its layer back from the game's static menu table (0x15E950: row
* +0x29 to menu +0x60), after facelift's frame and before the game's draw, so the menu's own layer
* can't keep it hidden. Covered with its name, the menu's row in that table is hidden too, and put
* back with the menu.
*
* hide.cover(obj, owner[, name]) every frame a new window covers the menu (name: the game opens it
* again every frame); hide.end_frame() puts back any that weren't covered this frame (if still open),
* hide.uncover(owner) gives back an owner's menus this frame (a window that failed), and
* hide.restore_all() puts back all of them.
--]]

local safemem = require('core.safemem');
local menus   = require('core.menus');
local sigs    = require('core.sigs');

local hide = {};

local HIDDEN_LAYER = 0xFF;
local hidden = {};  -- [obj] = its own layer
local covered = {}; -- [obj] = the frame it was last covered in
local owners = {};  -- [obj] = who covered it
local frame = 0;

-- The static menu table: rows of 0x2C, { char name[32]; T** slot; u32 flags; u8; u8 layer; u16 mask },
-- ended by an empty name (client-notes 'UI, packets, chat, commands...': the static menu table).
local ROW, ROWS, LAYER = 0x2C, 400, 0x29;
local rows = {};   -- [name] = its row's layer byte (false: not found)
local row_of = {}; -- [obj] = the row's layer byte hidden with it
local row_own = {}; -- [layer byte] = the row's own layer

local function row_layer(name)
    local at = rows[name];
    if (at == nil) then
        at = false;
        local base, col = sigs.get('menu.statics'), sigs.get('menu.static_layer');
        if (base ~= 0 and col == base + LAYER) then
            local want = ('menu    %-8s'):format(name);
            for i = 0, ROWS - 1 do
                local s = safemem.read(base + i * ROW, 16);
                if (s == nil or s:byte(1) == 0) then
                    break;
                end
                if (s == want) then
                    at = col + i * ROW;
                    break;
                end
            end
        end
        rows[name] = at;
    end
    return at;
end

function hide.cover(obj, owner, name)
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
    if (name ~= nil and row_of[obj] == nil) then
        local at = row_layer(name);
        local s = at and safemem.read(at, 1) or nil;
        if (s ~= nil and s:byte(1) ~= HIDDEN_LAYER) then
            row_own[at], row_of[obj] = s:byte(1), at;
            ashita.memory.write_uint8(at, HIDDEN_LAYER);
        end
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
            -- Its row in the static table (always there): back too, or the game's next opening of
            -- it would be hidden.
            local at = row_of[obj];
            if (at ~= nil) then
                local cur = safemem.read(at, 1);
                if (cur ~= nil and cur:byte(1) == HIDDEN_LAYER) then
                    ashita.memory.write_uint8(at, row_own[at]);
                end
                row_own[at], row_of[obj] = nil, nil;
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
