--[[
**********************************************************************
MagicMarker best friend for raid marking. See README.txt for
more details.
**********************************************************************
This file is part of MagicMarker, a World of Warcraft Addon

MagicMarker is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MagicMarker is distributed in the hope that it will be useful, WITHOUT
but ANY WARRANTY without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with MagicMarker.  If not, see <http://www.gnu.org/licenses/>.
**********************************************************************
]]

local CONFIG_VERSION = 11
local format = string.format
local sub = string.sub
local strmatch = strmatch
local tonumber = tonumber
local tolower = strlower
local UnitGUID = UnitGUID
local LibStub = LibStub
local ipairs = ipairs
local pairs = pairs
local select = select
local tinsert = tinsert
local tconcat = table.concat
local tostring = tostring
local tsort = table.sort
local next = next
local gsub = gsub
local type = type

local GetRealZoneText = GetRealZoneText
local IsInInstance = IsInInstance
local UnitCreatureFamily = UnitCreatureFamily
local UnitCreatureType = UnitCreatureType
local UnitPowerMax = UnitPowerMax
local UnitClassification = UnitClassification
local GetBindingKey = GetBindingKey
local SetBinding = SetBinding
local GetBindingAction = GetBindingAction
local GetBindingText = GetBindingText
local SetBindings = SetBindings
local GetCurrentBindingSet = GetCurrentBindingSet
local SaveBindings = SaveBindings or AttemptToSaveBindings

local KEY_BOUND = KEY_BOUND
local KEY_UNBOUND_ERROR = KEY_UNBOUND_ERROR
local _G = _G

local mod = LibStub("AceAddon-3.0"):GetAddon("MagicMarker")
local MagicMarker = mod
local L = LibStub("AceLocale-3.0"):GetLocale("MagicMarker", false)
local R = LibStub("AceConfigRegistry-3.0")
local C = LibStub("AceConfigDialog-3.0")
local DBOpt = LibStub("AceDBOptions-3.0")

local BabbleZone = LibStub("LibBabble-Zone-3.0")
local ZoneReverse = BabbleZone:GetReverseLookupTable()
local ZoneLookup = BabbleZone:GetUnstrictLookupTable()
BabbleZone = nil

local MobNotesDB
local options, cmdoptions, standardZoneOptions, standardMobOptions
local lastRaidIconType

local db

local mobdata

local configBuilt


-- Config UI name => ID
local CONFIG_MAP = {}

-- ID => Config UI name
local ACT_LIST = { "TANK", "CC" }
local CC_LIST = {
    "00NONE", "SHEEP", "BANISH", "SHACKLE", "HIBERNATE", "TRAP", "KITE",
    "MC", "FEAR", "SAP", "ENSLAVE", "ROOT",
    "CYCLONE", "TURNUNDEAD", "SCAREBEAST", "SEDUCE", "TURNEVIL", "BLIND", "BURN",
    "HEX", "REPENTANCE", "BINDELEMENTAL"
}
local AVAILABLE_CC = {
	[7] = true, -- KITE
	[19] = true, -- BURN
}
do
    local ccids = LibStub("MagicComm-1.0").spellIdToCCID
    for spellid in pairs(ccids) do
        AVAILABLE_CC[ccids[spellid]] = true
    end
end

local PRI_LIST = { "P1", "P2", "P3", "P4", "P5", "P6" }
local CCPRI_LIST = { "P1", "P2", "P3", "P4", "P5", "P0" }
local RT_LIST = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull", "None" }
local ccDropdown, ccpriDropdown, priDropdown, catDropdown, raidIconDropdown, logLevelsDropdown

local dungeon_tiers = {
    wotlk = {
        ["Ahn'kahet:TheOldKingdom"] = true,
        ["Azjol-Nerub"] = true,
        ["Drak'TharonKeep"] = true,
        ["Gundrak"] = true,
        ["HallsofLightning"] = true,
        ["HallsofReflection"] = true,
        ["HallsofStone"] = true,
        ["IcecrownCitadel"] = true,
        ["Naxxramas"] = true,
        ["PitofSaron"] = true,
        ["TheCullingofStratholme"] = true,
        ["TheEyeofEternity"] = true,
        ["TheForgeofSouls"] = true,
        ["TheNexus"] = true,
        ["TheObsidianSanctum"] = true,
        ["TheOculus"] = true,
        ["TheVioletHold"] = true,
        ["TrialoftheChampion"] = true,
        ["TrialoftheCrusader"] = true,
        ["Ulduar"] = true,
        ["UtgardeKeep"] = true,
        ["UtgardePinnacle"] = true,
        ["VaultofArchavon"] = true,
    },
    bc = {
        ["AuchenaiCrypts"] = true,
        ["BlackTemple"] = true,
        ["Gruul'sLair"] = true,
        ["HellfireRamparts"] = true,
        ["HyjalSummit"] = true,
        ["Karazhan"] = true,
        ["Magisters'Terrace"] = true,
        ["Magtheridon'sLair"] = true,
        ["Mana-Tombs"] = true,
        ["OldHillsbradFoothills"] = true,
        ["SerpentshrineCavern"] = true,
        ["SethekkHalls"] = true,
        ["ShadowLabyrinth"] = true,
        ["SunwellPlateau"] = true,
        ["TempestKeep"] = true,
        ["TheArcatraz"] = true,
        ["TheBlackMorass"] = true,
        ["TheBloodFurnace"] = true,
        ["TheBotanica"] = true,
        ["TheMechanar"] = true,
        ["TheShatteredHalls"] = true,
        ["TheSlavePens"] = true,
        ["TheSteamvault"] = true,
        ["TheUnderbog"] = true,
        ["Zul'Aman"] = true,
    },
    cata = {
        ["BaradinHold"] = true,
        ["BlackrockCaverns"] = true,
        ["BlackwingDescent"] = true,
        ["GrimBatol"] = true,
        ["HallsofOrigination"] = true,
        ["LostCityoftheTol'vir"] = true,
        ["TheBastionOfTwilight"] = true,
        ["TheBastionofTwilight"] = true,
        ["TheStonecore"] = true,
        ["TheVortexPinnacle"] = true,
        ["ThroneoftheFourWinds"] = true,
        ["ThroneoftheTides"] = true,
        ["Firelands"] = true,
    }
}

