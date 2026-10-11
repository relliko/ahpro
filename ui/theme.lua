--[[
* facelift - ui/theme
* One look for every window, in one of four themes:
*   glass  dark smoked glass: translucent dark panels with a faint top sheen and a thin light
*          edge, soft white highlights, and one cool accent (the first look, and the default)
*   clean  scouter's clean: neutral grey panels, warm text, an amber accent
*   guild  allrecipes' guild: warm leather and parchment, gold for what's picked
*   phoenix  phoenixfishtrack's: deep ember-black panels, near-white text, its royal red accent
* theme.set(name, opacity) switches; the colour tables below (theme.ACCENT...) are changed in place,
* so code that keeps one sees the new colour. A colour made from one at another alpha:
* theme.derive(key, alpha), kept up to date the same way.
*
* A part of the interface can have its own theme (theme.AREAS: 'ah', the auction house's windows,
* settings look.ah_theme): the runtime switches to it around those windows (theme.begin_area /
* theme.end_area) and back to the rest's.
--]]

local imgui = require('ui.gui');
local pointer = require('ui.pointer');
local fonts = require('ui.fonts');

local theme = {
    name = 'glass',
    version = 0, -- goes up each time the theme or opacity changes
};

theme.NAMES = { { 'glass', 'Smoked glass' }, { 'clean', 'Clean' }, { 'guild', 'Guild' }, { 'phoenix', 'Phoenix' } };

