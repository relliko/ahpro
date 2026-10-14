--[[
* facelift - core/perf: /facelift perf, what facelift costs a frame. For a few seconds each piece's
* time is added up (core/clock), with the frames' own length; then each piece's average a frame is
* said, slowest first, with its share of the frame.
*
* Lua's garbage collector is stopped for the sample, so what facelift leaves to collect a frame can be
* counted exactly; at the end it's restarted and one full collection timed (normally that work is
* spread over the frames in small steps, or comes as a pause).
--]]

local clock = require('core.clock');

local perf = { on = false };

local S = nil;

-- Starts a sample of secs seconds.
function perf.start(secs)
    S = { secs = secs, t0 = nil, last = nil, frames = 0, gap = 0, worst = 0, ms = {}, calls = {}, kb = {}, mem0 = nil };
    perf.on = true;
end

-- Adds ms to a piece (n calls, 1 if not given; kb of garbage made, if known).
function perf.add(key, ms, n, kb)
    if (S ~= nil) then
        S.ms[key] = (S.ms[key] or 0) + ms;
        S.calls[key] = (S.calls[key] or 0) + (n or 1);
        if (kb ~= nil) then
            S.kb[key] = (S.kb[key] or 0) + kb;
        end
    end
end

-- A time and Lua's memory to measure from, or nil while not sampling.
function perf.t()
    if (not perf.on) then
        return nil, nil;
    end
    return clock.now(), collectgarbage('count');
end

-- Adds the time since t0 (and the garbage made since k0: the collector is stopped) to a piece.
function perf.since(key, t0, k0)
    if (t0 ~= nil) then
        perf.add(key, (clock.now() - t0) * 1000, 1, k0 and (collectgarbage('count') - k0));
    end
end

-- A piece's garbage a frame, as said after its time.
local function kb_of(key, f)
    local kb = S.kb[key];
    if (kb == nil or kb / f < 0.05) then
        return '';
    end
    return ('  [%.1f KB]'):format(kb / f);
end

local PIECES = {
    { 'present',  'facelift each frame (all below)' },
    { 'names',    '  names over characters', },
    { 'names.read', '    reading the characters' },
    { 'names.covered', '    under menus' },
    { 'names.world', '    laid out for the world' },
    { 'names.over', '    drawn over everything' },
    { 'windows',  '  windows (each below)' },
    { 'radar',    '  compass' },
    { 'config',   '  config window' },
    { 'other',    '  the rest' },
    { 'scenes',   'scene start/end hooks (names in the world)' },
    { 'depth.draw', '  names drawn into the world' },
};

local function report(say, now)
    local f = math.max(1, S.frames);
    local frame_ms = S.gap / f * 1000;
    local m = S.ms;
    m.other = math.max(0, (m.present or 0) - (m.names or 0) - (m.windows or 0) - (m.radar or 0) - (m.config or 0));
    local total = (m.present or 0) + (m.scenes or 0);
    say(('Perf over %d frames: %.0f fps, a frame %.2f ms on average, the longest %.1f ms.'):format(S.frames, frame_ms > 0 and 1000 / frame_ms or 0, frame_ms, S.worst * 1000));
    say(('facelift: %.2f ms a frame (%.0f%% of the frame).'):format(total / f, frame_ms > 0 and 100 * total / f / frame_ms or 0));
    for _, p in ipairs(PIECES) do
        local v = m[p[1]];
        if (v ~= nil and v / f >= 0.005) then
            local calls = S.calls[p[1]];
            local extra = (p[1] == 'scenes' and calls ~= nil) and ('  (%.0f calls a frame)'):format(calls / f) or '';
            say(('%s: %.2f ms%s%s'):format(p[2], v / f, kb_of(p[1], f), extra));
        end
    end
    -- The windows, slowest first.
    local ws = {};
    for k, v in pairs(m) do
        if (k:sub(1, 2) == 'w:') then
            ws[#ws + 1] = { k:sub(3), v / f, kb_of(k, f) };
        end
    end
    table.sort(ws, function (a, b) return a[2] > b[2]; end);
    for i = 1, math.min(10, #ws) do
        if (ws[i][2] >= 0.005) then
            say(('    window %s: %.2f ms%s'):format(ws[i][1], ws[i][2], ws[i][3]));
        end
    end
    -- The garbage: counted with the collector stopped, then one full collection timed.
    local kb = collectgarbage('count') - (S.mem0 or 0);
    collectgarbage('restart');
    local g0 = clock.now();
    collectgarbage('collect');
    local gc = (clock.now() - g0) * 1000;
    say(('Lua garbage (the [KB] above: what each piece made a frame): %.1f KB a frame (%.1f MB a minute at this rate); a full collection took %.1f ms (spread over frames in normal play).'):format(
        kb / f, kb / 1024 * 60 / math.max(0.001, now - S.t0), gc));
end

-- At the start of each d3d_present: counts the frame; says the report when the sample's done.
function perf.frame(say)
    if (S == nil) then
        return;
    end
    local now = clock.now();
    if (S.t0 == nil) then
        -- The first frame: the counting starts (the garbage collected first, then the collector stopped).
        collectgarbage('collect');
        collectgarbage('stop');
        S.mem0 = collectgarbage('count');
        S.t0, S.last = now, now;
        S.ms, S.calls, S.kb = {}, {}, {};
        return;
    end
    local gap = now - S.last;
    S.gap, S.worst, S.last = S.gap + gap, math.max(S.worst, gap), now;
    S.frames = S.frames + 1;
    -- (ended early past 48 MB of garbage: FFXI is a 32-bit process, and the collector is stopped)
    if (now - S.t0 >= S.secs or collectgarbage('count') - S.mem0 > 48 * 1024) then
        local ok, err = pcall(report, say, now);
        if (not ok) then
            collectgarbage('restart');
            say('Perf: ' .. tostring(err));
        end
        S, perf.on = nil, false;
    end
end

-- Unloading or stopping mid-sample: the collector back on.
function perf.stop()
    if (S ~= nil) then
        collectgarbage('restart');
    end
    S, perf.on = nil, false;
end

return perf;
