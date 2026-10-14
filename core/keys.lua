--[[
* facelift - core/keys: keeping a key facelift has already acted on from reaching the game while
* it's still held. Enter in a facelift field confirms there and takes the field out of typing, and
* from the next frame the game could read the same, still held Enter as its own (answering its
* yes/no, or confirming the box past facelift's second press). So until ImGui sees Enter come up
* (it gets the window's real key messages), the game's DirectInput read of Enter and keypad Enter is
* cleared. Should ImGui miss the key coming up, after 10 seconds the game's own read showing both up
* ends it too.
*
* Tab, while a gil or quantity box steps through its picks with it (keys.hold_tab every frame it
* does): the game's read of Tab is cleared, so it doesn't also cycle the game's target; a moment
* after the box stops asking, the game has it again.
*
* M, for the map window (keys.map: set each frame by facelift.lua, whether M may act now): pressed
* with no Shift, Ctrl or Alt, counted in keys.map_presses (facelift.lua takes them in its frame) and
* cleared from the game's read until it's let go. Escape the same way (keys.esc, keys.esc_presses), while
* the map window is up and nothing else is: it closes the window.
*
* It only ever clears these keys, never presses one.
--]]

local ffi = require('ffi');

local keys = {};

local DIK_RETURN, DIK_NUMPADENTER, DIK_TAB, DIK_M, DIK_ESCAPE = 0x1C, 0x9C, 0x0F, 0x32, 0x01;
local MODS = { 0x2A, 0x36, 0x1D, 0x9D, 0x38, 0xB8 }; -- (Shift, Ctrl, Alt: left and right)
keys.map = false;      -- M may act now (no menu focused, the chat line closed, no ImGui field typing)
keys.map_presses = 0;  -- presses not yet taken
local m_down, m_held = false, false;
keys.esc = false;      -- Escape closes the map window now (it's up, nothing else is: facelift.lua)
keys.esc_presses = 0;
local esc_down, esc_held = false, false;
local active, until_t = false, 0;
local tab_until = 0;

-- Keeps Tab from the game for this frame and a moment after (asked every frame it's wanted).
function keys.hold_tab()
    tab_until = os.clock() + 0.2;
end

-- Keeps Enter from the game until it's let go.
function keys.swallow_enter()
    active, until_t = true, os.clock() + 10;
end

-- Each frame (d3d_present): stop once ImGui sees Enter up.
function keys.frame(imgui)
    if (active and not imgui.IsKeyDown(ImGuiKey_Enter) and not imgui.IsKeyDown(ImGuiKey_KeypadEnter)) then
        active = false;
    end
end

-- The game's keyboard read (the key_state event): Enter cleared while swallowing.
function keys.key_state(e)
    if (os.clock() < tab_until) then
        ffi.cast('uint8_t*', e.data_raw)[DIK_TAB] = 0;
    end
    local kb = ffi.cast('uint8_t*', e.data_raw);
    local down = kb[DIK_M] >= 0x80;
    if (down and not m_down and keys.map) then
        local mod = false;
        for _, k in ipairs(MODS) do
            mod = mod or kb[k] >= 0x80;
        end
        if (not mod) then
            keys.map_presses = keys.map_presses + 1;
            m_held = true;
        end
    end
    m_down = down;
    if (m_held) then
        if (down) then
            kb[DIK_M] = 0;
        else
            m_held = false;
        end
    end
    -- Escape, while the map window is the only thing up: it closes the window, and the game doesn't
    -- see that press (it would clear your target).
    local edown = kb[DIK_ESCAPE] >= 0x80;
    if (edown and not esc_down and keys.esc) then
        keys.esc_presses = keys.esc_presses + 1;
        esc_held = true;
    end
    esc_down = edown;
    if (esc_held) then
        if (edown) then
            kb[DIK_ESCAPE] = 0;
        else
            esc_held = false;
        end
    end
    if (not active) then
        return;
    end
    local buf = ffi.cast('uint8_t*', e.data_raw);
    if (os.clock() > until_t and buf[DIK_RETURN] < 0x80 and buf[DIK_NUMPADENTER] < 0x80) then
        active = false; -- ImGui missed it coming up; the game's read shows it up
        return;
    end
    buf[DIK_RETURN], buf[DIK_NUMPADENTER] = 0, 0;
end

-- facelift stopped or unloading: the game gets Enter again.
function keys.reset()
    active, tab_until = false, 0;
    keys.map, keys.map_presses, m_held = false, 0, false;
    keys.esc, keys.esc_presses, esc_held = false, 0, false;
end

function keys.active()
    return active;
end

return keys;
