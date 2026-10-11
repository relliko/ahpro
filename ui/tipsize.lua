--[[
* facelift - ui/tipsize: the item tooltip's width, the same wherever facelift draws one (its own tooltip
* window, the auction house's item column), as the game keeps its tooltip one width across the
* interface: the game's (its iteminfo window, 366 UI px wide: data/menus_options.txt), and at least 300
* times the text size.
--]]

local tipsize = { GAME_W = 366 };

-- The tooltip window's width (screen px) at the game's UI scale and facelift's text size.
function tipsize.window(scale, fs)
    return math.max(tipsize.GAME_W * scale, 300 * fs);
end

-- What's inside it: less the windows' padding (12 a side: ui/theme).
function tipsize.content(scale, fs)
    return tipsize.window(scale, fs) - 24 * fs;
end

return tipsize;
