--[[
* facelift - core/sigs
* Finds the patterns in core/sigdefs, each once, the first time it's needed (the game is running by
* then), and keeps the result. A pattern that isn't found is 0; the windows that need it stay off.
--]]

local ffi     = require('ffi');
local safemem = require('core.safemem');
local defs    = require('core.sigdefs');

local sigs = {};

local by_name = {};
for _, d in ipairs(defs) do
    by_name[d.name] = d;
end

local found = {}; -- [name] = address, 0 when not found
local fns = {};   -- [name] = cast function

-- A pattern's address (see core/sigdefs for what each kind gives), or 0.
function sigs.get(name)
    local v = found[name];
    if (v == nil) then
        local d = by_name[name];
        if (d == nil) then
            error('facelift: no pattern called ' .. tostring(name), 2);
        end
        v = ashita.memory.find('FFXiMain.dll', 0, d.pat, d.off or 0, 0) or 0;
        if (v ~= 0 and d.kind == 'ptr') then
            v = safemem.u32(v) or 0;
        end
        found[name] = v;
    end
    return v;
end

-- A 'fn' pattern as a callable function, or nil when it wasn't found.
function sigs.fn(name)
    local f = fns[name];
    if (f == nil) then
        local a = sigs.get(name);
        if (a == 0) then
            return nil;
        end
        f = ffi.cast(by_name[name].proto, a);
        fns[name] = f;
    end
    return f;
end

-- True when every pattern in the list was found; else false and the first one that wasn't.
function sigs.ok(names)
    for _, n in ipairs(names or {}) do
        if (sigs.get(n) == 0) then
            return false, n;
        end
    end
    return true;
end

--[[
* Each pattern for /fl sigs: { name, kind, value, offset (from FFXiMain.dll's base, for code and fn),
* doc, note }. offset ~= doc means this client differs from the dump the notes were written from.
--]]
function sigs.report()
    local base = ashita.memory.get_base('FFXiMain.dll') or 0;
    local out = {};
    for _, d in ipairs(defs) do
        local v = sigs.get(d.name);
        local r = { name = d.name, kind = d.kind, value = v, doc = d.doc, note = d.note };
        if (v ~= 0 and d.kind ~= 'ptr' and base ~= 0) then
            r.offset = v - base;
        elseif (v ~= 0 and d.kind == 'ptr' and base ~= 0) then
            r.offset = ashita.memory.find('FFXiMain.dll', 0, d.pat, 0, 0) - base;
        end
        out[#out + 1] = r;
    end
    return out;
end

return sigs;
