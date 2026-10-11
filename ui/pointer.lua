--[[
* facelift - ui/pointer: keys or mouse, whichever was used last. A key that moves a game cursor (the
* arrows and keypad arrows, page keys, Home / End, Enter, Escape, Tab) puts facelift in key mode: what
* the mouse happens to rest on is ignored (ui/gui's IsItemHovered says no, and the theme draws no hover
* highlight), so what a window shows follows the game's cursor, as the game does. Only a click (or the
* wheel) ends it, as in the game: moving the mouse alone doesn't.
*
* pointer.frame() once a frame, before the windows; pointer.keys: in key mode.
--]]

local imgui = require('imgui');

local pointer = { keys = false };

local KEYS = nil; -- (ImGui's key enums, read once they exist)

function pointer.frame()
    if (KEYS == nil) then
        KEYS = {};
        for _, n in ipairs({ 'UpArrow', 'DownArrow', 'LeftArrow', 'RightArrow', 'PageUp', 'PageDown', 'Home', 'End',
                             'Enter', 'KeypadEnter', 'Escape', 'Tab', 'Keypad2', 'Keypad4', 'Keypad6', 'Keypad8' }) do
            local k = rawget(_G, 'ImGuiKey_' .. n);
            if (k ~= nil) then
                KEYS[#KEYS + 1] = k;
            end
        end
    end
    local io = imgui.GetIO();
    if (imgui.IsMouseClicked(0) or imgui.IsMouseClicked(1) or (io.MouseWheel or 0) ~= 0) then
        pointer.keys = false;
    end
    for _, k in ipairs(KEYS) do
        if (imgui.IsKeyPressed(k, true)) then
            pointer.keys = true;
            break;
        end
    end
end

return pointer;
