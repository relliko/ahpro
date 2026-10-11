--[[
* facelift - core/presence: which of facelift and ahpro (its auction house on its own) are loaded, so
* the two never both cover the auction house: ahpro steps aside while facelift is loaded. Ashita gives
* each addon its own Lua, so this is a process environment variable (FACELIFT_<NAME> = 1).
--]]

local ffi = require('ffi');

pcall(ffi.cdef, [[
    int SetEnvironmentVariableA(const char* name, const char* value);
    unsigned long GetEnvironmentVariableA(const char* name, char* buf, unsigned long size);
]]);

local presence = {};

local function var(name)
    return 'FACELIFT_' .. name:upper();
end

-- This addon is loaded (on) or unloaded (off).
function presence.set(name, on)
    pcall(function () ffi.C.SetEnvironmentVariableA(var(name), on and '1' or nil); end);
end

-- Whether addon name says it's loaded.
function presence.loaded(name)
    local ok, n = pcall(function ()
        local buf = ffi.new('char[4]');
        return ffi.C.GetEnvironmentVariableA(var(name), buf, 4);
    end);
    return ok and n ~= nil and n > 0;
end

return presence;
