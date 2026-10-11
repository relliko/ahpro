--[[
* facelift - ui/fmt: numbers as the windows show them.
--]]

local fmt = {};

-- 1234567 -> '1,234,567'
function fmt.commas(n)
    local s = tostring(math.floor(n)):reverse():gsub('(%d%d%d)', '%1,'):reverse();
    return (s:gsub('^,', ''));
end

-- How long ago, from seconds: 'just now', '5 min ago', '3 h ago', '2 days ago', '4 months ago'.
function fmt.ago(s)
    if (s < 60) then
        return 'just now';
    elseif (s < 3600) then
        return ('%d min ago'):format(math.floor(s / 60));
    elseif (s < 86400) then
        return ('%d h ago'):format(math.floor(s / 3600));
    elseif (s < 86400 * 60) then
        local d = math.floor(s / 86400);
        return d == 1 and '1 day ago' or ('%d days ago'):format(d);
    end
    return ('%d months ago'):format(math.floor(s / (86400 * 30)));
end

return fmt;
