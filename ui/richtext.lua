--[[
* facelift - ui/richtext: the game's text as the game shows it, wherever facelift draws it (item
* info, the help bar...): decoded by core/gametext, and with the game's element icons (a resistance:
* [light]-5) laid out word by word, each icon as tall as the text (ui/gameicons), or the element's
* name when the icons can't be made.
--]]

local imgui     = require('ui.gui');
local gametext  = require('core.gametext');
local gameicons = require('ui.gameicons');

local rt = {};

local size = { 0, 0 };

--[[
* Runs (core/gametext) in colour col, wrapped at w pixels from where they start: words placed one
* by one, a line break where the next doesn't fit, nothing between an icon and the characters
* touching it.
--]]
function rt.draw(runs, col, w)
    local tex, uv = gameicons.get();
    local s = imgui.GetFontSize();
    local x, fresh, glue = 0, true, false;
    local function place(tw)
        if (not fresh) then
            if (not glue and x + tw > w) then
                x = 0;
            else
                imgui.SameLine(0, 0);
            end
        end
        fresh = false;
        x = x + tw;
    end
    for _, r in ipairs(runs) do
        if (r == false) then
            if (fresh) then
                imgui.NewLine();
            end
            x, fresh, glue = 0, true, false;
        elseif (type(r) == 'number') then
            if (tex ~= nil and uv[r] ~= nil) then
                place(s);
                size[1], size[2] = s, s;
                imgui.Image(tex, size, uv[r][1], uv[r][2]);
            else
                local name = gametext.ELEMENTS[r];
                place((imgui.CalcTextSize(name)));
                imgui.TextColored(col, name);
            end
            glue = true;
        else
            for word in r:gmatch('%S*%s*') do
                if (word ~= '') then
                    place((imgui.CalcTextSize(word)));
                    imgui.TextColored(col, word);
                    glue = false;
                end
            end
            glue = r:find('%S$') ~= nil; -- an icon right after this word stays with it
        end
    end
end

--[[
* The game's string raw in colour col: plain text as one item (wrapped by the wrap pos already
* pushed), or with icons laid out by rt.draw within w pixels (default: to the window's edge).
--]]
function rt.text(raw, col, w)
    local runs = gametext.runs(raw);
    if (runs.icons == 0) then
        imgui.TextColored(col, runs.text);
    else
        rt.draw(runs, col, w or imgui.GetContentRegionAvail());
    end
end

return rt;
