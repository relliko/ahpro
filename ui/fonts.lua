--[[
* facelift - ui/fonts: the fonts facelift draws with, loaded into ImGui's atlas once each when the
* renderer can make glyphs at any size (ImGui 1.92's dynamic fonts), and taken out again on unload
* (the atlas is shared by every addon). A font file is one of facelift's own (fonts/: the game's
* bitmap fonts as TrueType, made from its data files by tools/ffxi_fonts.py), a path, or a file in
* Windows' fonts.
*
* The windows' text font (settings look.font, fonts.TEXT): ImGui's own, FFXI Text (the game's chat
* and menu font) or FFXI Text Pixel (the same as the game's exact pixels: sharpest at 16 px and its
* multiples, so its size goes in those steps). A change is made at the start of a frame, never while
* a window still uses the old font.
--]]

local bit = require('bit');
local gui = require('ui.gui');

local fonts = {
    win_dir = nil, -- Windows' fonts (default: %WINDIR%\Fonts\)
    own_dir = nil, -- facelift's own (default: its fonts folder)
    why = nil,     -- why the windows' text font isn't loaded, if it isn't
};

-- facelift's own fonts. step: drawn only at multiples of this size (px); italic: italic only.
fonts.OWN = {
    ['FFXI-Text.ttf']         = { name = 'FFXI Text' },
    ['FFXI-Text-Pixel.ttf']   = { name = 'FFXI Text Pixel', step = 16 },
    ['FFXI-Names-Italic.ttf'] = { name = 'FFXI Names', italic = true },
};

-- The windows' text fonts: the setting, the file (nil: ImGui's own), the label.
fonts.TEXT = {
    { 'imgui', nil, 'ImGui\'s own' },
    { 'ffxi', 'FFXI-Text.ttf', 'FFXI Text (the game\'s)' },
    { 'ffxi_pixel', 'FFXI-Text-Pixel.ttf', 'FFXI Text, exact pixels (the game\'s)' },
};

local function own_dir()
    if (fonts.own_dir ~= nil) then
        return fonts.own_dir;
    end
    local base = addon.path or ((AshitaCore:GetInstallPath() or '') .. 'addons\\' .. (addon.name or 'facelift'));
    if (not base:find('[/\\]$')) then
        base = base .. '\\';
    end
    return base .. 'fonts\\';
end

-- A font file's path: facelift's own from its fonts folder, a path as given, else Windows' fonts.
function fonts.path(file)
    if (fonts.OWN[file] ~= nil) then
        return own_dir() .. file;
    end
    if (file:find('[/\\]')) then
        return file;
    end
    return (fonts.win_dir or ((os.getenv('WINDIR') or 'C:\\Windows') .. '\\Fonts\\')) .. file;
end

-- Whether a font file is there (and not empty).
function fonts.has(file)
    local f = io.open(fonts.path(file), 'rb');
    if (f == nil) then
        return false;
    end
    local n = f:seek('end');
    f:close();
    return (n or 0) > 0;
end

