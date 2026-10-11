--[[
* facelift - ui/iteminfo: an item as the game's item tooltip shows it, line for line (core/itemview):
* its icon (in the game's tint), its name in the game's colour (green when worn), the Aug / Rare / Ex /
* Tmp / Alt badges at the top right (the game's own pictures), the type line ('[Ring]All Races '),
* the description, the Lv line, the augments, and the right-aligned lines (a charged item's
* '<6/7 0:00/[16:00:00, 0:15]>' in its colour, a signature, '<Item Level:119>'). Every facelift
* window that shows an item draws it with this. From the game's tooltip (src.handler: exactly what
* the game shows) or from the item's data (src.ext / bag / slot: its extra data and where it is).
* The game's strings go through core/gametext, the description through ui/richtext (its element icons).
--]]

local imgui    = require('ui.gui');
local theme    = require('ui.theme');
local icons    = require('ui.icons');
local gamepic  = require('ui.gamepic');
local gametext = require('core.gametext');
local itemview = require('core.itemview');
local richtext = require('ui.richtext');

local colors = {}; -- [the game's colour] = ImGui's
local function col(c)
    local k = colors[c];
    if (k == nil) then
        k = itemview.color(c);
        colors[c] = k;
    end
    return k;
end

local BADGE = theme.derive('LIGHT', 0.10);

-- The badges at the top right, ending at right (window x): the game's pictures, or their names.
local function badges(list, fs, right)
    local bs = math.floor(16 * fs + 0.5);
    local widths, total = {}, 0;
    for i, b in ipairs(list) do
        widths[i] = b.pic ~= nil and bs or (imgui.CalcTextSize(b.label) + 6 * fs);
        total = total + widths[i] + 2 * fs;
    end
    imgui.SameLine(math.max(imgui.GetCursorPosX(), right - total));
    local dl = imgui.GetWindowDrawList();
    for i, b in ipairs(list) do
        local x, y = imgui.GetCursorScreenPos();
        local drawn = false;
        if (b.pic ~= nil) then
            local x0, y0, x1, y1 = gamepic.bounds(b.pic);
            if (x0 ~= nil and y1 > y0) then
                local k = bs / math.max(y1 - y0, x1 - x0);
                drawn = gamepic.draw(dl, b.pic, x - x0 * k, y - y0 * k, k, 0xFFFFFFFF);
            end
        end
        if (drawn) then
            imgui.Dummy({ bs, bs });
        else
            dl:AddRectFilled({ x, y + 1 }, { x + widths[i], y + imgui.GetFontSize() }, imgui.GetColorU32(BADGE), theme.r(3 * fs));
            imgui.SetCursorScreenPos({ x + 3 * fs, y });
            imgui.TextColored(theme.DIM, b.label);
        end
        if (i < #list) then
            imgui.SameLine(0, 2 * fs);
        end
    end
end

--[[
* Draws item id. stack: show the item's stack size (a stack's listing); fs: text size; wrap: the
* right edge (window x; 0 = the window's edge); src: { handler = the game's tooltip handler } (what it
* shows), or { ext = the item's extra data (bytes), bag, slot }, or nil.
--]]
return function (id, stack, fs, wrap, src)
    local v = nil;
    if (src ~= nil and src.handler ~= nil) then
        v = itemview.from_tooltip(src.handler);
    end
    if (v == nil or v.id ~= id) then
        v = itemview.from_item(id, src ~= nil and src.ext or nil, src ~= nil and src.bag or nil, src ~= nil and src.slot or nil);
    end
    if (v == nil) then
        return;
    end
    local right = (wrap ~= nil and wrap > 0) and wrap or (imgui.GetCursorPosX() + imgui.GetContentRegionAvail());
    imgui.PushTextWrapPos(right);
    -- The header: the icon, the name and its badges, the type line.
    local tex = (v.tint ~= nil and v.tint ~= 0x80808080 and v.tint ~= 0 and icons.tinted(id, v.tint)) or icons.get(id);
    local sz = 32 * fs;
    if (tex ~= nil) then
        local x, y = imgui.GetCursorScreenPos();
        imgui.Image(tex, { sz, sz });
        local item = stack and AshitaCore:GetResourceManager():GetItemById(id) or nil;
        local n = v.stack or (item ~= nil and item.StackSize) or nil;
        if (n ~= nil and n > 1) then
            local t = ('%d'):format(n);
            imgui.GetWindowDrawList():AddText({ x + sz - imgui.CalcTextSize(t) - 1, y + sz - imgui.GetFontSize() },
                imgui.GetColorU32(col(itemview.YELLOW)), t);
        end
        imgui.SameLine();
    end
    imgui.BeginGroup();
    imgui.TextColored(col(v.name_color or itemview.WHITE), v.name);
    if (#v.badges > 0) then
        badges(v.badges, fs, right);
    end
    if (v.typeline ~= nil and v.typeline ~= '') then
        imgui.TextColored(col(itemview.WHITE), v.typeline);
    end
    imgui.EndGroup();
    -- The description (as the game wrapped it, when from the game), the Lv line, the augments.
    local w = right - imgui.GetCursorPosX();
    for _, line in ipairs(v.desc) do
        richtext.text(line, theme.TEXT, w);
    end
    if (v.lv ~= nil) then
        richtext.text(v.lv, theme.TEXT, w);
    end
    if (v.aug ~= nil) then
        for line in (v.aug .. '\n'):gmatch('([^\n]*)\n') do
            if (line ~= '') then
                richtext.text(line, col(itemview.AUG), w);
            end
        end
    end
    -- The right-aligned lines.
    for _, r in ipairs(v.right) do
        local t = r.utf8 and r.text or gametext.text(r.text);
        imgui.SetCursorPosX(math.max(imgui.GetCursorPosX(), right - imgui.CalcTextSize(t)));
        imgui.TextColored(col(r.color or itemview.WHITE), t);
    end
    imgui.PopTextWrapPos();
end
