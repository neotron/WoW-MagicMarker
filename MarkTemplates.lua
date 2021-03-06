--[[
**********************************************************************
MagicMarker - your best friend for raid marking. See README.txt for
more details.
**********************************************************************
This file is part of MagicMarker, a World of Warcraft Addon

MagicMarker is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MagicMarker is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with MagicMarker.  If not, see <http://www.gnu.org/licenses/>.
**********************************************************************
]]

local MagicMarker = LibStub("AceAddon-3.0"):GetAddon("MagicMarker")
local L = LibStub("AceLocale-3.0"):GetLocale("MagicMarker", false)
local UnitClass = UnitClass
local GetRaidTargetIndex = GetRaidTargetIndex
local SetRaidTarget = SetRaidTarget


local decursers = { MAGE = 1000, DRUID = 1000 }
local shamans = { SHAMAN = 500 }
local mages = { MAGE = 1000 }
local function MarkIfClassHelper(self, unit, classes, class, usedMarks)
   if not class then
      _,class = UnitClass(unit)
   end

   if GetRaidTargetIndex(unit) then
      return
   end
   
   if class and classes[class] then
      for id = 1, 8 do 
	 if not usedMarks[id] then
	    SetRaidTarget(unit, id)
	    usedMarks[id] = unit
	    if self.hasDebug then self:debug("Marking "..unit.." with target "..id) end
	    return true
	 end
      end
   end
end

MagicMarker.MarkTemplates = {
   decursers  = {
      func = function (self, unit, class, usedMarks) MarkIfClassHelper(self, unit, decursers, class, usedMarks) end,
      desc = L["Mark all mages and druids in the raid"],
   },
   shamans = {
      func = function (self, unit, class, usedMarks) MarkIfClassHelper(self, unit, shamans, class, usedMarks) end,
      desc = L["Mark all shamans in the raid"],
      
   },
   archimonde = {
      desc = L["Mark the decursers followed by the shamans"],
      order = 1,
   },
   arch = {
      desc = L["Alias for archimonde"],
      order = 2,
   }
}
