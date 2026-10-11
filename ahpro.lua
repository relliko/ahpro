--[[
* ahpro
*
* facelift's auction house on its own: the whole auction house in one window (Bid, Sell and Sales
* Status as tabs, the categories with their icons, an item lookup, the prices seen, Sales Status's
* pages gathered into one list), or its separate windows, and the price box. Each is drawn over the
* game's own window while that's open and works through it, exactly what its keys do; unload ahpro (or
* turn a window off) and the game's is back.
*
* Nothing is ever sent to the server and no packet is built or changed: anything that gets sent is
* what the game's own window sends.
*
* It's built from facelift's own code (the same files: tools/package.py picks the ones it needs), so
* the two never differ. With facelift loaded, ahpro steps aside: facelift has the same windows.
--]]

addon.name    = 'ahpro';
addon.author  = 'Relli';
addon.version = require('version');
addon.desc    = 'The auction house in one window, with item search and the prices seen (from facelift).';
addon.link    = 'https://github.com/relliko/ahpro';

require('common');
local chat     = require('chat');
local imgui    = require('imgui');
local settings = require('settings');
local menus    = require('core.menus');
local hide     = require('core.hide');
local runtime  = require('windows.runtime');
local store    = require('layout.store');
local prices   = require('db.prices');
local keys     = require('core.keys');
local era      = require('core.era');
local theme    = require('ui.theme');
local fonts    = require('ui.fonts');
local pointer  = require('ui.pointer');
local ahpages  = require('core.ahpages');
local presence = require('core.presence');
local cog      = require('ui.cog');

local windows = {};
for i, spec in ipairs(require('windows.ah')) do
    windows[i] = runtime.make(spec);
