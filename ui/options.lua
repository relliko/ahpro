--[[
* facelift - ui/options: drawing settings: a checkbox, sliders (set while dragging, done once let go),
* a hint under a setting, and a window's options (windows/init: options) as the config window and the
* windows' cogs show them. A window's option is kept with its layout, for this character.
--]]

local imgui = require('ui.gui');
local theme = require('ui.theme');
local store = require('layout.store');

local options = {};

local cb, fb, ib = { false }, { 0 }, { 0 };

-- A checkbox for a value: true and the new value when it was clicked.
function options.check(label, value)
    cb[1] = value == true;
    if (imgui.Checkbox(label, cb)) then
        return true, cb[1];
    end
    return false, value;
end

-- Sliders: set(v) while dragging, done() once let go.
function options.slider_f(label, value, lo, hi, format, set, done)
    fb[1] = value;
    if (imgui.SliderFloat(label, fb, lo, hi, format)) then
        set(math.max(lo, math.min(hi, fb[1])));
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then
        done();
    end
end
function options.slider_i(label, value, lo, hi, format, set, done)
    ib[1] = value;
    if (imgui.SliderInt(label, ib, lo, hi, format)) then
        set(math.max(lo, math.min(hi, math.floor(ib[1]))));
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then
        done();
    end
end

-- A short grey line under a setting.
function options.hint(text)
    imgui.PushStyleColor(ImGuiCol_Text, theme.FAINT);
    imgui.TextWrapped(text);
    imgui.PopStyleColor();
end

-- Sets a window's option (kept with its layout, for this character).
function options.set_opt(w, k, v)
    local cur = store.get(w.id);
    local t = {};
    for kk, vv in pairs(cur ~= nil and cur.opts or {}) do
        t[kk] = vv;
    end
    t[k] = v;
    store.set(w.id, { opts = t });
end

--[[
* A window's option (windows/init: options): kind 'check' a checkbox (0 or 1), 'choice' a list of
* choices[min..max], else a slider (format: its number's); a hint under it; when = another option
* it's shown only while that one isn't 0.
--]]
function options.option(w, k, o)
    if (o.when ~= nil and (w.opt(o.when) or 0) == 0) then
        return;
    end
    local id = '##facelift_opt_' .. w.id .. '_' .. k;
    local v = w.opt(k) or o.default or o.min;
    if (o.kind == 'check') then
        local h, now = options.check(o.label .. id, v ~= 0);
        if (h) then
            options.set_opt(w, k, now and 1 or 0);
            store.save();
        end
    elseif (o.kind == 'choice') then
        if (imgui.BeginCombo(o.label .. id, o.choices[v] or tostring(v))) then
            for i = o.min, o.max do
                if (imgui.Selectable(o.choices[i] .. id .. '_' .. i, i == v)) then
                    options.set_opt(w, k, i);
                    store.save();
                end
            end
            imgui.EndCombo();
        end
    else
        imgui.PushTextWrapPos(0);
        imgui.Text(o.label);
        imgui.PopTextWrapPos();
        options.slider_i(id, v, o.min, o.max, o.format or '%d', function (nv) options.set_opt(w, k, nv); end, store.save);
    end
    if (o.hint ~= nil) then
        options.hint(o.hint);
    end
end

-- A window's options in their order (o.order, then by name).
function options.options_of(w)
    local opts = w.spec.options;
    if (opts == nil) then
        return nil;
    end
    local keys = {};
    for k in pairs(opts) do
        keys[#keys + 1] = k;
    end
    table.sort(keys, function (x, y)
        local ox, oy = opts[x].order or 99, opts[y].order or 99;
        if (ox ~= oy) then
            return ox < oy;
        end
        return x < y;
    end);
    return keys;
end

-- A window's options, each as option() draws it, in their order.
function options.draw(w)
    for _, k in ipairs(options.options_of(w) or {}) do
        options.option(w, k, w.spec.options[k]);
    end
end

return options;
