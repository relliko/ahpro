# ahpro

The auction house for Final Fantasy XI, redone, as an Ashita v4 addon. It is facelift's auction house on its own: the same code, built from the same source.

- **One window** from the first menu on: Bid, Sell and Sales Status as tabs.
- **Categories as a tree**, each with the icon of an item the game lists there; Sort on every list.
- **Search listings** (Ctrl+F): type part of an item's name and pick it; it goes to its category the way a click there does, and puts the game's cursor on the item. Typing on a list filters it.
- **Prices seen**: every price history you open is kept, with a graph, the median and the last ten.
- **Sales Status in one list** on servers that page it (6 a press): it presses Sales Status again until it has every page.
- **The keyboard works as in the game**: arrow keys move the game's cursor, and the mouse is ignored until you click.

Each window is drawn over the game's own while that's open and works through it, exactly what its keys do. Unload ahpro, or turn a window off, and the game's own window is back.

No packets: ahpro never builds, sends or changes a packet. Anything sent is what the game's own window sends.

## Install

Unzip into Ashita's `addons` folder (it contains `ahpro/`), then `/addon load ahpro`.

If you also use facelift, you don't need ahpro: facelift has the same auction house, and ahpro steps aside while facelift is loaded.

## Commands

- `/ahpro` lists the windows and the commands.
- `/ahpro <window> on|off` (`ahone`, `auccats`, `auclist`, `prices`, `moneyctr`).
- `/ahpro theme glass|clean|guild|phoenix`, `/ahpro opacity <0.2-1>`, `/ahpro scale <0.5-4>`.
- `/ahpro era on|off` hides what an era server has no use for (the Geomancy category).
- `/ahpro errors`, `/ahpro retry`.

More settings are in the auction house's cog, at its top right.