end
-- facelift's item tooltip, only while an auction house window is up (it docks the game's tooltip
-- beside them, where facelift has it; anywhere else the game's own shows, as without ahpro).
do
    local tip, ids = {}, {};
    for k, v in pairs(require('windows.iteminfo')) do
        tip[k] = v;
    end
    for _, w in ipairs(windows) do
        ids[#ids + 1] = w.id;
    end
    tip.while_up, tip.title, tip.look = ids, 'Item tooltip (at the auction house)', 'ah';
    windows[#windows + 1] = runtime.make(tip);
end

-- The switches, one per toggle key, named by its first window.
local toggles, by_key = {}, {};
for _, w in ipairs(windows) do
    local k = w.spec.toggle;
    local t = by_key[k];
    if (t == nil) then
        t = { key = k, title = w.spec.title, fallback = w.spec.fallback, windows = {} };
        by_key[k] = t;
        toggles[#toggles + 1] = t;
    end
    t.windows[#t.windows + 1] = w;
end

local defaults = T{
    views = T{ ahone = true, auccats = true, auclist = true, prices = true, moneyctr = true },
    font_scale = 1.0,
    text_follows_ui = true, -- text and ahpro's sizes grow and shrink with the game's UI on screen
    -- The look (ui/theme): 'glass', 'clean', 'guild' or 'phoenix', the panels' opacity (0: the
    -- theme's), corners, and the text font (ImGui's own: the game's fonts are facelift's only).
    look = T{ theme = 'glass', opacity = 0, font = 'imgui', corners = 'square' },
    era = true, -- what an era server has no use for, hidden (core/era): the Geomancy category
};

local ap = {
    settings = settings.load(defaults),
    stopped = nil, -- an error outside any window stops ahpro until /ahpro retry
    aside = false, -- facelift is loaded: it has these windows
    env = { scale = 1, fs = 1, dw = 0, dh = 0 },
};

local function msg(text)
    print(chat.header(addon.name):append(chat.message(text)));
end

local function toggle_on(key)
    local on = ap.settings.views[key];
    return on == nil or on == true;
end

local function window_on(w)
    local s = w.spec;
    return toggle_on(s.toggle) and (s.off_with == nil or not toggle_on(s.off_with)) and (s.on_with == nil or toggle_on(s.on_with));
end

local function first_line(err)
    return (tostring(err):match('^[^\n]*'));
end

runtime.notify = function (w, err)
    local t = by_key[w.spec.toggle];
    msg(('%s (%s) hit an error and turned off, so the game\'s own window shows: %s. /ahpro errors, /ahpro retry'):fmt(
        t.title, w.id, first_line(err)));
end

store.load();
theme.set(ap.settings.look.theme, ap.settings.look.opacity);
theme.corners(ap.settings.look.corners);
-- Prices are the server's, kept for all characters together: facelift's file when it has one (the
-- same prices, whichever is loaded), else ahpro's own.
do
    local base = AshitaCore:GetInstallPath():gsub('\\', '/') .. '/config/addons/';
    local fl = base .. 'facelift/prices.tsv';
    local f = io.open(fl, 'r');
    if (f ~= nil) then
        f:close();
        prices.path = fl;
    else
        prices.path = base .. 'ahpro/prices.tsv';
    end
end

settings.register('settings', 'ahpro_settings_update', function (s)
    if (s ~= nil) then
        ap.settings = s;
        theme.set(s.look.theme, s.look.opacity);
        theme.corners(s.look.corners);
    end
end);

-- Its theme, in the auction house's cog (ui/cog): ahpro's whole look.
cog.theme_picker = function ()
    local s = ap.settings;
    local shown = s.look.theme;
    for _, t in ipairs(theme.NAMES) do
        if (t[1] == s.look.theme) then
            shown = t[2];
        end
    end
    if (imgui.BeginCombo('Theme##ahpro_theme', shown)) then
        for _, t in ipairs(theme.NAMES) do
            if (imgui.Selectable(t[2] .. '##ahpro_theme_' .. t[1], t[1] == s.look.theme)) then
                s.look.theme, s.look.opacity = t[1], 0;
                theme.set(t[1], 0);
                settings.save();
            end
        end
        imgui.EndCombo();
    end
end;

ashita.events.register('unload', 'ahpro_unload', function ()
    hide.restore_all(); -- the game's own windows show again
    fonts.unload();
    pcall(function () require('ui.gametex').unload(); end);
    keys.reset();
    settings.save();
    store.save();
end);

-- Game windows are placed in UI pixels; the screen may be a different size.
local function ui_scale()
    local uw = menus.ui_size();
    local dw = imgui.GetIO().DisplaySize.x;
    if (uw ~= nil and dw ~= nil and dw > 0) then
        return dw / uw;
    end
    return 1;
end

local function frame()
    fonts.frame(ap.settings.look.font);
    menus.begin_frame();
    local m = menus.focused();
    local env = ap.env;
    local io = imgui.GetIO();
    env.scale, env.dw, env.dh = ui_scale(), io.DisplaySize.x, io.DisplaySize.y;
    env.fs = ap.settings.font_scale * (ap.settings.text_follows_ui ~= false and env.scale or 1);
    runtime.frame(windows, m, env, window_on);
end

ashita.events.register('d3d_present', 'ahpro_present', function ()
    -- With facelift loaded, it has these windows: ahpro steps aside (the game's menus left to it).
    local aside = presence.loaded('facelift');
    if (aside ~= ap.aside) then
        ap.aside = aside;
        if (aside) then
            hide.restore_all();
            msg('facelift is loaded and has the auction house: ahpro steps aside while it is.');
        end
    end
    if (aside or ap.stopped ~= nil) then
        keys.frame(imgui);
        return;
    end
    era.on = ap.settings.era ~= false;
    pointer.frame(); -- (keys or mouse, last used: ui/pointer)
    local ok, err = pcall(frame);
    keys.frame(imgui);
    hide.end_frame(); -- whatever happened, a game window not covered this frame is shown again
    if (not ok) then
        ap.stopped = err;
        keys.reset();
        hide.restore_all();
        msg(('Stopped after an error, so the game\'s own windows show: %s. /ahpro errors, /ahpro retry'):fmt(first_line(err)));
    end
end);

-- The game's keyboard read: only to keep an Enter ahpro already acted on from it (core/keys).
ashita.events.register('key_state', 'ahpro_key_state', function (e)
    keys.key_state(e);
end);

-- Sales Status's pages, as the server says them (core/ahpages).
ashita.events.register('text_in', 'ahpro_text_in', function (e)
    ahpages.text(e.message);
end);

local function status(t)
    for _, w in ipairs(t.windows) do
        if (not runtime.ready(w)) then
            return 'the game\'s code wasn\'t found (client changed?), so ' .. t.fallback;
        end
    end
    return 'ready';
end

ashita.events.register('command', 'ahpro_command', function (e)
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/ahpro')) then
        return;
    end
    e.blocked = true;
    local s = ap.settings;
    local cmd = (args[2] or ''):lower();
    local t = by_key[cmd];
    if (t ~= nil) then
        local to = (args[3] or ''):lower();
        local on = (to == '') and not toggle_on(t.key) or to == 'on';
        s.views[t.key] = on;
        settings.save();
        msg(('%s %s: %s.'):fmt(t.title, on and 'on' or 'off', on and 'the new window shows' or 'the game\'s own window shows'));
    elseif (cmd == 'theme') then
        local name = (args[3] or ''):lower();
        local known = {};
        for _, x in ipairs(theme.NAMES) do
            known[#known + 1] = x[1];
            if (x[1] == name) then
                s.look.theme, s.look.opacity = name, 0;
                theme.set(name, 0);
                settings.save();
                msg(('Theme: %s.'):fmt(x[2]));
                return;
            end
        end
        msg(('/ahpro theme %s   its look (now %s; also in the auction house\'s cog)'):fmt(table.concat(known, '|'), theme.name));
    elseif (cmd == 'opacity') then
        local n = tonumber(args[3] or '');
        if (n ~= nil and (n == 0 or (n >= 0.2 and n <= 1))) then
            s.look.opacity = n;
            theme.set(s.look.theme, n);
            settings.save();
            msg(n == 0 and 'Background opacity: the theme\'s own.' or ('Background opacity %.2f.'):fmt(n));
        else
            msg('/ahpro opacity <0.2-1>   how solid the backgrounds are (0: the theme\'s own)');
        end
    elseif (cmd == 'scale') then
        local n = tonumber(args[3] or '');
        if (n ~= nil and n >= 0.5 and n <= 4) then
            s.font_scale = n;
            settings.save();
            msg(('Text size %.2f.'):fmt(n));
        else
            msg('/ahpro scale <0.5-4>   text size (1 is normal)');
        end
    elseif (cmd == 'era') then
        local to = (args[3] or ''):lower();
        s.era = (to == '') and not (s.era ~= false) or to == 'on';
        settings.save();
        msg(s.era and 'Era: content after Abyssea hidden (the Geomancy category).' or 'Era: everything shown.');
    elseif (cmd == 'errors') then
        local any = ap.stopped ~= nil;
        if (any) then
            msg('Stopped: ' .. tostring(ap.stopped));
        end
        for _, w in ipairs(windows) do
            if (w.fault ~= nil) then
                any = true;
                msg(('%s: %s'):fmt(w.id, tostring(w.fault)));
            end
        end
        if (not any) then
            msg('No errors.');
        end
    elseif (cmd == 'retry') then
        ap.stopped = nil;
        for _, w in ipairs(windows) do
            w.off, w.fault = false, nil;
        end
        msg('Every window is back on.');
    else
        for _, x in ipairs(toggles) do
            msg(('%s (%s): %s, %s.'):fmt(x.title, x.key, toggle_on(x.key) and 'on' or 'off', status(x)));
        end
        if (ap.aside) then
            msg('facelift is loaded and has the auction house: ahpro steps aside while it is.');
        end
        msg('/ahpro <window> on|off, /ahpro theme <name>, /ahpro opacity <n>, /ahpro scale <n>, /ahpro era [on|off], /ahpro errors|retry. More in the auction house\'s cog (top right).');
    end
end);