function mod:GetCCID(ccname)
    return CONFIG_MAP[ccname]
end

function mod:GetIconTexture(id)
    return format("Interface\\AddOns\\MagicMarker\\Textures\\%s.tga",
            sub(RT_LIST[id], 2))
end

-- KeybindHelper code from Xinhuan's addon IPopBar. Thanks for letting me use it!
local KeybindHelper = {}
do
    local t = {}
    function KeybindHelper:MakeKeyBindingTable(...)
        for k in pairs(t) do
            t[k] = nil
        end
        for i = 1, select("#", ...) do
            local key = select(i, ...)
            if key ~= "" then
                tinsert(t, key)
            end
        end
        return t
    end

    function KeybindHelper:GetKeybind(info)
        return tconcat(self:MakeKeyBindingTable(GetBindingKey(info.arg)), ", ")
    end

    function KeybindHelper:SetKeybind(info, key)
        if key == "" then
            local t = self:MakeKeyBindingTable(GetBindingKey(info.arg))
            for i = 1, #t do
                SetBinding(t[i])
            end
        else
            local oldAction = GetBindingAction(key)
            if (oldAction ~= "" and oldAction ~= info.arg) then
                mod:SetStatusText(format(KEY_UNBOUND_ERROR, GetBindingText(oldAction, "BINDING_NAME_")), true)
            else
                mod:SetStatusText(KEY_BOUND, true)
            end

            SetBinding(key, info.arg)
        end
        SaveBindings(GetCurrentBindingSet())
    end
end

local updateStatusTimer
function mod:SetStatusText(text, update)
    local frame = C.OpenFrames["Magic Marker"]
    if frame then
        frame:SetStatusText(text)
        if updateStatusTimer then
            self:CancelTimer(updateStatusTimer, true)
        end
        if update then
            updateStatustimer = self:ScheduleTimer("SetStatusText", 10, format(L["Active profile: %s"], self.db:GetCurrentProfile()))
        else
            updateStatustimer = false
        end
    end
end

