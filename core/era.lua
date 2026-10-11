--[[
* facelift - core/era: what an era server (content up to Abyssea, June 2010) has no use for, hidden
* while the switch is on (settings era, General; on by default): only what can't be reached or had
* there. Kept: the Mog House's storages (private servers use them), Currencies, Linkshell 2,
* Synthesis, Request, Play Time, the party's quartermaster marks; anything that shows only when you
* already have it (wardrobe marks, item levels, trusts in the party...).
*
* Option menus (adapters/menuopts): the options by the menu's option number (data/menus_options.txt;
* option numbers aren't screen order). The command menu's by command id instead (its options change
* with the situation: word [h + 0x1C + 2(i-1)], 25 Trust = picture keytops3 #505).
*   statcom2  12 Master Levels, 10 Currencies 2, 11 Unity, 8 Job Points, 13 Alter Ego Points
*   mgcmenu   7 Geomancy, 8 Trust
*   abimenu   6 Mount            abiselec  5 Mount
*   missionm  7 Adoulin, 6 Add-ons
* Elsewhere: the Status page's 'ILv / Su' line (panes/persona), the quest menu's Records of Eminence,
* Objective List and Vana'Bout rows (adapters/logs), the chat box's Assist 1, Assist 2 and Unity tabs
* (core/chatlog), and the game's full log's filters for them (its F key skips them: adapters/chatlog).
--]]

local era = {
    on = true, -- (settings.era: set every frame)
};

era.OPTIONS = {
    statcom2 = { [8] = true, [10] = true, [11] = true, [12] = true, [13] = true },
    mgcmenu  = { [7] = true, [8] = true },
    abimenu  = { [6] = true },
    abiselec = { [5] = true },
    missionm = { [6] = true, [7] = true },
};
era.COMMANDS = { [25] = true }; -- the command menu (playermo), by command id
era.QUEST_ROWS = { [2] = true, [3] = true, [4] = true }; -- quest00 mode 0: RoE, Objective List, Vana'Bout
era.CHAT_TABS = { as1 = true, as2 = true, unity = true };
era.LOG_FILTERS = { [6] = true, [9] = true, [10] = true }; -- the full log's filter kinds for them (Unity, Assist 1, 2)

-- Whether menu's option n (its number) is hidden.
function era.option(menu, n)
    local t = era.on and era.OPTIONS[menu] or nil;
    return t ~= nil and t[n] == true;
end

-- Whether the command menu's command id is hidden.
function era.command(id)
    return era.on and era.COMMANDS[id] == true;
end

return era;
