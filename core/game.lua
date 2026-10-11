--[[
* facelift - core/game
* The only way facelift acts on the game: writing a handler's own fields and calling the game's own
* functions, the same code its keys run. Never a packet. Callers check the menu is still open and
* its handler is the class they expect before calling here.
--]]

local ffi     = require('ffi');
local safemem = require('core.safemem');
local sigs    = require('core.sigs');
local menus   = require('core.menus');

local game = {};

local casts = {}; -- [proto][address] = cast function

local function cast(proto, addr)
    local t = casts[proto];
    if (t == nil) then
        t = {};
        casts[proto] = t;
    end
    local f = t[addr];
    if (f == nil) then
        f = ffi.cast(proto, addr);
        t[addr] = f;
    end
    return f;
end

local function in_client(addr)
    local base = ashita.memory.get_base('FFXiMain.dll') or 0;
    local size = ashita.memory.get_size('FFXiMain.dll') or 0;
    return base ~= 0 and addr >= base and addr < base + size;
end

-- Calls a 'fn' pattern on this (an address) with the rest of the arguments. False if it wasn't found.
function game.call(name, this, ...)
    local f = sigs.fn(name);
    if (f == nil) then
        return false;
    end
    f(ffi.cast('void*', this), ...);
    menus.invalidate();
    return true;
end

--[[
* Calls this object's virtual function at vtable + slot, typed proto, with the rest of the arguments.
* Only if the vtable entry points into the game's own code. Returns false if it doesn't, else true
* and what the function returned.
--]]
function game.vcall(this, slot, proto, ...)
    local vt = safemem.u32(this);
    local fn = vt ~= nil and safemem.u32(vt + slot) or nil;
    if (fn == nil or not in_client(fn)) then
        return false;
    end
    local r = cast(proto, fn)(ffi.cast('void*', this), ...);
    menus.invalidate();
    return true, r;
end

function game.write_i32(addr, v) ashita.memory.write_int32(addr, v); end
function game.write_u8(addr, v) ashita.memory.write_uint8(addr, v); end

return game;