-- Whether the renderer can take a new font now (ImGui 1.92's dynamic fonts).
function fonts.dynamic()
    local ok, r = pcall(function ()
        return bit.band(gui.GetIO().BackendFlags or 0, ImGuiBackendFlags_RendererHasTextures) ~= 0;
    end);
    return ok and r == true;
end

-- A font file in ImGui's atlas (made at size px; dynamic fonts draw sharp at any size), or nil.
function fonts.load(file, size)
    local f = nil;
    pcall(function ()
        if (fonts.dynamic() and fonts.has(file)) then
            f = gui.AddFontFromFileTTF(fonts.path(file), size);
        end
    end);
    return f or nil;
end

--[[
* Where a font's capitals are, from its file: the middle of a capital as a fraction of the size the
* font is drawn at, from the top of its line (ImGui sizes a font by ascent - descent, so that's
* (ascent - cap height / 2) / (ascent - descent): Segoe UI 0.55, FFXI Names 0.41). nil if the file
* can't be read; kept per file.
--]]
local caps = {};
function fonts.cap_middle(file)
    local v = caps[file];
    if (v ~= nil) then
        return v or nil;
    end
    caps[file] = false;
    local f = io.open(fonts.path(file), 'rb');
    if (f == nil) then
        return nil;
    end
    local ok, r = pcall(function ()
        local function u16(s, o) return s:byte(o + 1) * 256 + s:byte(o + 2); end
        local function s16(s, o) local x = u16(s, o); return x >= 0x8000 and x - 0x10000 or x; end
        local function u32(s, o) return u16(s, o) * 65536 + u16(s, o + 2); end
        local hdr = f:read(12);
        local n = u16(hdr, 4);
        local dir = f:read(16 * n);
        local at = {};
        for i = 0, n - 1 do
            at[dir:sub(i * 16 + 1, i * 16 + 4)] = u32(dir, i * 16 + 8);
        end
        if (at['hhea'] == nil or at['head'] == nil) then
            return nil;
        end
        f:seek('set', at['head']);
        local upm = u16(f:read(54), 18);
        f:seek('set', at['hhea']);
        local hh = f:read(8);
        local asc, desc = s16(hh, 4), s16(hh, 6);
        local cap = upm * 0.7;
        if (at['OS/2'] ~= nil) then
            f:seek('set', at['OS/2']);
            local os2 = f:read(90);
            if (os2 ~= nil and #os2 >= 90 and u16(os2, 0) >= 2 and s16(os2, 88) > 0) then
                cap = s16(os2, 88);
            end
        end
        if (asc - desc <= 0) then
            return nil;
        end
        return (asc - cap / 2) / (asc - desc);
    end);
    f:close();
    v = ok and r or nil;
    caps[file] = v or false;
    return v;
end

-- A loaded font out of the atlas.
function fonts.remove(f)
    if (f) then
        pcall(function () gui.GetIO().Fonts:RemoveFont(f); end);
    end
end

local text = { setting = nil, font = nil, step = nil };

--[[
* At the start of a frame: the windows' text font the setting asks for. Loaded once; until the
* renderer can take fonts it's tried again each frame, and a file that won't load leaves ImGui's own
* (fonts.why says why).
--]]
function fonts.frame(setting)
    setting = setting or 'imgui';
    if (setting == text.setting) then
        return;
    end
    local file = nil;
    for _, t in ipairs(fonts.TEXT) do
        if (t[1] == setting) then
            file = t[2];
        end
    end
    if (file ~= nil and not fonts.dynamic()) then
        fonts.why = 'this renderer can\'t load a font now';
        return;
    end
    fonts.remove(text.font);
    text.setting, text.font, text.step, fonts.why = setting, nil, nil, nil;
    if (file ~= nil) then
        text.font = fonts.load(file, 16);
        if (text.font) then
            text.step = fonts.OWN[file] and fonts.OWN[file].step or nil;
        else
            fonts.why = fonts.has(file) and 'it didn\'t load' or ('fonts\\' .. file .. ' is missing');
        end
    end
end

-- The windows' text font and the size to draw it at for size px (a pixel font's nearest step), or
-- nil (ImGui's own) and size.
function fonts.text(size)
    local f = text.font;
    if (not f) then
        return nil, size;
    end
    local step = text.step;
    if (step ~= nil) then
        size = step * math.max(1, math.floor(size / step + 0.5));
    end
    return f, size;
end

-- The windows' text font's label, for /facelift font.
function fonts.text_name()
    for _, t in ipairs(fonts.TEXT) do
        if (t[1] == text.setting and (t[2] == nil or text.font)) then
            return t[3];
        end
    end
    return fonts.TEXT[1][3];
end

-- On unload: the windows' text font out of the atlas.
function fonts.unload()
    fonts.remove(text.font);
    text.setting, text.font, text.step = nil, nil, nil;
end

return fonts;
