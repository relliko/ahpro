--[[
* facelift - layout/edit
* Layout edit mode (/facelift edit): every window that's up can be dragged, and right-clicked for
* where it sits (over the game's window, fixed on screen, or next to another facelift window), its
* text size, its options and a reset. Changes are kept per character (layout/store) and saved when
* edit mode ends. Clicks don't reach the game while editing.
--]]

local imgui = require('ui.gui');
local theme = require('ui.theme');
local place = require('layout.place');
local store = require('layout.store');

local edit = {
    on = false,
};

-- Starts or ends edit mode.
function edit.set(on, windows)
    edit.on = on;
    for _, w in ipairs(windows) do
        w.grabbed = false;
    end
    if (not on) then
        store.save();
    end
end

-- Whether the runtime should leave the window where it is (the player is dragging it).
function edit.held(w)
    return (edit.on or w.spec.movable == true or w.spec.movable == 'shift') and w.grabbed == true;
end

local SCREEN_FIELDS = { dx = false, dy = false, target = false, at = false };
local MENU_FIELDS = { from = false, x = false, y = false, px = false, py = false, target = false, at = false, dx = false, dy = false };

local function anchor_menu(w, L, env, windows)
    local o = store.get(w.id) or {};
    local from = o.from;
    if (imgui.RadioButton('Over the game\'s window', from == nil)) then
        store.set(w.id, MENU_FIELDS);
    end
    if (imgui.RadioButton('Fixed on screen', from == 'screen')) then
        local f = place.offset({ from = 'screen' }, nil, env, w.rect.x, w.rect.y);
        for k, v in pairs(SCREEN_FIELDS) do f[k] = v; end
        f.from = 'screen';
        store.set(w.id, f);
    end
    for _, t in ipairs(windows) do
        if (t ~= w) then
            if (imgui.RadioButton('Next to ' .. t.name .. '##' .. t.id, from == 'window' and o.target == t.id)) then
                store.set(w.id, { from = 'window', target = t.id, at = 'tr', dx = 8, dy = 0, x = false, y = false, px = false, py = false });
            end
        end
    end
    if (from == 'window') then
        for _, c in ipairs({ { 'tr', 'right' }, { 'bl', 'below' }, { 'tl', 'over' } }) do
            imgui.SameLine();
            if (imgui.RadioButton(c[2] .. '##at', (o.at or 'tr') == c[1])) then
                store.set(w.id, { at = c[1], dx = c[1] == 'tr' and 8 or 0, dy = c[1] == 'bl' and 8 or 0 });
            end
        end
    end
end

local fs_buf, opt_buf = { 1 }, { 0 };

--[[
* In a window, while editing: its name, dragging, and the right-click menu. L: its layout now; a, own:
* what it's placed from and its own game rect (see layout/place); env: its env (fs is the window's);
* pl: where its layout puts it; windows: all of them.
--]]
--[[
* Dragging a window: held from a click on it until the button comes up; dropped somewhere else, that's
* kept (the same kind of anchor). Windows that aren't held follow their anchors as they move. free: a
* movable window outside edit mode (spec.movable): held only from its empty space (its rows and buttons
* stay the game's), and kept at once.
--]]
function edit.drag(w, L, a, own, env, pl, free)
    if (imgui.IsMouseClicked(0) and imgui.IsWindowHovered(ImGuiHoveredFlags_RootAndChildWindows)
            and not (free and imgui.IsAnyItemHovered())) then
        w.grabbed = true;
    end
    if (w.grabbed and imgui.IsMouseReleased(0)) then
        w.grabbed = false;
        if (math.abs(w.rect.x - pl.x) > 1 or math.abs(w.rect.y - pl.y) > 1) then
            local f = place.offset(L, a, env, w.rect.x, w.rect.y, own, w.rect.w, w.rect.h);
            if (f ~= nil) then
                if (L.docked) then
                    -- Moved off where it docks: that spot gets its own offset; where it goes when
                    -- it doesn't dock is left alone.
                    local docks = {};
                    local cur = store.get(w.id);
                    for k, v in pairs(cur ~= nil and cur.docks or {}) do
                        docks[k] = v;
                    end
                    docks[L.target .. '/' .. L.at] = { dx = f.dx, dy = f.dy };
                    f = { docks = docks };
                end
                store.set(w.id, f);
                if (free) then
                    store.save();
                end
            end
        end
    end
end

function edit.chrome(w, L, a, own, env, pl, windows)
    imgui.TextColored(theme.ACCENT, w.name);
    imgui.SameLine();
    imgui.TextColored(theme.DIM, 'drag, right-click');
    edit.drag(w, L, a, own, env, pl, false);

    if (imgui.BeginPopupContextWindow('##facelift_edit')) then
        imgui.TextColored(theme.ACCENT, w.name);
        imgui.Separator();
        anchor_menu(w, L, env, windows);
        imgui.Separator();
        local o = store.get(w.id) or {};
        fs_buf[1] = o.fs or 1;
        if (imgui.SliderFloat('Text size##facelift_fs', fs_buf, 0.5, 3, '%.2f')) then
            store.set(w.id, { fs = fs_buf[1] });
        end
        for name, opt in pairs(w.spec.options or {}) do
            opt_buf[1] = w.opt(name) or opt.default or opt.min;
            if (imgui.SliderInt(opt.label .. '##facelift_opt_' .. name, opt_buf, opt.min, opt.max)) then
                local opts = {};
                for k, v in pairs(o.opts or {}) do opts[k] = v; end
                opts[name] = opt_buf[1];
                store.set(w.id, { opts = opts });
            end
        end
        imgui.Separator();
        if (imgui.Button('Reset##facelift_reset')) then
            store.reset(w.id);
        end
        imgui.EndPopup();
    end
end

return edit;
