--[[
* The auction house's windows, in their order (a window docks beside ones before it): facelift's and
* ahpro's (the auction house on its own) alike, so the two always have the same.
--]]
return {
    require('windows.ahlist'),
    require('windows.ahsales'),
    require('windows.ahsellpick'),
    require('windows.ahhisto'),
    require('windows.ahprices'),
    require('windows.ahbrowse'),
    require('windows.pricebox'), -- after the windows it docks beside
    require('windows.ahitem'),
    require('windows.ahsaleitem'),
    require('windows.ahcats'),
};