-- bg: panels (bg_a: their alpha, solid_a: windows nothing shows through, popup_a); light: the colour
-- of faint overlays (edges, hovered controls); title(_active): the config window's title bar;
-- round: window corners (inner: everything else); sheen: the glass along the top edge.
local THEMES = {
    glass = {
        bg = { 0.05, 0.06, 0.09 }, bg_a = 0.76, solid_a = 0.94, popup_a = 0.92,
        accent = { 0.56, 0.78, 1.00 }, text = { 0.93, 0.94, 0.97 }, dim = { 0.58, 0.61, 0.68 },
        faint = { 0.40, 0.42, 0.48 }, good = { 0.55, 0.88, 0.62 }, warn = { 0.96, 0.74, 0.40 },
        light = { 1.00, 1.00, 1.00 }, title = { 0.08, 0.10, 0.15 }, title_active = { 0.11, 0.15, 0.23 },
        round = 10, inner = 6, sheen = true,
    },
    clean = {
        bg = { 0.094, 0.106, 0.125 }, bg_a = 0.86, solid_a = 0.96, popup_a = 0.94,
        accent = { 0.937, 0.624, 0.153 }, text = { 0.945, 0.937, 0.910 }, dim = { 0.667, 0.659, 0.627 },
        faint = { 0.431, 0.427, 0.408 }, good = { 0.431, 0.804, 0.471 }, warn = { 0.886, 0.294, 0.290 },
        light = { 0.85, 0.84, 0.80 }, title = { 0.173, 0.173, 0.165 }, title_active = { 0.267, 0.267, 0.255 },
        round = 8, inner = 4, sheen = false,
    },
    guild = { -- (allrecipes' style.lua guild, its 0-255 colours as these)
        bg = { 0.141, 0.110, 0.082 }, bg_a = 0.88, solid_a = 0.96, popup_a = 0.95,
        accent = { 0.910, 0.706, 0.298 }, text = { 0.949, 0.898, 0.800 }, dim = { 0.698, 0.620, 0.494 },
        faint = { 0.486, 0.424, 0.361 }, good = { 0.612, 0.800, 0.408 }, warn = { 0.941, 0.792, 0.361 },
        light = { 0.95, 0.86, 0.68 }, title = { 0.220, 0.173, 0.125 }, title_active = { 0.306, 0.243, 0.169 },
        round = 8, inner = 4, sheen = false,
    },
    phoenix = { -- (phoenixfishtrack's COLOR: abyss, text, muted, faint, royal, peach, success, gold, surface1/2)
        bg = { 0.094, 0.055, 0.055 }, bg_a = 0.90, solid_a = 0.96, popup_a = 0.95,
        accent = { 0.773, 0.318, 0.318 }, text = { 1.000, 0.973, 0.973 }, dim = { 0.541, 0.420, 0.420 },
        faint = { 0.353, 0.271, 0.271 }, good = { 0.388, 0.729, 0.541 }, warn = { 0.773, 0.631, 0.192 },
        light = { 0.824, 0.671, 0.671 }, title = { 0.161, 0.110, 0.110 }, title_active = { 0.196, 0.122, 0.122 },
        round = 8, inner = 4, sheen = false,
    },
};

local P = THEMES.glass; -- the palette in use

--[[
* Corners (settings look.corners): 'square' (none), 'slight' (half the theme's) or 'round' (the
* theme's own). Every rounded thing facelift draws goes through theme.r(px) (its radius as the
* corners say) or the style below.
--]]
theme.CORNERS = { { 'square', 'Square' }, { 'slight', 'Slightly rounded' }, { 'round', 'Round' } };
local CK = { square = 0, slight = 0.5, round = 1 };
local ck = 0;
function theme.corners(mode)
    ck = CK[mode] or 0;
    theme.version = theme.version + 1;
end
function theme.r(px)
    return (px or 0) * ck;
end

theme.ACCENT = { 0, 0, 0, 1 };
theme.TEXT   = { 0, 0, 0, 1 };
theme.DIM    = { 0, 0, 0, 1 };
theme.FAINT  = { 0, 0, 0, 1 };
theme.GOOD   = { 0, 0, 0, 1 };
theme.WARN   = { 0, 0, 0, 1 };
theme.LIGHT  = { 0, 0, 0, 1 }; -- faint overlays' colour (white in the glass)
theme.BG     = { 0, 0, 0, 1 };
theme.BLACK  = { 0, 0, 0, 1 };

-- The palette's colour for each of those keys.
local KEYS = { ACCENT = 'accent', TEXT = 'text', DIM = 'dim', FAINT = 'faint', GOOD = 'good', WARN = 'warn',
               LIGHT = 'light', BG = 'bg' };

local derived = {}; -- { table, key, alpha }

-- A colour from theme[key] (ACCENT, LIGHT, BG, BLACK...) at alpha, kept up to date with the theme.
function theme.derive(key, alpha)
    local t = { 0, 0, 0, alpha };
    derived[#derived + 1] = { t, key, alpha };
    local c = theme[key];
    t[1], t[2], t[3] = c[1], c[2], c[3];
    return t;
end

-- ImGui colours as { ImGuiCol, colour table }; the tables are derived (or theme's own), so they
-- follow the theme.
local SOLID = theme.derive('BG', 0.94);
local WINDOW_BG = theme.derive('BG', 0.76);
local BORDER = theme.derive('LIGHT', 0.12);
local NONE = { 0, 0, 0, 0 };
local KEYS_BUTTON = theme.derive('LIGHT', 0.07); -- (a button under the mouse in key mode: as the others)
local POPUP_BG = theme.derive('BG', 0.92);

local COLORS = {
    { ImGuiCol_Text,                 theme.TEXT },
    { ImGuiCol_TextDisabled,         theme.FAINT },
    { ImGuiCol_WindowBg,             WINDOW_BG },
    { ImGuiCol_ChildBg,              theme.derive('BLACK', 0.18) },
    { ImGuiCol_PopupBg,              POPUP_BG },
    { ImGuiCol_Border,               BORDER },
    { ImGuiCol_BorderShadow,         theme.derive('BLACK', 0.00) },
    { ImGuiCol_FrameBg,              theme.derive('BLACK', 0.32) },
    { ImGuiCol_FrameBgHovered,       theme.derive('LIGHT', 0.06) },
    { ImGuiCol_FrameBgActive,        theme.derive('LIGHT', 0.09) },
    { ImGuiCol_Button,               theme.derive('LIGHT', 0.07) },
    { ImGuiCol_ButtonHovered,        theme.derive('ACCENT', 0.22) },
    { ImGuiCol_ButtonActive,         theme.derive('ACCENT', 0.34) },
    { ImGuiCol_Header,               theme.derive('ACCENT', 0.20) },
    { ImGuiCol_HeaderHovered,        theme.derive('LIGHT', 0.07) },
    { ImGuiCol_HeaderActive,         theme.derive('ACCENT', 0.30) },
    { ImGuiCol_Separator,            theme.derive('LIGHT', 0.09) },
    { ImGuiCol_ScrollbarBg,          theme.derive('BLACK', 0.00) },
    { ImGuiCol_ScrollbarGrab,        theme.derive('LIGHT', 0.14) },
    { ImGuiCol_ScrollbarGrabHovered, theme.derive('LIGHT', 0.22) },
    { ImGuiCol_ScrollbarGrabActive,  theme.derive('ACCENT', 0.45) },
    { ImGuiCol_CheckMark,            theme.ACCENT },
    { ImGuiCol_TextSelectedBg,       theme.derive('ACCENT', 0.30) },
    { ImGuiCol_NavCursor,            theme.derive('ACCENT', 0.00) },
};

local TITLE, TITLE_ACTIVE = { 0, 0, 0, 1 }, { 0, 0, 0, 1 };
local MOVABLE = theme.derive('ACCENT', 0.8); -- a window's edge while it can be dragged

--[[
* Switches to theme name ('glass', 'clean', 'guild' or 'phoenix'; anything else is the glass), with the panels'
* opacity (0.2-1; 0 or nil: the theme's own). Windows that nothing shows through, and popups, stay
* at least as solid as the panels.
--]]
function theme.set(name, opacity)
    if (THEMES[name] == nil) then
        name = 'glass';
    end
    P = THEMES[name];
    theme.name, theme.opacity_now = name, opacity;
    for key, from in pairs(KEYS) do
        local c, t = P[from], theme[key];
        t[1], t[2], t[3] = c[1], c[2], c[3];
    end
    for _, d in ipairs(derived) do
        local c = theme[d[2]];
        d[1][1], d[1][2], d[1][3], d[1][4] = c[1], c[2], c[3], d[3];
    end
    -- The player's opacity is the panels'; every other background moves with it in proportion
    -- (the solid windows, the config window's title bar, popups), never so far it can't be read.
    local a = (opacity ~= nil and opacity > 0) and math.max(0.2, math.min(1, opacity)) or P.bg_a;
    local k = a / P.bg_a;
    WINDOW_BG[4] = a;
    SOLID[4] = math.max(0.3, math.min(1, P.solid_a * k));
    POPUP_BG[4] = math.max(0.5, math.min(1, P.popup_a * k));
    TITLE[1], TITLE[2], TITLE[3] = P.title[1], P.title[2], P.title[3];
    TITLE_ACTIVE[1], TITLE_ACTIVE[2], TITLE_ACTIVE[3] = P.title_active[1], P.title_active[2], P.title_active[3];
    TITLE[4] = math.max(0.3, math.min(1, k));
    TITLE_ACTIVE[4] = TITLE[4];
    theme.version = theme.version + 1;
end

-- Parts of the interface with a theme of their own: [key] = theme name, or nil for the rest's.
theme.AREAS = {};
local main = nil; -- { name, opacity } while an area's theme is in

-- Into area key's theme (when it has one, other than the rest's); true if it switched.
function theme.begin_area(key)
    local t = key ~= nil and theme.AREAS[key] or nil;
    if (t == nil or t == theme.name or main ~= nil or THEMES[t] == nil) then
        return false;
    end
    main = { theme.name, theme.opacity_now };
    theme.set(t, 0);
    return true;
end

-- Back to the rest's theme (also at the start of each frame, should a window have stopped midway).
function theme.end_area()
    if (main ~= nil) then
        local m = main;
        main = nil;
        theme.set(m[1], m[2]);
    end
end

-- The panels' opacity in a theme (its own, before the player's choice).
function theme.opacity(name)
    return (THEMES[name] or THEMES.glass).bg_a;
end

-- The backgrounds' alphas now: panels, solid windows (the config window, the price box), popups.
function theme.backgrounds()
    return WINDOW_BG[4], SOLID[4], POPUP_BG[4];
end

local function vars(fs, pad_y)
    local v = {
        { ImGuiStyleVar_WindowRounding,    P.round * ck },
        { ImGuiStyleVar_ChildRounding,     P.inner * ck },
        { ImGuiStyleVar_FrameRounding,     P.inner * ck },
        { ImGuiStyleVar_PopupRounding,     P.inner * ck },
        { ImGuiStyleVar_ScrollbarRounding, P.inner * ck },
        { ImGuiStyleVar_GrabRounding,      P.inner * ck },
        { ImGuiStyleVar_WindowBorderSize,  1 },
        { ImGuiStyleVar_ChildBorderSize,   0 },
        { ImGuiStyleVar_FrameBorderSize,   0 },
        { ImGuiStyleVar_ScrollbarSize,     8 * fs },
        { ImGuiStyleVar_WindowPadding,     { 12 * fs, 10 * fs } },
        { ImGuiStyleVar_FramePadding,      { 8 * fs, 4 * fs } },
        { ImGuiStyleVar_ItemSpacing,       { 6 * fs, 5 * fs } },
    };
    if (pad_y ~= nil) then
        for _, s in ipairs(v) do
            if (s[1] == ImGuiStyleVar_WindowPadding) then
                s[2] = { 12 * fs, pad_y };
            end
        end
        v[#v + 1] = { ImGuiStyleVar_WindowMinSize, { 1, 1 } }; -- else ImGui keeps it at least 32 px tall
    end
    return v;
end

local function u32(c)
    return imgui.GetColorU32(c);
end

-- The glass: a sheen fading down from the top edge and a brighter line along it (the glass theme
-- only), on the window or on the rect x, y, w, h.
local SHEEN, CLEAR, EDGE = { 1, 1, 1, 0.07 }, { 1, 1, 1, 0.0 }, { 1, 1, 1, 0.22 };
local function glass(x, y, w, h)
    if (not P.sheen) then
        return;
    end
    local dl = imgui.GetWindowDrawList();
    if (x == nil) then
        x, y = imgui.GetWindowPos();
        w, h = imgui.GetWindowSize();
    end
    local sheen = math.min(h * 0.45, 70);
    local top, clear = u32(SHEEN), u32(CLEAR);
    dl:AddRectFilledMultiColor({ x + 1, y + 1 }, { x + w - 1, y + sheen }, top, top, clear, clear);
    dl:AddLine({ x + 10, y + 1 }, { x + w - 10, y + 1 }, u32(EDGE), 1);
end

local depth = 0;
local pushed = {};

-- A window's text: the windows' text font (ui/fonts) or ImGui's own, at the base size times fs.
local function push_text(fs)
    local f, size = fonts.text(imgui.GetFontSize() * fs);
    imgui.PushFont(f or imgui.GetFont(), size);
end

--[[
* Starts a themed window (call theme.finish after, whatever this returns). Flags default to a fixed
* overlay: no title, no moving or resizing, nothing saved; extra_flags are added. movable: the player
* can drag it (layout edit mode), with an accent edge. solid: nothing shows through it (a window
* that sits over others, like the price box). pad_y: its top and bottom padding in pixels, else
* the theme's. With ImGuiWindowFlags_NoBackground in extra_flags the window draws no background or
* edge (outside edit mode): its pane draws theme.box where it wants one. bg_a: the window's own
* background opacity (0-1), over the theme's (0: no background, edge or sheen).
--]]
local OWN_BG = { 0, 0, 0, 0 };
function theme.window(name, fs, extra_flags, movable, solid, pad_y, bg_a)
    local v = vars(fs, pad_y);
    for _, c in ipairs(COLORS) do
        imgui.PushStyleColor(c[1], c[2]);
    end
    for _, s in ipairs(v) do
        imgui.PushStyleVar(s[1], s[2]);
    end
    local nc = #COLORS;
    if (pointer.keys) then -- (key mode: no hover highlight where the mouse rests; ui/pointer)
        imgui.PushStyleColor(ImGuiCol_HeaderHovered, NONE);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, KEYS_BUTTON);
        nc = nc + 2;
    end
    if (solid) then
        imgui.PushStyleColor(ImGuiCol_WindowBg, SOLID);
        nc = nc + 1;
    end
    if (bg_a ~= nil and not solid) then
        OWN_BG[1], OWN_BG[2], OWN_BG[3], OWN_BG[4] = theme.BG[1], theme.BG[2], theme.BG[3], math.max(0, math.min(1, bg_a));
        imgui.PushStyleColor(ImGuiCol_WindowBg, OWN_BG);
        nc = nc + 1;
    end
    local bare = bit.band(extra_flags or 0, ImGuiWindowFlags_NoBackground) ~= 0 or bg_a == 0;
    if (movable == true) then -- (true: being edited, its edge lit; 'quiet': movable, as it looks)
        imgui.PushStyleColor(ImGuiCol_Border, MOVABLE);
        nc = nc + 1;
    elseif (bare) then
        imgui.PushStyleColor(ImGuiCol_Border, NONE);
        nc = nc + 1;
    end
    depth = depth + 1;
    pushed[depth] = { nc, #v };
    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize, movable and 0 or ImGuiWindowFlags_NoMove,
        ImGuiWindowFlags_NoCollapse, ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoFocusOnAppearing,
        extra_flags or 0);
    local open = imgui.Begin(name, true, flags);
    if (open) then
        if (not bare) then
            glass();
        end
        push_text(fs);
    end
    pushed[depth][3] = open;
    return open;
end

-- A window's background and edge, as theme.window draws them, on the rect (x0, y0)-(x1, y1) (screen
-- px) of the window being drawn: for a window without its own (ImGuiWindowFlags_NoBackground) that
-- frames only part of what it shows. bg_a: its own opacity (0-1) over the theme's (0: nothing drawn).
local bx0, bx1 = { 0, 0 }, { 0, 0 };
local BOX_BG = { 0, 0, 0, 0 };
function theme.box(x0, y0, x1, y1, bg_a)
    if (bg_a == 0) then
        return;
    end
    local dl = imgui.GetWindowDrawList();
    bx0[1], bx0[2], bx1[1], bx1[2] = x0, y0, x1, y1;
    local bg = WINDOW_BG;
    if (bg_a ~= nil) then
        BOX_BG[1], BOX_BG[2], BOX_BG[3], BOX_BG[4] = theme.BG[1], theme.BG[2], theme.BG[3], math.min(1, bg_a);
        bg = BOX_BG;
    end
    dl:AddRectFilled(bx0, bx1, u32(bg), P.round * ck);
    dl:AddRect(bx0, bx1, u32(BORDER), P.round * ck, 0, 1);
    glass(x0, y0, x1 - x0, y1 - y0);
end

-- facelift's own windows (the config window): solid, a title bar to move it by, tabs in the
-- accent, resizable; ImGui keeps where it is. No close button: title_button(wx, wy, ww), if given,
-- draws what goes in its place (the tray's -), before the window's text size is pushed (the title
-- bar is laid out at the base size); its result is returned second.
local PANEL = {
    { ImGuiCol_WindowBg,             SOLID },
    { ImGuiCol_TitleBg,              TITLE },
    { ImGuiCol_TitleBgActive,        TITLE_ACTIVE },
    { ImGuiCol_TitleBgCollapsed,     TITLE },
    { ImGuiCol_Tab,                  theme.derive('LIGHT', 0.05) },
    { ImGuiCol_TabHovered,           theme.derive('ACCENT', 0.26) },
    { ImGuiCol_TabSelected,          theme.derive('ACCENT', 0.20) },
    { ImGuiCol_TabSelectedOverline,  theme.ACCENT },
    { ImGuiCol_SliderGrab,           theme.derive('ACCENT', 0.70) },
    { ImGuiCol_SliderGrabActive,     theme.ACCENT },
    { ImGuiCol_ResizeGrip,           theme.derive('LIGHT', 0.08) },
    { ImGuiCol_ResizeGripHovered,    theme.derive('ACCENT', 0.40) },
    { ImGuiCol_ResizeGripActive,     theme.derive('ACCENT', 0.70) },
};

function theme.panel(name, fs, title_button)
    local v = vars(fs);
    for _, c in ipairs(COLORS) do
        imgui.PushStyleColor(c[1], c[2]);
    end
    for _, c in ipairs(PANEL) do
        imgui.PushStyleColor(c[1], c[2]);
    end
    for _, s in ipairs(v) do
        imgui.PushStyleVar(s[1], s[2]);
    end
    depth = depth + 1;
    pushed[depth] = { #COLORS + #PANEL, #v };
    local shown = imgui.Begin(name, nil, ImGuiWindowFlags_NoCollapse);
    local hit = false;
    if (shown) then
        if (title_button ~= nil) then
            local wx, wy = imgui.GetWindowPos();
            local ww = imgui.GetWindowSize();
            hit = title_button(wx, wy, ww);
        end
        push_text(fs);
    end
    pushed[depth][3] = shown;
    return shown, hit;
end

function theme.finish()
    local p = pushed[depth];
    if (p[3]) then
        imgui.PopFont();
    end
    imgui.End();
    imgui.PopStyleVar(p[2]);
    imgui.PopStyleColor(p[1]);
    pushed[depth] = nil;
    depth = depth - 1;
end

-- For a window that failed part-way: forget windows started since mark (ui/gui closes them).
function theme.mark()
    return depth;
end
function theme.unwind(mark)
    while (depth > mark) do
        pushed[depth] = nil;
        depth = depth - 1;
    end
end

theme.set('glass');

return theme;
