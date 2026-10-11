--[[
* facelift - layout/store
* The player's changes to window layouts, per character, in their own settings file
* (config/addons/facelift/<character>/layout.lua) next to settings.lua. Only what was changed is kept:
* windows = { [window id] = { dx = 12, dy = -40, fs = 1.2, opts = { rows = 15 } } }; everything else
* comes from the window's own layout (windows/<id>.lua).
*
* Each change stores a new table for that window, so the runtime can tell a window's layout changed
* by comparing tables.
--]]

local settings = require('settings');

local store = {
    dirty = false,
};

local DEFAULTS = T{ version = 1, windows = T{} };
local s = nil;

-- Ashita's settings merge copies a missing table from the defaults by reference: give this
-- character a table of their own so their changes never land in the defaults (or another character).
local function detach()
    if (s.windows == nil or rawequal(s.windows, DEFAULTS.windows)) then
        s.windows = T{};
    end
end

function store.load()
    s = settings.load(DEFAULTS, 'layout');
    detach();
    settings.register('layout', 'facelift_layout_update', function (n)
        if (n ~= nil) then
            s = n;
            detach();
        end
    end);
end

-- A window's changes, or nil.
function store.get(id)
    return s ~= nil and s.windows[id] or nil;
end

-- Sets fields of a window's changes (a field set to false is removed).
function store.set(id, fields)
    local o = {};
    for k, v in pairs(s.windows[id] or {}) do
        o[k] = v;
    end
    for k, v in pairs(fields) do
        if (v == false) then
            o[k] = nil;
        else
            o[k] = v;
        end
    end
    s.windows[id] = next(o) ~= nil and o or nil;
    store.dirty = true;
end

-- Drops a window's changes (id nil: every window's).
function store.reset(id)
    if (id == nil) then
        s.windows = T{};
    else
        s.windows[id] = nil;
    end
    store.dirty = true;
end

function store.save()
    if (store.dirty and s ~= nil) then
        settings.save('layout');
        store.dirty = false;
    end
end

return store;
