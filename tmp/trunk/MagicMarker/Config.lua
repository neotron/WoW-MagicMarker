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
WITHOUT ANY WARRANTY without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with MagicMarker.  If not, see <http://www.gnu.org/licenses/>.
**********************************************************************
]]

local CONFIG_VERSION = 7
local format = format
local sub = string.sub
local strmatch = strmatch
local tonumber = tonumber
local tolower = strlower
local UnitGUID = UnitGUID

local MagicMarker = LibStub("AceAddon-3.0"):GetAddon("MagicMarker")
local L = LibStub("AceLocale-3.0"):GetLocale("MagicMarker", false)
local R = LibStub("AceConfigRegistry-3.0")
local C = LibStub("AceConfigDialog-3.0")
local DBOpt = LibStub("AceDBOptions-3.0")

local BabbleZone = LibStub("LibBabble-Zone-3.0") 
local ZoneReverse = BabbleZone:GetReverseLookupTable()
local ZoneLookup  = BabbleZone:GetLookupTable()

local MobNotesDB
local options, cmdoptions, standardZoneOptions, standardMobOptions
BabbleZone = nil

local db

local mobdata

local configBuilt

-- Config UI name => ID
local CONFIG_MAP = {
}

-- ID => Config UI name
local ACT_LIST = { "TANK", "CC" }
local CC_LIST = { "00NONE", "SHEEP", "BANISH", "SHACKLE", "HIBERNATE", "TRAP", "KITE", "MC", "FEAR", "SAP", "ENSLAVE", "ROOT", "CYCLONE", "TURNUNDEAD", "SCAREBEAST", "SEDUCE", "TURNEVIL", "BLIND", "BURN" }
local PRI_LIST = { "P1", "P2", "P3", "P4", "P5", "P6" }
local CCPRI_LIST = { "P1", "P2", "P3", "P4", "P5", "P0" }
local RT_LIST =  { "Star",  "Circle",  "Diamond",  "Triangle",  "Moon",  "Square",  "Cross",  "Skull", "None" }
local ccDropdown, ccpriDropdown, priDropdown, catDropdown, raidIconDropdown, logLevelsDropdown

function MagicMarker:GetIconTexture(id)
   return string.format("Interface\\AddOns\\MagicMarker\\Textures\\%s.tga",
			sub(RT_LIST[id], 2))
end

-- KeybindHelper code from Xinhuan's addon IPopBar. Thanks for letting me use it! 
local KeybindHelper = {}
do
   local t = {}
   function KeybindHelper:MakeKeyBindingTable(...)
      for k in pairs(t) do t[k] = nil end
      for i = 1, select("#", ...) do
	 local key = select(i, ...)
	 if key ~= "" then
	    tinsert(t, key)
	 end
      end
      return t
   end
   
   function KeybindHelper:GetKeybind(info)
      return table.concat(self:MakeKeyBindingTable(GetBindingKey(info.arg)), ", ")
   end
   
   function KeybindHelper:SetKeybind(info, key)
      if key == "" then
	 local t = self:MakeKeyBindingTable(GetBindingKey(info.arg))
	 for i = 1, #t do
	    SetBinding(t[i])
	 end
      else
	 local oldAction = GetBindingAction(key)
	 if ( oldAction ~= "" and oldAction ~= info.arg ) then
	    MagicMarker:SetStatusText(KEY_UNBOUND_ERROR:format(GetBindingText(oldAction, "BINDING_NAME_")), true)
	 else
	    MagicMarker:SetStatusText(KEY_BOUND, true)
	 end

	 SetBinding(key, info.arg)
      end
      SaveBindings(GetCurrentBindingSet())
   end
end

local updateStatusTimer
function MagicMarker:SetStatusText(text, update)
   local frame = C.OpenFrames["Magic Marker"]
   if frame then
      frame:SetStatusText(text)
      if updateStatusTimer then self:CancelTimer(updateStatusTimer, true) end
      if update then
	 updateStatustimer = self:ScheduleTimer("SetStatusText", 10, string.format(L["Active profile: %s"], self.db:GetCurrentProfile()))
      else
	 updateStatustimer = false 
      end
   end
end