local function GetMobName(arg)
    return mobdata[arg[#arg - 2]] and mobdata[arg[#arg - 2]].mobs[arg[#arg - 1]].name
end

local function GetMobDesc(arg)
    return mobdata[arg[#arg - 2]] and mobdata[arg[#arg - 2]].mobs[arg[#arg - 1]].desc
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
        return note .. "\n" .. desc
    elseif desc then
        return desc
    else
        return note or "N/A"
    end
end

function mod:NoMobNote(arg)
    return not ((MobNotesDB and MobNotesDB[GetMobName(arg)]) or GetMobDesc(arg))
end

function mod:ToggleConfigDialog()
    if C.OpenFrames["Magic Marker"] then
        C:Close("Magic Marker")
    else
        C:Open("Magic Marker")
        self:SetStatusText(format(L["Active profile: %s"], self.db:GetCurrentProfile()))
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

    CONFIG_MAP.NUMCC = #CC_LIST - 1
    maxcc = CONFIG_MAP.NUMCC + 1
    for num, txt in ipairs(CC_LIST) do
        if num <= maxcc and AVAILABLE_CC[num] then
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
        temp = num .. txt
        raidIconDropdown[temp] = L[txt]
        CONFIG_MAP[temp] = num
        RT_LIST[num] = temp
    end
    for logname, id in pairs(mod.logLevels) do
        logLevelsDropdown[id] = L[logname]
    end

    -- command line / dropdown options
    cmdoptions = {
        type = "group",
        name = L["Magic Marker"],
        handler = mod,
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
                args = {}
            },
            about = {
                type = "execute",
                name = L["About Magic Marker"],
                func = "AboutMagicMarker"
            },
            reset = {
                type = "execute",
                name = L["Reset raid icon cache"] .. ".",
                func = "ResetMarkData",
            },
            assignments = {
                type = "execute",
                name = L["Report the raid icon assignments to raid/party chat"] .. ".",
                func = "ReportRaidMarks"
            },
            cache = {
                type = "group",
                name = L["Raid mark layout caching"],
                args = {
                    save = {
                        type = "execute",
                        name = L["Save party/raid mark layout"] .. ".",
                        func = "CacheRaidMarks",
                    },
                    load = {
                        type = "execute",
                        name = L["Load party/raid mark layout"] .. ".",
                        func = "MarkRaidFromCache",
                    },
                }
            }
        }
    }

    local expansions

    if mod:IsClassic() then
        expansions = {
            vanilla = { name = L["Classic"], type = "group", args = {}, order = 10 },
        }
    elseif mod:IsBurningCrusadeClassic() then
        expansions = {
            bc = { name = L["Burning Crusade"], type = "group", args = {}, order = 60 },
            vanilla = { name = L["Classic"], type = "group", args = {}, order = 70 },
        }
    else
        expansions = {
            bfa = { name = L["Battle for Azeroth"], type = "group", args = {}, order = 10 },
            legion = { name = L["Legion"], type = "group", args = {}, order = 20 },
            wod = { name = L["Warlords of Draenor"], type = "group", args = {}, order = 30 },
            cata = { name = L["Cataclysm"], type = "group", args = {}, order = 40 },
            wotlk = { name = L["Wrath of the Lich King"], type = "group", args = {}, order = 50 },
            bc = { name = L["Burning Crusade"], type = "group", args = {}, order = 60 },
            vanilla = { name = L["Vanilla"], type = "group", args = {}, order = 70 },
        }
    end
    options = {
        type = "group",
        name = L["Magic Marker"],
        childGroups = "tab",
        args = {
            mobs = {
                type = "group",
                name = L["Mob Database"],
                args = expansions,
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
                        args = {}
                    },
                }
            },
            ccprio = {
                type = "group",
                name = L["CC"] .. " " .. L["Priority"],
                order = 2,
                cmdHidden = true,
                dropdownHidden = true,
                handler = mod,
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
                handler = mod,
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
                            header = {
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
                                disabled = function()
                                    return not db or not db.acceptMobData
                                end
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
                                handler = mod,
                                disabled = not mod:IsValidMarker()
                            },
                            broadcastMobs = {
                                type = "execute",
                                name = L["Broadcast all zone data to the raid group."],
                                desc = L["BROADALLHELP"],
                                order = 1001,
                                width = "full",
                                func = "BroadcastAllZones",
                                handler = mod,
                                disabled = not mod:IsValidMarker()
                            },
                            broadcastCCPrio = {
                                type = "execute",
                                name = L["Broadcast crowd control priority settings to the raid group."],
                                order = 1002,
                                width = "full",
                                func = "BroadcastCCPriorities",
                                handler = mod,
                                disabled = not mod:IsValidMarker()
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
                            filterdead = {
                                name = L["Ignore dead people"],
                                desc = L["FILTERDEADHELP"],
                                type = "toggle",
                                order = 74,
                            },
                            minTankTargets = {
                                name = L["Minimum # of tank targets"],
                                desc = L["MINTANKHELP"],
                                type = "range",
                                min = 0,
                                max = 8,
                                step = 1,
                                order = 50,
                            },
                            modifier = {
                                name = L["Smart Mark Modifier"],
                                desc = L["SMARTMARKMODHELP"],
                                type = "select",
                                order = 20,
                                disabled = function()
                                    return GetBindingKey("MAGICMARKSMARTMARK") ~= nil
                                end,
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
                            burnDownIsTank = {
                                name = L["Count Burn Down target as tanked mobs"],
                                desc = L["BURN DOWN HELP"],
                                type = "toggle",
                                order = 120,
                                width = "full",
                            },
                            noCombatRemark = {
                                name = L["Preserve raid icons on units in combat"],
                                desc = L["IN COMBAT UNIT HELP TEXT"],
                                type = "toggle",
                                order = 125,
                                width = "full",
                            },
                            battleMarking = {
                                name = L["Enable target re-prioritization during combat"],
                                desc = L["INCOMBATHELPTEXT"],
                                type = "toggle",
                                order = 130,
                                width = "full",
                                hidden = true, -- disabled for now, it's confusing as hell
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
            handler = mod,
            set = "SetZoneConfig",
            get = "GetZoneConfig",
            order = 20,
        },
        mm = {
            width = "full",
            type = "toggle",
            name = L["Enable Magic Marker in this zone"],
            handler = mod,
            set = "SetZoneConfig",
            get = "GetZoneConfig",
            order = 10,
        },
        broadcastMobs = {
            type = "execute",
            name = L["Broadcast zone data to the raid group."],
            order = 1001,
            width = "full",
            func = function(var)
                mod:BroadcastZoneData(var[#var - 1])
            end,
            disabled = not mod:IsValidMarker()
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
            name = L["TANK"] .. " " .. L["Priority"],
            type = "select",
            values = priDropdown,
            order = 2,
        },
        ccpriority = {
            name = L["CC"] .. " " .. L["Priority"],
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
            min = 1,
            max = 8,
            step = 1,
            order = 4,
            hidden = "IsIgnoredCC",
        },
        ccheader = {
            name = L["CC"] .. " " .. L["Config"],
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

    for num = 1, CONFIG_MAP.NUMCC do
        options.args.ccprio.args["ccopt" .. num] = {
            name = format("%s #%d", L["CC"], num),
            type = "select",
            width = "full",
            values = ccDropdown,
            order = 100 + num,
            hidden = "IsHiddenCC",
            dialogControl = "MMCCPrio",
        }
    end
end

function mod:SetProfileParam(var, value)
    local varName = var[#var]
    db[varName] = value
    if self.hasSpam then
        self:spam("Setting parameter %s to %s.", varName, tostring(value))
    end

    if varName == "logLevel" then
        self:SetLogLevel(value)
    end
end

function mod:GetProfileParam(var)
    local varName = var[#var]
    if self.hasSpam then
        self:spam("Getting parameter %s as %s.", varName, tostring(db[varName]))
    end
    return db[varName]
end

function mod:GetMarkForCategory(category)
    if category == 1 then
        return db.targetdata.TANK or {}
    end
    return db.targetdata[CC_LIST[category]] or {}
end

function mod:IsUnitIgnored(pri)
    return pri == CONFIG_MAP.P6
end

local function getID(value)
    return tonumber(strmatch(value, "%d+"))
end

local function uniqList(list, id, newValue, empty, max)
    local addEmpty = false
    list[id] = newValue

    local currentPos = 1
    local seen_value = {}

    for iter = 1, max do
        if list[iter] and not seen_value[list[iter]] and list[iter] ~= empty then
            list[currentPos] = list[iter]
            currentPos = currentPos + 1
            seen_value[list[iter]] = true
        end
    end

    for iter = currentPos, max do
        list[iter] = nil
    end

    return list
end

function mod:SetRaidTargetConfig(info, value)
    local type = info[#info - 1]
    local id = getID(info[#info])
    value = CONFIG_MAP[value]
    db.targetdata[type] = uniqList(db.targetdata[type] or {}, id, value, 9, 8)
end

function mod:GetRaidTargetConfig(info)
    local type = info[#info - 1]
    local id = getID(info[#info]) or 9
    if not db.targetdata[type] then
        return nil
    end
    lastRaidIconType = type
    return RT_LIST[db.targetdata[type][id]]
end

function mod:GetCCPrio(info)
    local var = info[#info]
    local value = CC_LIST[db.ccprio[getID(var)] or 1]
    if value == CC_LIST['00NONE'] then
        value = nil
    end
    if self.hasSpam then
        self:spam("Get %s as %s", var, tostring(value))
    end
    return value
end

function mod:SetCCPrio(info, value)
    local var = info[#info]
    db.ccprio = uniqList(db.ccprio or {}, getID(var), CONFIG_MAP[value], 1, CONFIG_MAP.NUMCC)
    mod:UpdateUsedCCMethods()
    if self.hasSpam then
        self:spam("Set %s to %s", var, tostring(value))
    end
end

function mod:UpdateUsedCCMethods()
    local unused = L["Unused Crowd Control Methods"]
    local used = {}
    local sorted = {}
    local first = true
    if db.ccprio then
        for _, id in pairs(db.ccprio) do
            used[id] = true
        end
    end

    for id = 2, CONFIG_MAP.NUMCC + 1 do
        if not used[id] and AVAILABLE_CC[id] then
            sorted[#sorted + 1] = L[CC_LIST[id]]
        end
    end
    tsort(sorted)

    if next(sorted) then
        for id = 1, #sorted do
            if first then
                unused = unused .. ": " .. sorted[id]
                first = false
            else
                unused = unused .. ", " .. sorted[id]
            end
        end
        options.args.ccprio.args.ccinfo.name = unused
    else
        options.args.ccprio.args.ccinfo.name = ""
    end
end

function mod:SetMobConfig(info, value, state)
    local var = info[#info]
    local mob = info[#info - 1]
    local region = info[#info - 2]
    if var ~= "ccnum" then
        value = CONFIG_MAP[value]
    end
    local mobhash = mobdata[region].mobs[mob]
    if var == "ccopt" then
        if value == CONFIG_MAP['00NONE'] then
            mobhash.ccopt = nil
        else
            local ccopt = mobhash.ccopt or {}

            ccopt[value] = state or nil

            if not next(ccopt) then
                mobhash.ccopt = nil
            else
                mobhash.ccopt = ccopt
            end
        end
        if self.hasSpam then
            self:spam("|cffffff00SetMobConfig:|r %s/%s/%s[%s] => %s", region, mob, var, CC_LIST[value], tostring(state))
        end
    else
        mobhash[var] = value
        if self.hasSpam then
            self:spam("|cffffff00SetMobConfig:|r %s/%s/%s => %s", region, mob, var, tostring(value))
        end
    end

    if mobhash.new then
        mobhash.new = nil
        -- Remove the "new" mark
        self:GetZoneConfigHash(mobdata[region], region).args[region].plugins.mobList[mob].name = mobhash.name
    end
    self:QueueData_Add(region, mob, mobhash)
end

function mod:GetMobConfig(info, key)
    local var = info[#info]
    local mob = info[#info - 1]
    local region = info[#info - 2]
    local value = mobdata[region].mobs[mob][var]

    if var == "ccopt" then
        if not value then
            if key == '00NONE' then
                value = true
            end
        elseif value then
            value = mobdata[region].mobs[mob].ccopt[CONFIG_MAP[key]]
        end
        if self.hasSpam then
            self:spam("GetMobConfig: %s/%s/%s[%s] => %s", region, mob, var, key, tostring(value))
        end
    else
        if var == "priority" then
            value = PRI_LIST[value or 1]
        elseif var == "ccpriority" then
            value = CCPRI_LIST[value or 1]
        elseif var == "category" then
            value = ACT_LIST[value or 1]
        end
        if self.hasSpam then
            self:spam("GetMobConfig: %s/%s/%s => %s", region, mob, var, tostring(value))
        end
    end
    return value
end

function mod:SetZoneConfig(info, value)
    local var = info[#info]
    local region = info[#info - 1]
    mobdata[region][var] = value
    if self.hasSpam then
        self:spam("Setting %s:%s to %s", region, var, tostring(value))
    end
    if region == self:GetZoneName() then
        if var == "mm" then
            self:ZoneChangedNewArea()
        elseif var == "targetMark" then
            if value then
                self:RegisterEvent("PLAYER_TARGET_CHANGED", "SmartMark_MarkUnit", "target")
            else
                self:UnregisterEvent("PLAYER_TARGET_CHANGED")
            end
        end
    end
end

function mod:GetZoneConfig(info)
    local var = info[#info]
    local region = info[#info - 1]
    return mobdata[region][var]
end

function mod:IsIgnored(var)
    return mod:IsUnitIgnored(mobdata[var[#var - 2]].mobs[var[#var - 1]].priority)
end

function mod:IsIgnoredCC(var)
    local mob = mobdata[var[#var - 2]].mobs[var[#var - 1]]
    return mob.category == CONFIG_MAP.TANK or mod:IsUnitIgnored(mob.priority)
end

function mod:IsHiddenCC(var)
    local index = getID(var[#var])
    return not db.ccprio[index]
end

function mod:IsHiddenRT(var)
    local index = getID(var[#var])
    local list = db.targetdata[var[#var - 1]]
    return not list or not list[index]
end

function mod:IsHiddenAddRT(var)
    local index = getID(var[#var])
    local list = db.targetdata[var[#var - 1]]
    if not list then
        return false
    end
    return list[#list] == 9 or #list == 8
end

function mod:IsHiddenAddCC(var)
    local cc = db.ccprio
    return cc[#cc] == 1 or #cc == CONFIG_MAP.NUMCC
end

function mod:AddNewCC(var)
    local val = db.ccprio
    val[#val + 1] = 1
end

function mod:AddNewRT(var)
    local val = db.targetdata[var[#var - 1]] or {}
    val[#val + 1] = 9
    db.targetdata[var[#var - 1]] = val
end

function mod:AddAllRT(var)
    local ccid = var[#var - 1]
    local val = db.targetdata[ccid] or {}
    local used = {}
    for _, id in ipairs(val) do
        used[id] = true
    end
    for id = 1, 8 do
        if not used[id] then
            val[#val + 1] = id
            db.targetdata[ccid] = val
        end
    end
end

function mod:GetZoneName(zone)
    local simple, heroic
    if not zone then
        zone = GetRealZoneText()
    end
    zone = ZoneReverse[zone] or zone

    simple = self:SimplifyName(zone)
    local inInstance, type = IsInInstance()
    local diffid, diffname, heroic = mod:GetDifficultyInfo()
    if inInstance and (diffid <= 0 or not heroic) then
        simple = simple .. diffname
    end
    local isRaid = type == "raid"
    return simple, zone, heroic, isRaid
end

local simpleNameCache = {}

function mod:SimplifyName(name)
    if not name then
        return ""
    end
    if not simpleNameCache[name] then
        simpleNameCache[name] = gsub(name, " ", "")
    end
    return simpleNameCache[name]
end

function mod:GetZoneInfo(hash)
    local new = 0
    local total = 0
    local ignored = 0
    local mobs = hash.mobs
    for mob, data in pairs(mobs) do
        if data.new then
            new = new + 1
        end
        if data.priority == 6 then
            ignored = ignored + 1
        end
        total = total + 1
    end
    if new > 0 then
        new = tostring(new)
    else
        new = L["None"]
    end

    local ret = format(L["%s has a total of %d mobs.\n%s of these are newly discovered."],
            hash.name, total, new)
    if ignored > 0 then
        ret = ret .. " " .. format(L["\nOut of these mobs %d are ignored."], ignored)
    end
    return ret
end

local optionsCallout

local function white(str)
    return format("|cffffffff%s|r", str or "N/A")
end

local function CompatGUIDToUID(guid)
    local uid = tonumber(sub(guid, 8, 12), 16)
    if uid == 0 then
        return nil
    end
    return tostring(uid)
end

function mod:InsertNewUnit(guid, uid, name, unit)
    local simpleName = self:SimplifyName(name)
    local simpleZone, zone, isHeroic, isRaid = self:GetZoneName()
    local zoneHash = mobdata[simpleZone] or { name = zone, mobs = {}, mm = 1, heroic = isHeroic }
    local changed
    local mobHash = zoneHash.mobs[uid]
    zoneHash.isRaid = isRaid
    -- Yeah this is not good but unavoidable for upgrade purposes.
    -- Stupid UID being broken with absolutely no way to convert
    -- correctly.
    for oldUID, hash in pairs(zoneHash.mobs) do
        if uid ~= oldUID and hash.name == name then
            if mobHash then
                mod:MergeCCMethods(mobHash, hash)
            else
                zoneHash.mobs[uid] = hash
                mobHash = hash
            end
            if mod.hasTrace then
                mod:trace("Upgraded broken uid %d to %d for %s.",
                        oldUID, uid, mobHash.name);
            end
            zoneHash.mobs[oldUID] = nil
            changed = true
        end
    end

    if not mobHash then
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

        if self.hasInfo then
            self:info(format(L["Added new mob %s in zone %s."], name, zone))
        end

        changed = true
    end
    mobHash = zoneHash.mobs[uid]

    if not mobHash.desc then
        local family = UnitCreatureFamily(unit)
        local type = UnitCreatureType(unit)
        local mana = UnitPowerMax(unit, Enum.PowerType.Mana)
        local class = UnitClassification(unit)
        local desc = L["Creature type"] .. ": " .. (white(type or "Unknown"))
        if family then
            desc = desc .. ", " .. L["family"] .. ": " .. white(family)
        end
        desc = desc .. ", " .. L["classification"] .. ": " .. white(class)
        if mana and mana > 0 then
            desc = desc .. ", " .. L["unit is a caster"] .. "."
        end

        mobHash.desc = desc
        changed = true
    end

    if mobHash.name ~= name then
        -- different locale, update name
        mobHash.name = name
        changed = true
    end

    local subZoneHash = self:GetZoneConfigHash(zoneHash, simpleZone)
    if changed then
        if not subZoneHash.args[simpleZone] then
            subZoneHash.args[simpleZone] = self:ZoneConfigData(simpleZone, zoneHash)
        else
            if subZoneHash.args[simpleZone].args.loader.hidden then
                self:LoadMobListForZone(simpleZone)
            end
            subZoneHash.args[simpleZone].args.zoneInfo.name = self:GetZoneInfo(zoneHash)
        end
        self:NotifyChange()
    end
    return mobHash
end

function mod:GetZoneConfigHash(zone, name)
    local era
    local shortname = gsub(name, "Heroic", "")
    shortname = gsub(shortname, "Normal", "")
    shortname = gsub(shortname, "Mythic", "")
    for expansion, dungeons in pairs(dungeon_tiers) do
        if dungeons[shortname] then
            era = options.args.mobs.args[expansion]
            break
        end
    end
    if not era then
        era = options.args.mobs.args.vanilla
    end

    local subZoneHash
    if zone.isRaid then
        subZoneHash = era.args.raid or {
            type = "group",
            name = L["Raid"],
            args = {}
        }
        era.args.raid = subZoneHash
    elseif zone.heroic then
        subZoneHash = era.args.heroic or {
            type = "group",
            name = L["Heroic"],
            args = {}
        }
        era.args.heroic = subZoneHash
    else
        subZoneHash = era.args.normal or {
            type = "group",
            name = L["Normal"],
            args = {}
        }
        era.args.normal = subZoneHash
    end
    return subZoneHash
end

function mod:RemoveZone(var)
    local zone = var[#var - 1]
    if self.hasWarn then
        self:warn(L["Deleting zone %s from the database!"],
                ZoneLookup[mobdata[zone].name] or mobdata[zone].name)
    end
    local zoneData = mobdata[zone]
    mobdata[zone] = nil
    if zoneData then
        self:GetZoneConfigHash(zoneData, zone).args[zone] = nil
    end
    self:NotifyChange()
end

function mod:RemoveMob(var)
    local mob = var[#var - 1]
    local zone = var[#var - 2]
    local hash = mobdata[zone]

    if self.hasInfo then
        self:info(L["Deleting mob %s from zone %s from the database!"],
                hash.mobs[mob].name, ZoneLookup[hash.name] or hash.name)
    end
    hash.mobs[mob] = nil
    local zoneData = self:GetZoneConfigHash(hash, zone)
    zoneData.args[zone].plugins.mobList[mob] = nil
    zoneData.args[zone].args.zoneInfo.name = self:GetZoneInfo(hash)
    self:NotifyChange()
end

function mod:BuildMobConfig(var)
    local mob = var[#var - 1]
    local zone = var[#var - 2]

    local zoneHash = self:GetZoneConfigHash(mobdata[zone], zone)
    local subopts = zoneHash.args[zone].plugins.mobList
    local name = subopts[mob].name

    configBuilt = true

    if self.hasTrace then
        self:trace("Generating configuration for %s in zone %s", mob, zone)
    end

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
                confirmText = format(L["Are you sure you want to delete |cffd9d919%s|r from the database?"], name)
            }
        }
    }
    self:NotifyChange()
end

function mod:NotifyChange()
    db = self.db.profile
    mobdata = MagicMarkerDB.mobdata
    self:UpdateUsedCCMethods()
    R:NotifyChange(L["Magic Marker"])
end

function mod:GenerateOptions()
    local opts = options.args.categories.args
    local subopts, order

    db = self.db.profile

    mobdata = MagicMarkerDB.mobdata

    options.handler = mod
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
                },
                auto = {
                    type = "execute",
                    name = L["Add all raid icons"],
                    func = "AddAllRT",
                    order = 1001,
                    hidden = "IsHiddenAddRT",
                }
            },
        }

        for icon = 1, 8 do
            subopts[catName].args["icon" .. icon] = {
                type = "select",
                name = L[catName] .. " #" .. icon,
                width = "full",
                dialogControl = "MMRaidIcon",
                order = icon * 10,
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
        local subZone = self:GetZoneConfigHash(zone, id)
        subZone.args[id] = self:ZoneConfigData(id, zone)
    end

    -- command line options
    opts = cmdoptions.args.tmpl.args
    for cmd, data in pairs(self.MarkTemplates) do
        opts[cmd] = {
            type = "execute",
            name = data.desc,
            func = function()
                mod:MarkRaidFromTemplate(cmd)
            end,
            order = data.order
        }
    end

    self:UpdateUsedCCMethods()

    options.args.options.args.profile = DBOpt:GetOptionsTable(self.db)
    mod:UpdateLDBConfig()
end

function mod:AddZoneConfig(zone, zonedata)
    local subZone = self:GetZoneConfigHash(zonedata, zone)
    subZone.args[zone] = self:ZoneConfigData(zone, zonedata)
end

function mod:ZoneConfigData(id, zone)
    local name = ZoneLookup[zone.name] or zone.name
    return {
        type = "group",
        name = name,
        handler = mod,
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
                confirmText = format(L["Are you |cffd9d919REALLY|r sure you want to delete |cffd9d919%s|r and all its mob data from the database?"],
                        ZoneLookup[zone.name] or zone.name)
            },
            loader = {
                type = "toggle",
                name = "loader",
                get = "LoadMobListForZone",
                set = function()
                end,
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

function mod:LoadMobListForZone(var)
    local zone = (type(var) == "table" and var[#var - 1]) or var
    local zoneData = self:GetZoneConfigHash(mobdata[zone], zone).args[zone]
    local name = mobdata[zone].name
    local subopts = {}

    configBuilt = true

    name = ZoneReverse[name] or name

    if self.hasTrace then
        self:trace("Loading mob list for zone %s", name)
    end

    zoneData.args.loader.hidden = true
    zoneData.plugins.mobList = subopts

    for mob, data in pairs(mobdata[zone].mobs) do
        subopts[mob] = {
            type = "group",
            name = (data.new and "* " .. data.name) or data.name,
            args = {
                loader = {
                    name = "Loader",
                    type = "toggle",
                    get = "BuildMobConfig",
                    set = function()
                    end
                }
            }
        }
    end
    self:NotifyChange()
end

function mod:MoveRaidIconDown(num)
    if not lastRaidIconType then
        return
    end
    if self.hasTrace then
        self:trace("Moving %s down from position %d", tostring(lastRaidIconType), num)
    end
    if db.targetdata[lastRaidIconType][num + 1] then
        local old = db.targetdata[lastRaidIconType][num]
        db.targetdata[lastRaidIconType][num] = db.targetdata[lastRaidIconType][num + 1]
        db.targetdata[lastRaidIconType][num + 1] = old
        self:NotifyChange()
    end
end

function mod:MoveRaidIconUp(num)
    if not lastRaidIconType then
        return
    end
    if self.hasTrace then
        self:trace("Moving %s up from position %d", tostring(lastRaidIconType), num)
    end
    local old = db.targetdata[lastRaidIconType][num]
    db.targetdata[lastRaidIconType][num] = db.targetdata[lastRaidIconType][num - 1]
    db.targetdata[lastRaidIconType][num - 1] = old
    self:NotifyChange()
end

function mod:MoveCCPrioDown(num)
    if self.hasTrace then
        self:trace("Swapping CC position %d down one", num)
    end
    if db.ccprio[num + 1] then
        local old = db.ccprio[num]
        db.ccprio[num] = db.ccprio[num + 1]
        db.ccprio[num + 1] = old
        self:NotifyChange()
    end
end

function mod:MoveCCPrioUp(num)
    if self.hasTrace then
        self:trace("Swapping CC position %d up one", num)
    end
    local old = db.ccprio[num]
    db.ccprio[num] = db.ccprio[num - 1]
    db.ccprio[num - 1] = old
    self:NotifyChange()
end

function mod:GetCCName(ccid, val)
    if ccid == -1 then
        return L["External"]
    elseif ccid == -2 then
        return L["Template"]
    elseif ccid == 1 then
        return (val and L["TANK"]) or tolower(L["TANK"])
    else
        return (val and L[CC_LIST[ccid]]) or tolower(L[CC_LIST[ccid]])
    end
end

function mod:GetTargetHashData()
    if not UnitExists("target") then
        return nil
    end
    local guid, uid, name = self:GetUnitID("target")
    local hash, zone = self:GetUnitHash(uid, true)
    return hash, uid, zone
end

function mod:Target_ChangePriority(change, cc)
    local hash, uid, zone = self:GetTargetHashData()
    if not hash then
        return
    end
    local priority
    local list
    if cc then
        priority = hash.ccpriority
        list = CCPRI_LIST
    else
        priority = hash.priority
        list = PRI_LIST
    end
    local newprio = priority - change

    if newprio < 1 then
        newprio = 1
    elseif newprio > #list then
        newprio = #list
    end
    if priority ~= newprio then
        if cc then
            hash.ccpriority = newprio
        else
            hash.priority = newprio
        end
        if self.hasInfo then
            self:info(L["Changed %s priority for %s to %s."],
                    tolower(cc and L["CC"] or L["TANK"]),
                    hash.name, L[list[newprio]])
        end
        self:NotifyChange();
        self:QueueData_Add(zone, uid, hash)
    end
end

function mod:Target_SwapCategory()
    local hash, uid, zone = self:GetTargetHashData()
    if not hash then
        return
    end
    if hash.category == 1 then
        hash.category = 2
    else
        hash.category = 1
    end
    if self.hasInfo then
        self:info(L["Changed category for %s to %s."], hash.name, L[ACT_LIST[hash.category]])
    end
    self:NotifyChange();
    self:QueueData_Add(zone, uid, hash)
end

do
    local iconLink = "|TInterface\\AddOns\\MagicMarker\\Textures\\%s.tga:0|t"
    function mod:GetTargetName(ccid, link)
        if not ccid then
            return "N/A"
        elseif link then
            return format("{rt%d}", ccid)
        else
            return format(iconLink, sub(RT_LIST[ccid] or "  ", 2))
        end
    end
end


-- All raid instances
do
    mod.raids = {
        ["MoltenCore"]=true, ["BlackwingLair"]=true, ["TempleofAhn'Qiraj"]=true, ["Ahn'Qiraj"]=true,
        ["RuinsofAhn'Qiraj"]=true, ["Zul'Gurub"]=true, ["Karazhan"]=true, ["Zul'Aman"]=true,
        ["Gruul'sLair"]=true, ["Magtheridon'sLair"]=true,
        ["SerpentshrineCavern"]=true, ["WorldBoss"]=true, ["TempestKeep"]=true,
        ["BlackTemple"]=true, ["HyjalSummit"]=true, ["Naxxramas"]=true, ["SunwellPlateau"]=true,
        ["TheObsidianSanctum"]=true, ["VaultofArchavon"]=true,
        ["TheEyeofEternity"]=true, ["Ulduar"]=true, ["TrialoftheCrusader"]=true, ["IcecrownCitadel"]=true
    }
    local raids = mod.raids
    -- all WotLK raid instances
    local mergeRaids = {
        Naxxramas = true,
        TheObsidianSanctum = true,
        VaultofArchavon = true,
        TheEyeofEternity = true,
        Ulduar = true,
        TrialoftheCrusader = true,
        IcecrownCitadel = true
    }

    function mod:UpgradeDatabase()
        local version = MagicMarkerDB.version or 0

        if version < 1 then
            -- Added two new priority levels and change logging
            MagicMarkerDB.logLevel = (MagicMarkerDB.debug and self.logLevels.DEBUG) or self.logLevels.INFO
            MagicMarkerDB.debug = nil
            for zone, zoneData in pairs(MagicMarkerDB.mobdata) do
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
            for zone, zoneData in pairs(MagicMarkerDB.mobdata) do
                zoneData.mm = true
            end
        end

        if version < 3 then
            self.db.profile.logLevel = MagicMarkerDB.logLevel
        end

        if version < 4 then
            -- Added "max mobs to CC" option, default to 8 (max)
            for zone, zoneData in pairs(MagicMarkerDB.mobdata) do
                for mob, mobData in pairs(zoneData.mobs) do
                    mobData.ccnum = 8
                end
            end
        end

        if version < 5 then
            local ccopt
            -- Changed to non-prioritized cc-list for mobs
            for zone, zoneData in pairs(MagicMarkerDB.mobdata) do
                for mob, mobData in pairs(zoneData.mobs) do
                    ccopt = {}
                    for _, ccid in pairs(mobData.cc) do
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
            for zone, zoneData in pairs(MagicMarkerDB.mobdata) do
                zoneData.handler = nil -- oops, didn't mean to store that in there!
                for mob, mobData in pairs(zoneData.mobs) do
                    mobData.ccpriority = 6 -- default ccpriority to "same as tank"
                end
            end
        end

        if version < 8 then
            for zone, zoneData in pairs(MagicMarkerDB.mobdata) do
                for mob, mobData in pairs(zoneData.mobs) do
                    mobData.cc = nil
                end
            end
        end
        if version < 9 then
            local db = self.db.profile
            local origBehavior = db.mobDataBehavior
            self:Print("Upgrading database. Merging normal and heroic raids into a single entry.")
            db.mobDataBehavior = 2 -- heroic will override normal
            for zoneName in pairs(raids) do
                local zone = MagicMarkerDB.mobdata[zoneName]
                if zone then
                    zone.isRaid = true
                end
                if mergeRaids[zoneName] then
                    local heroicKey = zoneName .. "Heroic"
                    local heroicZone = MagicMarkerDB.mobdata[heroicKey]
                    if heroicZone then
                        if zone then
                            heroicZone.name = zone.name
                        end
                        self:MergeZoneData(zoneName, heroicZone)
                        MagicMarkerDB.mobdata[heroicKey] = nil
                    end
                end
            end
            db.mobDataBehavior = origBehavior
        end
        if version < 10 then
            local origBehavior = MagicMarkerDB.mobDataBehavior
            MagicMarkerDB.mobDataBehavior = 1 -- learned will override imported
            -- Fix bad imported data from MagicMarker_Data
            for zoneName in pairs(dungeon_tiers.bc) do
                local heroicKey = zoneName.."Heroic"
                local zoneDetected = MagicMarkerDB.mobdata[zoneName]
                local zoneImported = MagicMarkerDB.mobdata[heroicKey]
                MagicMarkerDB.mobdata[heroicKey] = nil
                if zoneImported ~= nil then
                    if zoneDetected == nil then
                        MagicMarkerDB.mobdata[zoneName] = zoneImported
                    else
                        self:MergeZoneData(zoneName, zoneImported)
                    end
                end
            end
            MagicMarkerDB.mobDataBehavior = origBehavior
        end
        if version < 11 then
            local origBehavior = MagicMarkerDB.mobDataBehavior
            MagicMarkerDB.mobDataBehavior = 1 -- learned will override imported
            -- Fix bad imported data from MagicMarker_Data
            for zoneName in pairs(raids) do
                local importKey = zoneName.."Normal"
                local zoneDetected = MagicMarkerDB.mobdata[zoneName]
                local zoneImported = MagicMarkerDB.mobdata[importKey]
                mod:debug("Import key = %s, zoneNAme = %s, zoneDetected = %s, zoneImported = %s", importKey, zoneName, zoneDetected and "found" or "not found", zoneImported and "found" or  "not found")
                MagicMarkerDB.mobdata[importKey] = nil
                if zoneImported ~= nil then
                    zoneImported.isRaid = true
                    if zoneDetected == nil then
                        MagicMarkerDB.mobdata[zoneName] = zoneImported
                    else
                        self:MergeZoneData(zoneName, zoneImported)
                    end
                elseif zoneDetected then
                    zoneDetected.isRaid = true
                end
            end
            MagicMarkerDB.mobDataBehavior = origBehavior
        end
        MagicMarkerDB.version = CONFIG_VERSION
    end
end

local keyBindingOrder = 1000

local function AddKeyBinding(keyname, name, desc)
    _G["BINDING_NAME_" .. keyname] = name
    options.args.options.args.keybindings.args[keyname] = {
        name = name,
        desc = desc or desc,
        type = "keybinding",
        arg = keyname,
        order = keyBindingOrder,
    }
    keyBindingOrder = keyBindingOrder + 1
end

function mod:AboutMagicMarker()
    self:Print("|cffafa4ffAuthor:|r David Hedbor <neotron@gmail.com>")
    self:Print("|cffafa4ffDescription:|r Automated smart raid marking to speed up trash clearing in instance runs.")
    self:Print("|cffafa4ffVersion:|r" .. self.version)
    self:Print("|cffafa4ffHosted by:|r WowAce.com - thanks guys!")
    self:Print("|cffafa4ffPowered by:|r Ace3")
end

function mod:GetOptions()
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

AddKeyBinding("MAGICMARKINCREASEPRIO", L["Increase mob priority"], L["INCREASE PRIO HELP"])
AddKeyBinding("MAGICMARKDECREASEPRIO", L["Decrease mob priority"], L["DECREASE PRIO HELP"])
AddKeyBinding("MAGICMARKINCREASEPRIOCC", L["Increase CC mob priority"], L["INCREASE CC PRIO HELP"])
AddKeyBinding("MAGICMARKDECREASEPRIOCC", L["Decrease CC mob priority"], L["DECREASE CC PRIO HELP"])
AddKeyBinding("MAGICMARKSWAPTYPE", L["Toggle mob category"], L["SWAP TYPE HELP"])

LibStub("AceConfig-3.0"):RegisterOptionsTable(L["Magic Marker"],
        function(name)
            return (name == "dialog" and options) or cmdoptions
        end,
        { "mm", "magic", "magicmarker" })

