--[[
* facelift - ui/gui
* ImGui as facelift's UI code uses it: the same functions as require('imgui'), but every push and
* begin is remembered, so after an error part-way through a window gui.unwind(mark) closes exactly
* what was left open and ImGui's stacks stay balanced.
--]]

local imgui = require('imgui');

local gui = setmetatable({}, { __index = imgui });

local stack, n = {}, 0;

local function push(closer)
    n = n + 1;
    stack[n] = closer;
end

local function pop(k)
    n = math.max(0, n - (k or 1));
end

local pop_color = function () imgui.PopStyleColor(1); end;
local pop_var   = function () imgui.PopStyleVar(1); end;

function gui.Begin(...) push(imgui.End); return imgui.Begin(...); end
function gui.End() pop(); imgui.End(); end
function gui.BeginChild(...) push(imgui.EndChild); return imgui.BeginChild(...); end
function gui.EndChild() pop(); imgui.EndChild(); end
function gui.BeginGroup() push(imgui.EndGroup); imgui.BeginGroup(); end
function gui.Indent(w) push(function () imgui.Unindent(w); end); imgui.Indent(w); end
function gui.Unindent(w) pop(); imgui.Unindent(w); end
function gui.EndGroup() pop(); imgui.EndGroup(); end
function gui.PushStyleColor(...) push(pop_color); imgui.PushStyleColor(...); end
function gui.PopStyleColor(k) pop(k); imgui.PopStyleColor(k or 1); end
function gui.PushStyleVar(...) push(pop_var); imgui.PushStyleVar(...); end
function gui.PopStyleVar(k) pop(k); imgui.PopStyleVar(k or 1); end
function gui.PushFont(...) push(imgui.PopFont); imgui.PushFont(...); end
function gui.PopFont() pop(); imgui.PopFont(); end
function gui.PushItemWidth(...) push(imgui.PopItemWidth); imgui.PushItemWidth(...); end
function gui.PopItemWidth() pop(); imgui.PopItemWidth(); end
function gui.PushTextWrapPos(...) push(imgui.PopTextWrapPos); imgui.PushTextWrapPos(...); end
function gui.PopTextWrapPos() pop(); imgui.PopTextWrapPos(); end
function gui.PushID(...) push(imgui.PopID); imgui.PushID(...); end
function gui.PopID() pop(); imgui.PopID(); end
function gui.BeginPopupContextWindow(...)
    local open = imgui.BeginPopupContextWindow(...);
    if (open) then push(imgui.EndPopup); end
    return open;
end
function gui.BeginPopup(...)
    local open = imgui.BeginPopup(...);
    if (open) then push(imgui.EndPopup); end
    return open;
end
function gui.EndPopup() pop(); imgui.EndPopup(); end
function gui.BeginTabBar(...)
    local open = imgui.BeginTabBar(...);
    if (open) then push(imgui.EndTabBar); end
    return open;
end
function gui.EndTabBar() pop(); imgui.EndTabBar(); end
function gui.BeginTabItem(...)
    local open = imgui.BeginTabItem(...);
    if (open) then push(imgui.EndTabItem); end
    return open;
end
function gui.EndTabItem() pop(); imgui.EndTabItem(); end
function gui.BeginCombo(...)
    local open = imgui.BeginCombo(...);
    if (open) then push(imgui.EndCombo); end
    return open;
end
function gui.EndCombo() pop(); imgui.EndCombo(); end

-- Hovered, unless facelift is in key mode (ui/pointer): then what the mouse rests on doesn't count.
local pointer = require('ui.pointer');
function gui.IsItemHovered(...)
    if (pointer.keys) then
        return false;
    end
    return imgui.IsItemHovered(...);
end

-- Where the stack is now, for gui.unwind.
function gui.mark()
    return n;
end

-- Closes everything opened since mark, newest first.
function gui.unwind(mark)
    while (n > mark) do
        local f = stack[n];
        n = n - 1;
        pcall(f);
    end
end

return gui;
