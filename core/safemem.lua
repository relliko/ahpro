--[[
* facelift - core/safemem (from scouter, via bidcache; reads over 4096 bytes since 0.16.5)
* Reads the game's memory without touching it: ReadProcessMemory on our own process, which fails
* cleanly on an address the game has freed or never mapped, where a direct read (ashita.memory's
* read_*) takes the whole client down with no message. Pointer chains into game objects that come
* and go (menus) must be read this way.
--]]

local ffi = require('ffi');

local safemem = {
    rpm = nil,   -- (tests) stands in for ReadProcessMemory: function (addr, n) -> string or nil
    MAX = 0x60000, -- the most safemem.read takes at once (an auction list of 4000 rows is 0x52080)
};

local win = nil;
local function kernel()
    if (win == nil) then
        pcall(ffi.cdef, [[
            void* __stdcall GetCurrentProcess(void);
            int __stdcall ReadProcessMemory(void* process, const void* address, void* buffer, size_t size, size_t* read);
        ]]);
        win = { buf = ffi.new('uint8_t[4096]'), got = ffi.new('size_t[1]'), process = ffi.C.GetCurrentProcess() };
    end
    return win;
end

-- n (1 to safemem.MAX) bytes at addr as a string, or nil when any of them can't be read. Up to 4096
-- go through a fixed buffer; more (a list's rows) through one kept at the largest size asked for.
local big, big_n = nil, 0;
function safemem.read(addr, n)
    if (type(addr) ~= 'number' or addr < 0x10000 or addr >= 0x100000000 or type(n) ~= 'number' or n < 1 or n > safemem.MAX) then
        return nil;
    end
    if (safemem.rpm ~= nil) then
        return safemem.rpm(addr, n);
    end
    local ok, s = pcall(function ()
        local k = kernel();
        local buf = k.buf;
        if (n > 4096) then
            if (big_n < n) then
                big_n = math.min(safemem.MAX, math.max(n, big_n * 2, 0x4000));
                big = ffi.new('uint8_t[?]', big_n);
            end
            buf = big;
        end
        if (ffi.C.ReadProcessMemory(k.process, ffi.cast('const void*', addr), buf, n, k.got) == 0 or tonumber(k.got[0]) ~= n) then
            return nil;
        end
        return ffi.string(buf, n);
    end);
    return ok and s or nil;
end

-- n (1-4096) bytes at addr into buf (an ffi byte array at least that long), with nothing allocated
-- (for reads made many times a frame); false when any of them can't be read (buf is then left as it
-- was, or partly written). ReadProcessMemory reports a bad address by its result, so no pcall.
local rpm = nil;
function safemem.into(addr, n, buf)
    if (type(addr) ~= 'number' or addr < 0x10000 or addr >= 0x100000000 or n < 1 or n > 4096) then
        return false;
    end
    if (safemem.rpm ~= nil) then
        local s = safemem.rpm(addr, n);
        if (s == nil) then
            return false;
        end
        ffi.copy(buf, s, n);
        return true;
    end
    if (rpm == nil) then
        local ok = pcall(function ()
            local k = kernel();
            pcall(ffi.cdef, [[
                int __stdcall fl_rpm(void* process, uintptr_t address, void* buffer, size_t size, size_t* read) __asm__("ReadProcessMemory");
            ]]);
            local ok, fn = pcall(function () return ffi.C.fl_rpm; end);
            if (not ok) then
                -- No asm-labelled name: the plain declaration, the address cast per call.
                local C = ffi.C;
                fn = function (p, a, b, n, g) return C.ReadProcessMemory(p, ffi.cast('const void*', a), b, n, g); end;
            end
            rpm = { fn = fn, process = k.process, got = ffi.new('size_t[1]') };
        end);
        if (not ok or rpm == nil) then
            rpm = false;
        end
    end
    if (rpm == false) then
        return false;
    end
    return rpm.fn(rpm.process, addr, buf, n, rpm.got) ~= 0 and rpm.got[0] == n;
end

function safemem.u32(addr)
    local s = safemem.read(addr, 4);
    if (s == nil) then
        return nil;
    end
    local a, b, c, d = s:byte(1, 4);
    return a + b * 256 + c * 65536 + d * 16777216;
end

-- Little-endian values in a string from safemem.read, at byte offset o (from 0).
function safemem.le16(s, o)
    local a, b = s:byte(o + 1, o + 2);
    return a + b * 256;
end
function safemem.les16(s, o)
    local v = safemem.le16(s, o);
    return v >= 0x8000 and v - 0x10000 or v;
end
function safemem.le32(s, o)
    local a, b, c, d = s:byte(o + 1, o + 4);
    return a + b * 256 + c * 65536 + d * 16777216;
end
function safemem.les32(s, o)
    local v = safemem.le32(s, o);
    return v >= 0x80000000 and v - 0x100000000 or v;
end

function safemem.float(addr)
    local s = safemem.read(addr, 4);
    if (s == nil) then
        return nil;
    end
    local f = ffi.new('float[1]');
    ffi.copy(f, s, 4);
    return tonumber(f[0]);
end

-- The NUL-ended string at addr (at most max bytes, 256 by default), or nil when it can't be read. Read
-- in pieces up to the next 64-byte boundary, so a short string at the end of mapped memory still reads.
function safemem.cstr(addr, max)
    if (type(addr) ~= 'number' or addr < 0x10000) then
        return nil;
    end
    max = max or 256;
    local parts, got, a = {}, 0, addr;
    while (got < max) do
        local n = math.min(64 - a % 64, max - got);
        local s = safemem.read(a, n);
        if (s == nil) then
            return nil;
        end
        local z = s:find('\0', 1, true);
        if (z ~= nil) then
            parts[#parts + 1] = s:sub(1, z - 1);
            return table.concat(parts);
        end
        parts[#parts + 1] = s;
        got, a = got + n, a + n;
    end
    return table.concat(parts);
end

return safemem;
