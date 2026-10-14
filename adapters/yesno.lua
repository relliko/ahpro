--[[
* facelift - adapters/yesno: the game's yes/no boxes (one class, vtable yesno.vtable: shopbuy and
* shopsell (Buy/Sell and Cancel), comyn (most questions), merityn, the revival boxes resyn*;
* client-notes, 'Yes/no boxes'). Handler (0x44): +0x14 the answer's callback (0: no question
* pending), +0x1C the question (char*, NULL: it's in the help line or the title), +0x34 the title,
* +0x39 Escape allowed now, +0x40 hold mode (answer by holding Enter; then the game's own box shows).
* The options are the menu's own (1 Yes, 2 No; the game's pictures: Sell, Cancel...), read as
* adapters/menuopts reads any menu's.
*
* Answered only as the keys answer: the cursor moved to the option (SetCursor), then Enter through the
* game's menu input, which runs the game's own callback; a click on Yes is the deliberate choice (the
* game asks nothing more for a buy, a sale, a drop...). Escape stays the game's key.
*
* Model: adapters/menuopts' model, and question (text or nil), title (text or nil), card (in a number
* box's place, as big as it: see below; nil otherwise).
--]]

local safemem  = require('core.safemem');
local sigs     = require('core.sigs');
local menus    = require('core.menus');
local game     = require('core.game');
local gametext = require('core.gametext');
local menuopts = require('adapters.menuopts');

local A = {
    sigs = { 'yesno.vtable', 'menu.input', 'menu.set_cursor' },
};

function A.new()
    local m = menuopts.new();
    m.question, m.title = nil, nil;
    return m;
end

-- A char* as text, kept per pointer and bytes.
local texts = {};
local function text(ptr)
    if (ptr == 0) then
        return nil;
    end
    local s = safemem.read(ptr, 200);
    local z = s ~= nil and s:find('\0', 1, true) or nil;
    if (z == nil or z == 1) then
        return nil;
    end
    s = s:sub(1, z - 1);
    local t = texts[s];
    if (t == nil) then
        t = gametext.text(s);
        texts[s] = t;
    end
    return t;
end

-- The handler's fields when it's a yes/no box with a question pending, else nil.
local function pending(h)
    local vt = sigs.get('yesno.vtable');
    local hd = h ~= nil and h ~= 0 and safemem.read(h, 0x44) or nil;
    if (hd == nil or vt == 0 or safemem.le32(hd, 0) ~= vt or safemem.le32(hd, 0x14) == 0) then
        return nil;
    end
    return hd;
end

--[[
* Questions that follow one of facelift's number boxes (the AH sale's Sell / Cancel after its price, a
* bid's question, a shop's Buy / Sell after the quantity box): the box's OK pressed in facelift
* (A.sent, from adapters/numberbox and adapters/itemctrl) or, by the game's own Enter, the box drawn
* just before. Such a question goes where that box was (the game puts it at its own place, small and
* well away), as one chain: a question straight after one there (a re-ask: a new menu object), or a
* few seconds after one there answered Yes (the AH sale's fee, asked once the server has answered),
* goes there too. With the yes/no window's 'big' option, a chain's question is drawn as big as the box
* was (m.card; panes/yesno). An AH sale's chain started with the price history up keeps that history
* up meanwhile (A.sale: windows/ahhisto lingers).
--]]
local BOXES = { pricebox = true, qtybox = true }; -- facelift's number boxes a question can follow
local sent = nil;  -- the last box OK'd in facelift: { box, at, x, y, w (screen px), about, histo }
local chain = nil; -- the questions in a box's place: { x, y, w (UI px), about, sale, histo, seen, cursor, menu }
local spots = {};  -- [menu object] = { chain (or false: where the game has it), seen }
local WAIT = 3;    -- seconds a Yes on the sale's Sell waits for the server's next question

-- A number box's OK pressed in facelift (box: its window id; about: an AH bid's or sale's item and
-- price, { id, stack, value, name, sale }). A Cancel isn't one.
function A.sent(box, about)
    local rt = require('windows.runtime');
    local x, y, w = rt.recent(box, 2);
    if (x == nil) then
        return;
    end
    sent = { box = box, at = os.clock(), x = x, y = y, w = w, about = about,
             histo = about ~= nil and about.sale and rt.up('ahhisto') };
