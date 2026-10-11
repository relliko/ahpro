--[[
* facelift - core/clock: a fine timer (QueryPerformanceCounter) for measuring what windows cost.
* os.clock only moves in whole milliseconds here.
--]]

local ffi = require('ffi');

local clock = {};

local qpc, buf, freq = nil, nil, 0;
pcall(function ()
    pcall(ffi.cdef, [[
        int __stdcall QueryPerformanceCounter(int64_t* count);
        int __stdcall QueryPerformanceFrequency(int64_t* freq);
    ]]);
    buf = ffi.new('int64_t[1]');
    ffi.C.QueryPerformanceFrequency(buf);
    freq = tonumber(buf[0]);
    qpc = ffi.C.QueryPerformanceCounter;
end);

-- Seconds since some point, as finely as the machine can tell.
function clock.now()
    if (qpc ~= nil and freq > 0) then
        qpc(buf);
        return tonumber(buf[0]) / freq;
    end
    return os.clock();
end

return clock;
