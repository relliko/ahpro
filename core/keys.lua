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
* It only ever clears these keys, never presses one.
--]]

local ffi = require('ffi');

local keys = {};

local DIK_RETURN, DIK_NUMPADENTER, DIK_TAB = 0x1C, 0x9C, 0x0F;
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
end

function keys.active()
    return active;
end

return keys;
