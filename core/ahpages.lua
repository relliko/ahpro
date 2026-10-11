--[[
* facelift - core/ahpages: the auction house's Sales Status in pages, as Phoenix's server module
* ah_pagination gives it (its repo's modules/custom/cpp/ah_pagination.cpp): with more listings allowed
* than the client's 7, each Sales Status press shows the next 6 of yours (oldest first: ORDER BY id),
* the page kept per character until you zone, back to page 1 after an empty one; at most a press
* every 1.5 s. It says where it is in system lines, read here from the chat:
*   "You have N items listed for sale."               (the first press after zoning)
*   "No results for page: X of Y."                    (past the last page: page 1 follows)
*   "Current page: X of Y. Showing Z items."         (every press; Y is 99 with no listing limit)
* Without the module none of these come, and Sales Status is the game's one page of 7.
*
* State: active (a page line seen since load), total (N, when said), page, shown, wrapped (this page
* came after an empty one), serial (up by one for each page line).
--]]

local P = {
    active = false,
    total = nil,
    page = nil,
    shown = nil,
    wrapped = false,
    serial = 0,
    at = 0,
};

local empty = false; -- ("No results" just seen: the next page is page 1 again)

-- A chat line's text (raw, the game's bytes).
function P.text(raw)
    if (raw == nil or not raw:find('item', 1, true) and not raw:find('page', 1, true)) then
        return;
    end
    local n = raw:match('You have (%d+) items? listed for sale');
    if (n ~= nil) then
        P.active, P.total = true, tonumber(n);
        return;
    end
    if (raw:find('No results for page', 1, true)) then
        P.active, empty = true, true;
        return;
    end
    local x, z = raw:match('Current page: (%d+) of %d+%. Showing (%d+) items?');
    if (x ~= nil) then
        P.active = true;
        P.page, P.shown, P.wrapped = tonumber(x), tonumber(z), empty;
        empty = false;
        P.serial = P.serial + 1;
        P.at = os.clock();
    end
end

-- Forgets the count (zoning: the module starts again at page 1 and says the count again).
function P.zoned()
    P.total, P.page, P.shown, P.wrapped, empty = nil, nil, nil, false, false;
end

return P;