local function GetMobName(arg)
   return mobdata[ arg[#arg-2] ] and mobdata[ arg[#arg-2] ].mobs[ arg[#arg-1] ].name
end

local function GetMobDesc(arg)
   return mobdata[ arg[#arg-2] ] and mobdata[ arg[#arg-2] ].mobs[ arg[#arg-1] ].desc
end

local function GetMobNote(arg)
   local note, desc
   if not MobNotesDB then
      if _G.MobNotesDB then
	 MobNotesDB = _G.MobNotesDB
	 note = MobNotesDB[GetMobName(arg)]
      end
   end
   local desc = GetMobDesc(arg)
   if note and desc then
      return note .."\n"..desc
   elseif desc then
      return desc
   else
      return note or "N/A"
   end
end

function MagicMarker:NoMobNote(arg)
   return not (( MobNotesDB and MobNotesDB[GetMobName(arg)]) or GetMobDesc(arg))
end

function MagicMarker:ToggleConfigDialog()
   if C.OpenFrames["Magic Marker"] then
      C:Close("Magic Marker")
   else
      C:Open("Magic Marker")
      self:SetStatusText(string.format(L["Active profile: %s"], self.db:GetCurrentProfile()))
   end
end

do
   local temp, maxcc
   ccDropdown = {}
   priDropdown = {}
   ccpriDropdown = {}
   catDropdown = {}
   raidIconDropdown = {}
   logLevelsDropdown = {}

   CONFIG_MAP.NUMCC = #CC_LIST-1 
   maxcc = CONFIG_MAP.NUMCC + 1
   for num, txt in ipairs(CC_LIST) do
      if num <= maxcc then
	 ccDropdown[txt] = L[txt]
      end
      CONFIG_MAP[txt] = num
   end
   
   for num, txt in ipairs(PRI_LIST) do
      priDropdown[txt] = L[txt]
      CONFIG_MAP[txt] = num
   end

   for num, txt in ipairs(CCPRI_LIST) do
      ccpriDropdown[txt] = L[txt]
      CONFIG_MAP[txt] = num
   end

   for num, txt in ipairs(ACT_LIST) do
      catDropdown[txt] = L[txt]
      CONFIG_MAP[txt] = num
   end

   for num, txt in ipairs(RT_LIST) do
      temp = num..txt
      raidIconDropdown[temp] = L[txt]
      CONFIG_MAP[temp] = num
      RT_LIST[num] = temp
   end
   for logname,id in pairs(MagicMarker.logLevels) do
      logLevelsDropdown[id] = L[logname]
   end

   -- command line / dropdown options
   cmdoptions = {
      type = "group",
      name = L["Magic Marker"],
      handler = MagicMarker,
      args = {
	 versions = {
	    type = "execute",
	    name = L["Query raid for their MagicMarker versions."],
	    func = "QueryAddonVersions",
	 },
	 config = {
	    type = "execute",
	    name = L["Toggle configuration dialog"],
	    func = "ToggleConfigDialog",
	 },
	 toggle = {
	    type = "execute",
	    name = L["Toggle Magic Marker event handling"],
	    func = "ToggleMagicMarker",
	 },
	 tmpl = {
	    type = "group",
	    name = L["Raid group target templates"],
	    args = { }
	 },
	 about = {
	    type = "execute",
	    name = L["About Magic Marker"],
	    func = "AboutMagicMarker"
	 },
	 reset = {
	    type = "execute",
	    name = L["Reset raid icon cache"]..".",
	    func = "ResetMarkData", 
	 },
	 assignments = {
	    type = "execute",
	    name = L["Report the raid icon assignments to raid/party chat"]..".",
	    func = "ReportRaidMarks"
	 },
	 cache = {
	    type = "group",
	    name = L["Raid mark layout caching"],
	    args = {
	       save = {
		  type = "execute",
		  name = L["Save party/raid mark layout"]..".",
		  func = "CacheRaidMarks",
	       },
	       load = {
		  type = "execute",
		  name = L["Load party/raid mark layout"]..".",
		  func = "MarkRaidFromCache",
	       },
	    }
	 }
      }
   }

   options = { 
      type = "group", 
      name = L["Magic Marker"],
      childGroups = "tab",
      args = {
	 mobs = {
	    type = "group",
	    name = L["Mob Database"],
	    args = {}, 
	    order = 300,
	    cmdHidden = true, 
	    dropdownHidden = true, 
	 }, 
	 categories = {
	    childGroups = "tree",
	    type = "group",
	    name = L["Raid Target Settings"],
	    order = 1,
	    cmdHidden = true, 
	    dropdownHidden = true, 
	    args = {
	       cc = {
		  childGroups = "tree",
		  type = "group",
		  name = L["CC"],
		  order = 2,
		  args = {
		  }
	       }, 
	    }
	 }, 
	 ccprio = {
	    type = "group",
	    name = L["CC"] .." ".. L["Priority"],
	    order = 2,
	    cmdHidden = true, 
	    dropdownHidden = true,
	    handler = MagicMarker,
	    set = "SetCCPrio",
	    get = "GetCCPrio", 
	    args = {
	       addcc = {
		  type = "execute",
		  name = L["Add new crowd control"],
		  func = "AddNewCC",
		  order = 300,
		  hidden = "IsHiddenAddCC", 
	       },
	       ccheader = {
		  type = "header",
		  name = "",
		  order = 999
	       },
	       ccinfo = {
		  type = "description",
		  name = "",
		  order = 1000
	       },
	    }
	 }, 
	 options = {
	    type = "group",
	    name = L["Options"],
	    order = 0,
	    handler = MagicMarker,
	    set = "SetProfileParam",
	    get = "GetProfileParam",
	    cmdHidden = true, 
	    dropdownHidden = true, 
	    args = {
	       keybindings = {
		  type = "group",
		  name = L["Key Bindings"],
		  order = 100,
		  handler = KeybindHelper, 
		  get = "GetKeybind",
		  set = "SetKeybind",
		  args = {
		     bindingHeader = {
			type = "header",
			name = L["Key Bindings"],
			order = 100,
		     },
		  }
	       },
	       commsettings = {
		  type = "group",
		  name = L["Data Sharing"],
		  order = 2,
		  args = {
		     header =  {
			type = "header",
			name = L["Data Sharing"],
			order = 0,
		     },
		     acceptRaidMarks = {
			type = "toggle",
			width = "full",
			name = L["Accept raid mark broadcast messages"],
			desc = L["MARKBROADHELPTEXT"],
			order = 10,
		     },
		     acceptMobData = {
			type = "toggle",
			width = "full",
			name = L["Accept mobdata broadcast messages"],
			desc = L["MOBBROADHELPTEXT"],
			order = 15,
		     },
		     acceptCCPrio = {
			type = "toggle",
			width = "full",
			name = L["Accept CC priority broadcast messages"],
			desc = L["CCBROADHELPTEXT"],
			order = 10,
		     },
		     mobDataBehavior = {
			type = "select",
			name = L["Mobdata data import behavior"],
			desc = L["IMPORTHELPTEXT"],
			values = {
			   L["Merge - local priority"],
			   L["Merge - remote priority"],
			   L["Replace with remote data"],
			},
			disabled = function() return not db or not db.acceptMobData end
		     },
		     broadcastHeader = {
			type = "header",
			name = L["Data Broadcasting"],
			order = 200
		     },
		     broadcastTargets = {
			type = "execute",
			name = L["Broadcast raid target settings to the raid group."],
			order = 1000,
			width = "full", 
			func = "BroadcastRaidTargets",
			handler = MagicMarker,
			disabled = not MagicMarker:IsValidMarker()
		     },
		     broadcastMobs = {
			type = "execute",
			name = L["Broadcast all zone data to the raid group."],
			desc = L["BROADALLHELP"],
			order = 1001,
			width = "full", 
			func = "BroadcastAllZones",
			handler = MagicMarker,
			disabled = not MagicMarker:IsValidMarker()
		     },
		     broadcastCCPrio = {
			type = "execute",
			name = L["Broadcast crowd control priority settings to the raid group."],
			order = 1002,
			width = "full", 
			func = "BroadcastCCPriorities",
			handler = MagicMarker,
			disabled = not MagicMarker:IsValidMarker()
		     },
		  },		  
	       },
	       settings = { 
		  type = "group",
		  name = L["General Options"],
		  order = 1,
		  args = {
		     generalHeader = {
			type = "header",
			name = L["General Options"],
			order = 1,
		     },
		     logLevel = {
			type = "select",
			name = L["Log level"],
			desc = L["LOGLEVELHELP"],
			values = logLevelsDropdown,
			order = 2,
		     },
		     autolearncc = {
			name = L["Auto learn CC"],
			desc = L["CCAUTOHELPTEXT"], 
			type = "toggle",
			order = 70,
		     },
		     minTankTargets = {
			name = L["Minimum # of tank targets"],
			desc = L["MINTANKHELP"], 
			type = "range",
			min = 1, max = 8,
			step = 1,
			order = 50,
			disabled = function() return not db.alphasystem end
		     },
		     alphasystem = {
			name = L["New marking system"],
			desc = L["NEWMARKHELP"], 
			type = "toggle",
			order = 49
		     },
		     modifier = {
			name = L["Smart Mark Modifier"],
			desc = L["SMARTMARKMODHELP"], 
			type = "select",
			order = 20,
			disabled = function() return GetBindingKey("MAGICMARKSMARTMARK") ~= nil end, 
			values = {
			   ALT = L["Alt"],
			   SHIFT = L["Shift"],
			   CTRL = L["Control"],
			}
		     },
		     markHeader = {
			type = "header",
			name = L["Marking Behavior"],
			order = 100,
		     },
		     honorMarks = {
			name = L["Honor pre-existing raid icons"],
			desc = L["HONORHELPTEXT"], 
			type = "toggle",
			order = 110,
			width = "full",
		     },
		     honorRaidMarks = {
			name = L["Preserve raid group icons"],
			desc = L["NOREUSEHELPTEXT"], 
			type = "toggle",
			order = 120,
			width = "full",
		     },
		     battleMarking = {
			name = L["Enable target re-prioritization during combat"],
			desc = L["INCOMBATHELPTEXT"], 
			type = "toggle",
			order = 130,
			width = "full",
		     },
		     resetRaidIcons = {
			name = L["Reset raid icons when resetting the cache"],
			desc = L["RESETICONHELPTEXT"], 
			type = "toggle",
			order = 130,
			width = "full",
		     },
		  },
	       },
	    },
	 },
      }
   }
   
   standardZoneOptions = {
      optionHeader = {
	 type = "header",
	 name = L["Zone Options"],
	 order = 1
      },
      targetMark = {
	 width = "full",
	 type = "toggle",
	 name = L["Enable auto-marking on target change"],
	 handler = MagicMarker,
	 set = "SetZoneConfig",
	 get = "GetZoneConfig",
	 order = 20,
      },
      mm = {
	 width = "full",
	 type = "toggle",
	 name = L["Enable Magic Marker in this zone"],
	 handler = MagicMarker,
	 set = "SetZoneConfig",
	 get = "GetZoneConfig",
	 order = 10,
      },
      broadcastMobs = {
	 type = "execute",
	 name = L["Broadcast zone data to the raid group."],
	 order = 1001,
	 width = "full", 
	 func = function(var) MagicMarker:BroadcastZoneData(var[#var-1]) end,
	 disabled = not MagicMarker:IsValidMarker()
      },
      deletehdr = {
	 type = "header",
	 name = "",
	 order = 99
      }, 
   }
   standardMobOptions = {
      header = {
	 name = GetMobName,
	 type = "header",
	 order = 0
      },
      priority = {
	 name = L["TANK"].." ".. L["Priority"],
	 type = "select",
	 values = priDropdown, 
	 order = 2,
      },
      ccpriority = {
	 name = L["CC"].." "..L["Priority"],
	 type = "select",
	 values = ccpriDropdown, 
	 order = 3,
	 disabled = "IsIgnored",
      },
      category = {
	 name = L["Category"],
	 type = "select",
	 values = catDropdown, 
	 order = 4,
	 disabled = "IsIgnored",
      },
      ccnum = {
	 name = L["Max # to Crowd Control"],
	 desc = L["MAXCCHELP"], 
	 type = "range",
	 min = 1, max = 8,
	 step = 1, 
	 order = 4,
	 hidden = "IsIgnoredCC",
      },
      ccheader = {
	 name = L["CC"].." "..L["Config"], 
	 type = "header",
	 disabled = "IsIgnoredCC",
	 order = 40
      },
      ccinfo = {
	 type = "description",
	 name = L["CCHELPTEXT"],
	 order = 50,
	 disabled = "IsIgnoredCC",
      }, 
      mobnotes = {
	 name = GetMobNote, 
	 type = "description", 
	 order = 20,
	 hidden = "NoMobNote",
      },
      mobnoteheader = {
	 name = L["Mob Notes"],
	 type = "header", 
	 order = 15,
	 hidden = "NoMobNote",
      },
      deletehdr = {
	 type = "header",
	 name = "",
	 order = 10000
      },
      ccopt = {
	 type = "multiselect",
	 name = "",
	 order = 51,
	 disabled = "IsIgnoredCC",
	 values = ccDropdown,
      }
   }
   
   for num = 1,CONFIG_MAP.NUMCC do
      options.args.ccprio.args["ccopt"..num] = {
	 name = string.format("%s #%d", L["CC"], num), 
	 type = "select",
	 values = ccDropdown,
	 order = 100+num,
	 hidden = "IsHiddenCC",
      }
   end
end

function MagicMarker:SetProfileParam(var, value)
   local varName = var[#var]
   db[varName] = value
   if self.spam then 
      self:spam("Setting parameter %s to %s.", varName, tostring(value))
   end

   if varName == "logLevel" then
      self:SetLogLevel(value)
   end
end

function MagicMarker:GetProfileParam(var) 
   local varName = var[#var]
   if self.spam then
      self:spam("Getting parameter %s as %s.", varName, tostring(db[varName]))
   end
   return db[varName]
end

function MagicMarker:GetMarkForCategory(category)
   if category == 1 then
      return db.targetdata.TANK or {}
   end
   return db.targetdata[ CC_LIST[category] ] or {}
end

function MagicMarker:IsUnitIgnored(pri)
   return pri == CONFIG_MAP.P6
end

local function getID(value)
   return tonumber(strmatch(value, "%d+"))
end

local function uniqList(list, id, newValue, empty, max)
   local addEmpty = false
   list[id] = newValue

   if id == #list then
      for iter = 1,id-1 do
	 if list[iter] == value then
	    addEmpty = true
	 end
      end
   end
   
   local currentPos = 1
   local seen_value = { empty = true }
   
   for iter = 1,max do
      if list[iter] and not seen_value[ list[iter] ] then
	 list[currentPos] = list[iter]
	 currentPos = currentPos+1
	 seen_value[ list[iter] ] = true
      end
   end
   if addEmpty then
      list[currentPos] = empty
      currentPos = currentPos + 1
   end
   for iter = currentPos, max do
      list[iter] = nil
   end
   return list
end
   
function MagicMarker:SetRaidTargetConfig(info, value)
   local type = info[#info-1]
   local id = getID(info[#info])
   value = CONFIG_MAP[value]
   db.targetdata[type] = uniqList(db.targetdata[type] or {}, id, value, 9, 8)
end

function MagicMarker:GetRaidTargetConfig(info)
   local type = info[#info-1]
   local id = getID(info[#info]) or 9
   if not db.targetdata[type] then
      return nil
   end
   return RT_LIST[ db.targetdata[type][id] ]
end

function MagicMarker:GetCCPrio(info)
   local var = info[#info]
   local value = CC_LIST[ db.ccprio[getID(var)] or 1 ]
   if value == CC_LIST['00NONE'] then
      value = nil
   end
   if self.spam then self:spam("Get %s as %s", var, tostring(value)) end
   return value
end

function MagicMarker:SetCCPrio(info, value)
   local var = info[#info]
   db.ccprio = uniqList(db.ccprio or {}, getID(var), CONFIG_MAP[value], 1, CONFIG_MAP.NUMCC)
   self:UpdateUsedCCMethods()
   if self.spam then self:spam("Set %s to %s", var, tostring(value)) end
end

function MagicMarker:UpdateUsedCCMethods()
   local unused = L["Unused Crowd Control Methods"]
   local used = {}
   local sorted = {}
   local first = true
   if db.ccprio then
      for _,id in pairs(db.ccprio) do
	 used[id] = true
      end
   end

   for id = 2, CONFIG_MAP.NUMCC+1 do 
      if not used[id] then
	 sorted[#sorted+1] = L[CC_LIST[id]]
      end
   end
   table.sort(sorted)
   
   if next(sorted) then
      for id = 1, #sorted do
	 if first then
	    unused = unused .. ": "..sorted[id]
	    first = false
	 else
	    unused = unused .. ", "..sorted[id]
	 end
      end
      options.args.ccprio.args.ccinfo.name = unused
   else
      options.args.ccprio.args.ccinfo.name = ""
   end
end

function MagicMarker:SetMobConfig(info, value, state)
   local var = info[#info]
   local mob = info[#info-1]
   local region = info[#info-2]
   if var ~= "ccnum" then
      value = CONFIG_MAP[value]
   end      
   if var == "ccopt" then
      if value == CONFIG_MAP['00NONE'] then
	 mobdata[region].mobs[mob].ccopt = nil
      else
	 local ccopt = mobdata[region].mobs[mob].ccopt or {}

	 ccopt[value] = state or nil
	 if value == CONFIG_MAP.TURNUNDEAD then
	    -- If turn undead works / doesn't work, so does turn evil
	    ccopt[CONFIG_MAP.TURNEVIL] = state or nil
	 end

	    	 
	 if not next(ccopt) then
	    mobdata[region].mobs[mob].ccopt = nil
	 else
	    mobdata[region].mobs[mob].ccopt = ccopt
	 end
      end
      if self.spam then self:spam("|cffffff00SetMobConfig:|r %s/%s/%s[%s] => %s", region, mob, var, CC_LIST[value], tostring(state)) end
   else
      mobdata[region].mobs[mob][var] = value
      if self.spam then self:spam("|cffffff00SetMobConfig:|r %s/%s/%s => %s", region, mob, var, tostring(value)) end
   end
   
   if mobdata[region].mobs[mob].new then
      mobdata[region].mobs[mob].new = nil
      -- Remove the "new" mark
      options.args.mobs.args[region].plugins.mobList[mob].name = 
	 mobdata[region].mobs[mob].name
   end
   
end

function MagicMarker:GetMobConfig(info, key)
   local var = info[#info]
   local mob = info[#info-1]
   local region = info[#info-2]
   local value = mobdata[region].mobs[mob][var]

   if var == "ccopt" then
      if not value then
	 if key == '00NONE' then
	    value = true
	 end
      elseif value then
	 value = mobdata[region].mobs[mob].ccopt[CONFIG_MAP[key]]
      end
      if self.spam then self:spam("GetMobConfig: %s/%s/%s[%s] => %s", region, mob, var, key, tostring(value)) end
   else
      if var == "priority"  then
	 value = PRI_LIST[value or 1]
      elseif var == "ccpriority" then
	 value = CCPRI_LIST[value or 1]
      elseif var == "category" then
	 value = ACT_LIST[value or 1]
      end
      if self.spam then self:spam("GetMobConfig: %s/%s/%s => %s", region, mob, var, tostring(value)) end
   end
   return value
end

function MagicMarker:SetZoneConfig(info, value)
   local var = info[#info]
   local region = info[#info-1]
   mobdata[region][var] = value
   if self.spam then self:spam("Setting %s:%s to %s", region, var, tostring(value)) end
   if region == self:GetZoneName() then
      if var == "mm" then
	 self:ZoneChangedNewArea()
      elseif var == "targetMark" then
	 if value then
	    self:RegisterEvent("PLAYER_TARGET_CHANGED", "SmartMarkUnit", "target")
	 else
	    self:UnregisterEvent("PLAYER_TARGET_CHANGED")
	 end
      end
   end
end

function MagicMarker:GetZoneConfig(info)
   local var = info[#info]
   local region = info[#info-1]
   return mobdata[region][var]
end


function MagicMarker:IsIgnored(var)
   return MagicMarker:IsUnitIgnored(mobdata[var[#var-2]].mobs[var[#var-1]].priority)
end

function MagicMarker:IsIgnoredCC(var)
   local mob = mobdata[var[#var-2]].mobs[var[#var-1]]
   return mob.category == CONFIG_MAP.TANK or MagicMarker:IsUnitIgnored(mob.priority)
end

function MagicMarker:IsHiddenCC(var)
   local index = getID(var[#var])
   return not db.ccprio[index] 
end

function MagicMarker:IsHiddenRT(var)
   local index = getID(var[#var])
   local list = db.targetdata[var[#var-1]]
   return not list or not list[index] 
end

function MagicMarker:IsHiddenAddRT(var)
   local index = getID(var[#var])
   local list = db.targetdata[var[#var-1]] 
   if not list then return false end
   return list[#list] == 9 or #list == 8
end

function MagicMarker:IsHiddenAddCC(var)
   local cc = db.ccprio
   return cc[#cc] == 1 or #cc == CONFIG_MAP.NUMCC 
end
   
function MagicMarker:AddNewCC(var)
   local val = db.ccprio
   val[#val+1] = 1
end
   
function MagicMarker:AddNewRT(var)
   local val = db.targetdata[var[#var-1]] or {}
   val[#val+1] = 9
   db.targetdata[var[#var-1]] = val
end

function MagicMarker:GetZoneName(zone)
   local simple, heroic 
   if not zone then
      zone = GetRealZoneText()
   end
   zone = ZoneReverse[zone] or zone

   simple = self:SimplifyName(zone)
   if IsInInstance() and GetCurrentDungeonDifficulty() == 2 then
      simple = simple .. "Heroic"
      heroic = true
   end
   return simple, zone, heroic
end

local simpleNameCache = {}

function MagicMarker:SimplifyName(name)
   if not name then return "" end
   if not simpleNameCache[name] then
      simpleNameCache[name] = gsub(name, " ", "")
   end
   return simpleNameCache[name]
end

function MagicMarker:GetZoneInfo(hash)
   local new = 0
   local total = 0
   local ignored = 0
   local mobs = hash.mobs
   for mob,data in pairs(mobs) do
      if data.new then new = new + 1 end
      if data.priority == 6 then ignored = ignored + 1 end
      total = total + 1
   end
   if new > 0 then new = tostring(new) else new = L["None"] end

   local ret =  format(L["%s has a total of %d mobs.\n%s of these are newly discovered."],
			      hash.name, total, new)
   if ignored > 0 then
      ret = ret .. " "..format(L["\nOut of these mobs %d are ignored."], ignored)
   end
   return ret
end

local optionsCallout

local function white(str)
   return string.format("|cffffffff%s|r", str)
end
function MagicMarker:InsertNewUnit(uid, name, unit)
   local simpleName = self:SimplifyName(name)
   local simpleZone,zone, isHeroic = self:GetZoneName()
   local zoneHash = mobdata[simpleZone] or { name = zone, mobs = { }, mm = 1, heroic = isHeroic }
   local changed

   
   if not zoneHash.mobs[uid] then
      if zoneHash.mobs[simpleName] then
	 -- 2.4 conversion to use mob id instead of simplified mob name
	 zoneHash.mobs[uid] = zoneHash.mobs[simpleName]
	 zoneHash.mobs[simpleName] = nil
      else
	 mobdata[simpleZone] = zoneHash -- new zone
	 zoneHash.mobs[uid] = {
	    name = name, 
	    new = true,
	    category = 1,
	    priority = 3,
	    ccpriority = 6,
	    cc = {},
	    ccnum = 8
	 }
      end

      if self.info then self:info(format(L["Added new mob %s in zone %s."],name, zone)) end

      changed = true
   end
   
   if not zoneHash.mobs[uid].desc then
      local family = UnitCreatureFamily(unit)
      local type = UnitCreatureType(unit)
      local mana = UnitManaMax(unit)
      local class = UnitClassification(unit)
      local desc = L["Creature type"]..": ".. white(type)
      if family then
	 desc =  desc ..", ".. L["family"] ..": " ..white(family)
      end
      desc =  desc ..", ".. L["classification"]..": "..white(class)
      if mana and mana > 0 then
	 desc =  desc ..", ".. L["unit is a caster"].."."
      end
      
      zoneHash.mobs[uid].desc  = desc
      changed = true
   end
   
   if zoneHash.mobs[uid].name ~= name then
      -- different locale, update name
      zoneHash.mobs[uid].name = name
      changed = true
   end

   if changed then
      if not options.args.mobs.args[simpleZone] then
	 options.args.mobs.args[simpleZone] = self:ZoneConfigData(simpleZone, zoneHash)
      else 
	 if options.args.mobs.args[simpleZone].args.loader.hidden then
	    self:LoadMobListForZone(simpleZone)
	 end
	 options.args.mobs.args[simpleZone].args.zoneInfo.name = self:GetZoneInfo(zoneHash)
      end
      self:NotifyChange()
   end
end

function MagicMarker:RemoveZone(var)
   local zone = var[#var-1]
   if self.warn then
      self:warn(L["Deleting zone %s from the database!"],
	       ZoneLookup[mobdata[zone].name] or mobdata[zone].name)
   end
   mobdata[zone] = nil
   options.args.mobs.args[zone] = nil
   self:NotifyChange()
end

function MagicMarker:RemoveMob(var)
   local mob = var[#var-1]
   local zone = var[#var-2]
   local hash = mobdata[zone]
      
   if self.info then
      self:info(L["Deleting mob %s from zone %s from the database!"],
	       hash.mobs[mob].name, ZoneLookup[hash.name] or hash.name)
   end
   hash.mobs[mob] = nil
   options.args.mobs.args[zone].plugins.mobList[mob] = nil
   options.args.mobs.args[zone].args.zoneInfo.name = self:GetZoneInfo(hash)
   self:NotifyChange()
end

function MagicMarker:BuildMobConfig(var)
   local mob = var[#var-1]
   local zone = var[#var-2]
   local zoneHash = options.args.mobs.args[zone]
   local subopts = options.args.mobs.args[zone].plugins.mobList
   local name = subopts[mob].name
   
   configBuilt = true

   if self.trace then self:trace("Generating configuration for %s in zone %s", mob, zone) end

   subopts[mob].args.loader.hidden = true
   
   subopts[mob].plugins = {
      sharedMobConfig = standardMobOptions,
      privateMobConfig = {
	 delete = {
	    type = 'execute',
	    name = L['Delete mob from database (not recoverable)'],
	    order = 10001,
	    width = "full",
	    func = "RemoveMob",
	    confirm = true,
	    confirmText = string.format(L["Are you sure you want to delete |cffd9d919%s|r from the database?"], name)
	 }
      }
   }
   self:NotifyChange()
end

function MagicMarker:NotifyChange()
   db = self.db.profile
   mobdata = MagicMarkerDB.mobdata
   self:UpdateUsedCCMethods()
   R:NotifyChange(L["Magic Marker"])
end
 
local unloadTimer

function MagicMarker:UnloadOptions()
   if C.OpenFrames[L["Magic Marker"]] then
      if not unloadTimer then
	 unloadTimer = self:ScheduleRepeatingTimer("UnloadOptions", 5)
      end
      return
   end
   if unloadTimer then
      self:CancelTimer(unloadTimer, true)  
      unloadTimer = nil
   end
   
   for id, hash in pairs(options.args.mobs.args) do
      if id ~= "headerdata" then
	 hash.args.loader.hidden = false
	 hash.plugins.mobList = nil
	 if self.trace then self:trace("Unloaded mob options for %s.", hash.name) end
      end
   end
   configBuilt = false
   R:NotifyChange(L["Magic Marker"])
end

function MagicMarker:GenerateOptions()
   local opts = options.args.categories.args
   local subopts, order

   db = self.db.profile

   mobdata = MagicMarkerDB.mobdata
   
   options.handler = MagicMarker
   options.args.categories.set = "SetRaidTargetConfig"
   options.args.categories.get = "GetRaidTargetConfig"

   for id, catName in ipairs(CC_LIST) do
      if id == 1 then
	 catName = "TANK"
	 subopts = opts
	 order = 1
      else
	 subopts = opts.cc.args
	 order = 0
      end 
      
      subopts[catName] = {
	 type = "group",
	 name = L[catName],
	 order = order,
	 args = {
	    addcc = {
	       type = "execute",
	       name = L["Add raid icon"],
	       func = "AddNewRT",
	       order = 1000,
	       hidden = "IsHiddenAddRT", 
	    }
	 },
      }

      for icon = 1,8 do
	 subopts[catName].args["icon"..icon] = {
	    type = "select",
	    name = "Raid Icon #"..icon,
	    dialogControl = "MMRaidIcon",
	    order = icon*10,
	    hidden = "IsHiddenRT",
	    values = raidIconDropdown,
	 }
      end
      
   end

   opts = options.args.mobs.args
   opts.headerdata = {
      type = "group",
      name = L["Introduction"],
      args = {
	 header = {
	    type = "header",
	    name = L["Introduction"]
	 },
	 desc = {
	    type = "description",
	    name = L["MOBDATAHELPTEXT"]
	 }
      },
      order = 0,
   }
   for id, zone in pairs(mobdata) do
      opts[id] = self:ZoneConfigData(id, zone)
   end

   -- command line options
   opts = cmdoptions.args.tmpl.args
   for cmd,data in pairs(self.MarkTemplates) do
      opts[cmd] = {
	 type = "execute",
	 name = data.desc,
	 func = function() MagicMarker:MarkRaidFromTemplate(cmd) end,
	 order = data.order
      }
   end
   
   self:UpdateUsedCCMethods()

   options.args.options.args.profile = DBOpt:GetOptionsTable(self.db)
   if MMFu then
      MMFu:GenerateProfileConfig()
   end
end

function MagicMarker:AddZoneConfig(zone, zonedata)
   options.args.mobs.args[zone] = self:ZoneConfigData(zone, zonedata)
end

function MagicMarker:ZoneConfigData(id, zone)
   local name = ZoneLookup[zone.name] or zone.name
   if zone.heroic then
      name = L["Heroic"] .. " " .. name 
   end

   return {
      type = "group",
      name = name,
      handler = MagicMarker, 
      args = {
	 zoneInfo = {
	    type = "description",
	    name = self:GetZoneInfo(zone), 
	    order = 0,
	 },
	 delete = {
	    type = 'execute',
	    name = L['Delete entire zone from database (not recoverable)'],
	    order = 100,
	    width = "full",
	    func = "RemoveZone",
	    confirm = true,
	    confirmText = string.format(L["Are you |cffd9d919REALLY|r sure you want to delete |cffd9d919%s|r and all its mob data from the database?"],
					ZoneLookup[zone.name] or zone.name)
	 },
	 loader = {
	    type = "toggle",
	    name = "loader",
	    get = "LoadMobListForZone",
	    set = function() end,
	    arg = id,
	 }
      },
      plugins = {
	 StandardZone = standardZoneOptions, 
      },
      set = "SetMobConfig",
      get = "GetMobConfig", 
   }
end

function MagicMarker:LoadMobListForZone(var)
   local zone = (type(var) == "table" and var[#var-1]) or var
   local zoneData = options.args.mobs.args[zone]
   local name = mobdata[zone].name
   local subopts = {}

   configBuilt = true

   name = ZoneReverse[name] or name

   if self.trace then self:trace("Loading mob list for zone %s", name) end

   zoneData.args.loader.hidden = true 
   zoneData.plugins.mobList = subopts

   for mob, data in pairs(mobdata[zone].mobs) do
      subopts[mob] = {
	 type = "group",
	 name = (data.new and "* "..data.name) or data.name,
	 args = {
	    loader = {
	       name = "Loader",
	       type = "toggle",
	       get = "BuildMobConfig", 
	       set = function() end
	    }
	 }
      }
   end
   self:NotifyChange()
end

function MagicMarker:GetCCName(ccid, val)
   if not ccid then
      return (val == 50 and L["External"]) or L["Template"]
   elseif ccid == 1 then
      return (val and L["TANK"]) or tolower(L["TANK"])
   else
      return (val and L[CC_LIST[ccid]]) or tolower(L[CC_LIST[ccid]])
   end
end

function MagicMarker:GetTargetName(ccid, link)
   if link then
      return format("{%s}", sub(RT_LIST[ccid], 2))
   else
      return sub(RT_LIST[ccid], 2)
   end
end

function MagicMarker:UpgradeDatabase()
   local version = MagicMarkerDB.version or 0

   if version < 1 then
      -- Added two new priority levels and change logging 
      MagicMarkerDB.logLevel = (MagicMarkerDB.debug and self.logLevels.DEBUG) or self.logLevels.INFO
      MagicMarkerDB.debug = nil
      for zone,zoneData in pairs(MagicMarkerDB.mobdata) do
	 for mob, mobData in pairs(zoneData.mobs) do
	    if mobData.priority == 4 then
	       mobData.priority = 6
	    else
	       mobData.priority = mobData.priority + 1
	    end
	 end
      end
   end

   if version < 2 then
      -- zone-level enable/disable feature, default to enable
      for zone,zoneData in pairs(MagicMarkerDB.mobdata) do
	 zoneData.mm = true
      end
   end

   if version < 3 then
      self.db.profile.logLevel = MagicMarkerDB.logLevel
   end

   if version < 4 then
      -- Added "max mobs to CC" option, default to 8 (max)
      for zone,zoneData in pairs(MagicMarkerDB.mobdata) do
	 for mob, mobData in pairs(zoneData.mobs) do
	    mobData.ccnum = 8
	 end
      end
   end
   
   if version < 5 then
      local ccopt
      -- Changed to non-prioritized cc-list for mobs 
      for zone,zoneData in pairs(MagicMarkerDB.mobdata) do
	 for mob, mobData in pairs(zoneData.mobs) do
	    ccopt = {}
	    for _,ccid in pairs(mobData.cc) do
	       if ccid ~= CONFIG_MAP['00NONE'] then
		  ccopt[ccid] = true
	       end
	    end
	    if next(ccopt) then
	       mobData.ccopt = ccopt
	    else
	       mobData.ccopt = nil
	    end
	    mobData.cc = nil
	 end
      end
   end
   
   if version < 7 then
      for zone,zoneData in pairs(MagicMarkerDB.mobdata) do
	 zoneData.handler = nil -- oops, didn't mean to store that in there!
	 for mob, mobData in pairs(zoneData.mobs) do
	    mobData.ccpriority = 6 -- default ccpriority to "same as tank"
	 end
      end      
   end

   MagicMarkerDB.version = CONFIG_VERSION
end


local keyBindingOrder = 1000

local function AddKeyBinding(keyname, name, desc)
   _G["BINDING_NAME_"..keyname] = name
   options.args.options.args.keybindings.args[keyname] = {
      name = name, 
      desc = desc or desc, 
      type = "keybinding",
      arg = keyname,
      order = keyBindingOrder,
   }
   keyBindingOrder = keyBindingOrder + 1
end

function MagicMarker:AboutMagicMarker()
   self:Print("|cffafa4ffAuthor:|r David Hedbor <neotron@gmail.com>")
   self:Print("|cffafa4ffDescription:|r Automated smart raid marking to speed up trash clearing in instance runs.")
   self:Print("|cffafa4ffVersion:|r"..self.version)
   self:Print("|cffafa4ffHosted by:|r WowAce.com - thanks guys!")
   self:Print("|cffafa4ffPowered by:|r Ace3")
end

function MagicMarker:GetOptions()
   return options
end
-- Keybind names

BINDING_HEADER_MagicMarker = L["Magic Marker"]

AddKeyBinding("MAGICMARKRESET", L["Reset raid icon cache"])
AddKeyBinding("MAGICMARKMARK", L["Mark selected target"])
AddKeyBinding("MAGICMARKUNMARK", L["Unmark selected target"])
AddKeyBinding("MAGICMARKTOGGLE", L["Toggle config dialog"])
AddKeyBinding("MAGICMARKRAID", L["Mark party/raid targets"])
AddKeyBinding("MAGICMARKSAVE", L["Save party/raid mark layout"])
AddKeyBinding("MAGICMARKLOAD", L["Load party/raid mark layout"])
AddKeyBinding("MAGICMARKSMARTMARK", L["Smart marking modifier key"], L["SMARTMARKKEYHELP"])

LibStub("AceConfig-3.0"):RegisterOptionsTable(L["Magic Marker"],
					      function(name) return (name == "dialog" and options) or cmdoptions end,
					      { "mm", "magic", "magicmarker" })