end

-- The newest frame any of the boxes was drawn in, and the one drawn within the last 90 frames (its
-- rect, screen px), if any.
local function boxes()
    local rt = require('windows.runtime');
    local newest, bx, by, bw, best = -1, nil, nil, nil, nil;
    for id in pairs(BOXES) do
        local t = rt.by_id[id];
        if (t ~= nil) then
            newest = math.max(newest, t.drawn);
            local x, y, w = rt.recent(id, 90);
            if (x ~= nil and (best == nil or t.drawn > best)) then
                bx, by, bw, best = x, y, w, t.drawn;
            end
        end
    end
    return newest, bx, by, bw;
end

-- Where a new question goes: its chain, or false (where the game has it).
local function decide(name)
    local rt = require('windows.runtime');
    local k = rt.scale or 0;
    local now = os.clock();
    if (k <= 0) then
        return false;
    end
    local newest, bx, by, bw = boxes();
    if (sent ~= nil and now - sent.at < 3) then
        local s = sent;
        sent = nil; -- (one question per OK; any after it come by the chain)
        chain = { x = s.x / k, y = s.y / k, w = s.w / k, about = s.about, histo = s.histo,
                  sale = s.about ~= nil and s.about.sale and s.about or nil };
    elseif (chain ~= nil and newest <= chain.mark
            and (now - chain.seen < 1.5 or (chain.menu == 'shopsell' and chain.cursor == 1 and now - chain.seen < WAIT + 2))) then
        -- (the chain's next question, no box up since: a re-ask, or the server's after Sell)
    elseif (bx ~= nil) then
        chain = { x = bx / k, y = by / k, w = bw / k }; -- (the box up just before, answered by the game's own Enter)
    else
        return false;
    end
    chain.seen, chain.cursor, chain.menu, chain.mark = now, 0, name, newest;
    return chain;
end

-- The spot of the question in menu obj (decided when it's new: the object's memory is reused for
-- the next one), kept up to date.
local function spot_of(obj, name)
    local spot = spots[obj];
    local now = os.clock();
    if (spot == nil or now - spot.seen > 0.5) then
        spot = { chain = decide(name), born = now };
        spots[obj] = spot;
    end
    spot.seen = now;
    if (spot.chain) then
        spot.chain.seen, spot.chain.menu, spot.chain.mark = now, name, (boxes());
    end
    return spot;
end

--[[
* The AH sale's chain while the price history it started with is to stay up: one of its questions is
* up now, or the sale's Sell / Cancel was just answered Sell and the server's question (the fee) is on
* its way. nil otherwise.
--]]
function A.sale()
    -- Only while facelift's yes/no window asks it (where the price box was): the game's own box (that
    -- window off; ahpro, which has none; a box it can't read) is at the game's place, which the history
    -- would cover. Its first frames count: the yes/no window comes after the history in windows/init.
    local rt = require('windows.runtime');
    local yw = rt.by_id.yesno;
    if (yw == nil or not yw.enabled) then
        return nil;
    end
    local f = menus.focused();
    if (f ~= nil and pending(f.handler) ~= nil) then
        local spot = spot_of(f.obj, f.name);
        local c = spot.chain;
        if (c and c.sale ~= nil and c.histo and (rt.up('yesno') or os.clock() - spot.born < 0.25)) then
            return c;
        end
        return nil;
    end
    local c = chain;
    if (c ~= nil and c.sale ~= nil and c.histo and c.menu == 'shopsell' and c.cursor == 1
            and os.clock() - c.seen < WAIT and menus.find('auc1') ~= nil) then
        return c;
    end
    return nil;
end

-- The labels of a box's two answers, by its menu (the game's pictures say the same).
local LABELS = { shopsell = { 'Sell', 'Cancel' }, shopbuy = { 'Buy', 'Cancel' } };
local YES_NO = { 'Yes', 'No' };

--[[
* What a question in its box's place says, drawn as big as that box (panes/yesno): { w (UI px),
* title, text, yes, no }. An AH bid's or sale's: the item over it, and for the sale's Sell / Cancel
* (the game asks it with no words: 'Sell this merchandise?' is in the help line) the price; else the
* game's question, or its help line.
--]]
local cards = {}; -- [menu object] = the card (kept: it only changes with the question)
local function card(p, m, c)
    local t = cards[p.obj];
    local key = ('%s/%s/%s'):format(tostring(p.menu), tostring(m.question), tostring(m.title));
    if (t ~= nil and t.key == key and t.chain == c) then
        return t;
    end
    local labels = LABELS[p.menu] or YES_NO;
    t = { key = key, chain = c, w = c.w, yes = labels[1], no = labels[2], title = m.title, text = m.question };
    if (c.about ~= nil) then
        t.title = c.about.name;
        if (t.text == nil and c.sale ~= nil and p.menu == 'shopsell') then
            t.text = ('Sell for %s gil?'):format(require('ui.fmt').commas(c.sale.value));
        end
    end
    if (t.text == nil) then
        local hb = require('windows.runtime').by_id.helpbar;
        local help = hb ~= nil and hb.parts[1] ~= nil and hb.parts[1].model.help or nil;
        t.text = (help ~= nil and help ~= '') and help or nil;
    end
    cards[p.obj] = t;
    return t;
