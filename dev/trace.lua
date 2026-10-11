--[[
* facelift - dev/trace: a short log of game memory as it changes, for finding out what the game does
* with something (/facelift trace [seconds]). Code with something to show checks trace.on() (cheap
* when off) and gives trace.state(key, text): text is written, with the time, only when it differs
* from the last for that key. It stops by itself after the time or 2000 entries.
--]]

local trace = { path = nil };

local f, stop_at, last, n = nil, 0, {}, 0;

function trace.stop()
    if (f ~= nil) then
        f:write(('%.3f end\n'):format(os.clock()));
        f:close();
        f = nil;
    end
end

-- Starts a log of the next seconds (default 30) in trace.path; false and why if it can't.
function trace.start(seconds)
    trace.stop();
    local why;
    f, why = io.open(trace.path or 'trace.txt', 'w');
    if (f == nil) then
        return false, why;
    end
    stop_at, last, n = os.clock() + (seconds or 30), {}, 0;
    f:write(('facelift trace, %s\n'):format(os.date('%Y-%m-%d %H:%M:%S')));
    return true;
end

function trace.on()
    if (f == nil) then
        return false;
    end
    if (os.clock() > stop_at or n >= 2000) then
        trace.stop();
        return false;
    end
    return true;
end

function trace.state(key, text)
    if (f ~= nil and last[key] ~= text) then
        last[key], n = text, n + 1;
        f:write(('%.3f %s\n%s\n'):format(os.clock(), key, text));
    end
end

return trace;