end

function A.read(p, m)
    local hd = pending(p.handler);
    if (hd == nil or safemem.le32(hd, 0x40) ~= 0) then
        return false; -- not a question, or answered by holding Enter: the game's own box
    end
    if (not menuopts.read_options(p, m, false)) then
        return false;
    end
    m.question, m.title = text(safemem.le32(hd, 0x1C)), text(safemem.le32(hd, 0x34));
    if (m.question ~= nil and m.wx ~= nil) then
        -- The box and the window take in the question too: the game writes it across its window
        -- from the top left, wider than the options (they'd cut it off).
        local left, top, right = math.floor(m.wx) - 2, math.floor(m.wy) - 2, math.ceil(m.wx + m.ww) + 2;
        local function widen(x, y, w, h)
            local x1, y1 = x + w, y + h;
            x, y = math.min(x, left), math.min(y, top);
            x1 = math.max(x1, right);
            return x, y, x1 - x, y1 - y;
        end
        m.bx, m.by, m.bw, m.bh = widen(m.bx, m.by, m.bw, m.bh);
        m.x, m.y, m.w, m.h = widen(m.x, m.y, m.w, m.h);
    end
    -- A question following one of facelift's number boxes: where that box was (its chain), as big as
    -- it with the yes/no window's 'big' option (m.card), else the game's box moved there.
    local c = spot_of(p.obj, p.menu).chain;
    m.card = nil;
    if (c) then
        c.cursor = m.cursor;
        local yw = require('windows.runtime').by_id.yesno;
        if (yw ~= nil and yw.opt('big') == 1) then
            m.card = card(p, m, c);
            m.x, m.y, m.w, m.h = c.x, c.y, c.w, m.card.h or c.w / 3;
        else
            local dx = c.x - (m.bw > 0 and m.bx or m.x);
            local dy = c.y - (m.bw > 0 and m.by or m.y);
            m.x, m.y, m.bx, m.by = m.x + dx, m.y + dy, m.bx + dx, m.by + dy;
            if (m.wx ~= nil) then
                m.wx, m.wy = m.wx + dx, m.wy + dy;
            end
            for i = 1, m.n or #m.opts do
                local o = m.opts[i];
                if (o ~= nil) then
                    o.x, o.y = o.x + dx, o.y + dy;
                end
            end
        end
    end
    return true;
end

A.actions = {
    -- The game's cursor to option n (1 Yes, 2 No): Left / Right on the side-by-side buttons.
    point = function (p, m, n)
        if (pending(p.handler) ~= nil and (n == 1 or n == 2)) then
            game.call('menu.set_cursor', p.obj, n);
        end
    end,
    -- Option n (1 Yes, 2 No): the cursor there, then the game's Enter.
    select = function (p, m, n)
        if (pending(p.handler) == nil or (n ~= 1 and n ~= 2)) then
            return;
        end
        if (game.call('menu.set_cursor', p.obj, n) and menus.cursor(p.obj) == n) then
            local spot = spots[p.obj];
            if (spot ~= nil and spot.chain) then
                spot.chain.cursor = n; -- (how it was answered: a Yes may bring the server's next question)
            end
            game.call('menu.input', p.obj, 5);
        end
    end,
};

return A;
