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
along with mod.  If not, see <http://www.gnu.org/licenses/>.
**********************************************************************
]]

local mod = LibStub("AceAddon-3.0"):NewAddon("MagicMarker", "AceConsole-3.0",
        "AceEvent-3.0", "AceTimer-3.0",
        "LibLogger-1.0")
MagicMarker = mod
local MagicMarker = MagicMarker
local MagicComm   = LibStub("MagicComm-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("MagicMarker", false)

mod.MAJOR_VERSION = "MagicMarker-1.0"
mod.MINOR_VERSION = tonumber('@project-revision@') or tonumber(("$Revision$"):match("%d+"))

-- Upvalue of global functions
local GetBindingKey = GetBindingKey
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local GetRaidTargetIndex = GetRaidTargetIndex
local GetRealZoneText = GetRealZoneText
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local IsAltKeyDown = IsAltKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsInInstance = IsInInstance
local UnitIsGroupLeader = UnitIsGroupLeader
local IsInRaid = IsInRaid
local UnitIsGroupAssistant = UnitIsGroupAssistant
local IsShiftKeyDown = IsShiftKeyDown
local LibStub = LibStub
local SendChatMessage = SendChatMessage
local SetRaidTarget = SetRaidTarget
local UnitAffectingCombat = UnitAffectingCombat
local UnitCanAttack = UnitCanAttack
local UnitClass = UnitClass
local UnitCreatureType = UnitCreatureType
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local UnitIsDead = UnitIsDead
local UnitIsPlayer = UnitIsPlayer
local UnitLevel = UnitLevel
local UnitName = UnitName
local UnitPlayerControlled = UnitPlayerControlled
local UnitSex = UnitSex
local GetInstanceInfo = GetInstanceInfo
local GetDifficultyInfo = GetDifficultyInfo
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo

local format = string.format
local ipairs = ipairs
local next = next
local pairs = pairs
local sort = table.sort
local strfind = strfind
local strlen = strlen
local sub = string.sub
local tinsert = tinsert
local tonumber = tonumber
local tostring = tostring
local type = type

-- Number of CC used for each crowd control method
local networkData = { }

-- class makeup of the party/raid
local raidClassList = {}
local raidClassNames = {}
-- Spell ID to CC id mapping (upvalued)
local spellIdToCCID

-- More upvalues
local mobdata
local db

-- New method data 
local markedTargets = {}    -- [mark] => data
local tankPriorityList = {} -- ordered array of known targets
local ccPriorityList = {}   -- ordered array of known ccable targets
local assignedTargets = {}  -- guid => data
local externalTargets = {}  -- [mark] => data
local templateTargets = {}  -- [mark] => data
local playerName

local cleu_parser = CreateFrame("Frame")
cleu_parser.OnEvent = function(frame, event, ...)
    mod.HandleCombatEvent(mod,event,...)
end
cleu_parser:SetScript("OnEvent", cleu_parser.OnEvent)

local cleu_subevents = {
    ["SPELL_AURA_APPLIED"] = true,
    ["UNIT_DIED"] = true,
    ["PARTY_KILL"] = true,
}

local function ends_with(str, ending)
    return ending == "" or str:sub(-#ending) == ending
end

local function ends_with(str, ending)
    return ending == "" or str:sub(-#ending) == ending
end

-- CC Classes, matches CC_LIST in Config.lua. Tank/kite has no classes specified for it
local CC_CLASS = {
    false, "MAGE", "WARLOCK", "PRIEST", "DRUID", "HUNTER", false ,
    "PRIEST", "WARLOCK", "ROGUE", "WARLOCK", "DRUID",
    "DRUID", "PALADIN", "HUNTER", "WARLOCK", "PALADIN", "ROGUE",false,
    "SHAMAN", "PALADIN"
}


local defaultConfigDB = {
    profile = {
        filterdead = false,
        autolearncc = true,
        acceptCCPrio = false,
        acceptMobData = false,
        acceptRaidMarks = false,
        battleMarking = false,
        honorMarks = false,
        honorRaidMarks = true,
        logLevel = 3,
        mobDataBehavior = 1,
        resetRaidIcons = true,
        modifier = "ALT",
        minTankTargets = 1,
        noCombatRemark = true,
        burnDownIsTank = false
    }
}

local function SetNetworkData(cmd, data, misc1, misc2, misc3, misc4)
    networkData.cmd = cmd
    networkData.data = data
    networkData.misc1 = misc1
    networkData.misc2 = misc2
    networkData.misc3 = misc3
    networkData.misc4 = misc4
    networkData.dbversion = MagicMarkerDB.version
end

local function SetExternalTarget(id, guid, uid, name, hash)
    if id and id > 0 and id < 9 then
        externalTargets[id].guid = guid
        externalTargets[id].uid  = uid
        externalTargets[id].name = name
        externalTargets[id].mark = guid and id or nil
        externalTargets[id].hash = hash
    end
end

local function SetTemplateTarget(id, name, network)
    if id and id > 0 and id < 9 then
        templateTargets[id].guid = name and UnitGUID(name) or nil
        templateTargets[id].name = name
        templateTargets[id].uid  = name
        templateTargets[id].mark = name and id or nil
        if name then
            SetExternalTarget(id)
            for oid = 1, 8 do
                -- We can only have the same template target once so clean it up
                if oid ~= id and templateTargets[oid].name == name then
                    SetTemplateTarget(oid)
                end
            end
            if not network then
                SetNetworkData("MARKV2", name, id, "TMPL")
                mod:SendUrgentMessage()
            end
        end
    end
end

local function LowSetTarget(id, uid, val, ccid, guid)
    if id and id > 0 and id < 9 then
        markedTargets[id].guid  = guid
        markedTargets[id].uid  = uid
        markedTargets[id].ccid  = ccid
        markedTargets[id].value = val
    end
end

local function GUIDToUID(guid)
    local _, _, _, _, _, npc_id = strsplit("-",guid);
    if npc_id == 0 then
        return nil
    end
    return tostring(npc_id)
end

-- Returns [id, difficulty string, isHeroic]
function mod:GetDifficultyInfo()
    if GetDifficultyInfo then
        local _,instype, diffid, diffname = GetInstanceInfo()
        if instype ~= "none" and diffid and diffid > 0 then
            local name, _, heroic = GetDifficultyInfo(diffid)
            -- Classic Era has GetDifficultyInfo but it returns nothing
            if name then
                return diffid, name, heroic
            end
        end
    end
    return 0, "Normal", false
end

-- Returns [GUID, UID, Name]
function mod:GetUnitID(unit)
    local guid, uid
    local unitName = UnitName(unit)
    guid = UnitGUID(unit)
    uid = GUIDToUID(guid)
    return guid, uid or mod:SimplifyName(unitName), unitName
end

function mod:IsClassic()
    return (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC)
end

function mod:IsBurningCrusadeClassic()
    return (WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC)
end

function mod:IsWrathClassic()
    return (WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC)
end

function mod:OnInitialize()
    -- Set up the config database
    self.db = LibStub("AceDB-3.0"):New("MagicMarkerConfigDB", defaultConfigDB, "Default")
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileDeleted","OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

    -- this is the mob database
    MagicMarkerDB = MagicMarkerDB or { }
    MagicMarkerDB.frameStatusTable = MagicMarkerDB.frameStatusTable or {}

    MagicMarkerDB.unitCategoryMap = nil -- Delete old data, no way to convert since it's missing zone info

    mobdata = MagicMarkerDB.mobdata or {}
    MagicMarkerDB.mobdata = mobdata
    db = self.db.profile
    -- Buggy FuBar_MM caused these to be stored as strings
    db.logLevel = tonumber(db.logLevel)
    db.mobDataBehavior = tonumber(db.mobDataBehavior)
    db.remarkDelay = nil -- no longer needed

    self:UpgradeDatabase()


    -- sets ccprio/raid target defaults
    self:FixProfileDefaults()

    -- This is moved to the profile
    if MagicMarkerDB.targetdata then
        db.targetdata = MagicMarkerDB.targetdata
        MagicMarkerDB.targetdata = nil
    end

    self:SetLogLevel(db.logLevel)
    self.commPrefix = "MagicMarker"
    self.commPrefixRT = "MagicMarkerRT"

    -- no longer used
    MagicMarkerDB.debug = nil
    MagicMarkerDB.logLevel = nil

    for id = 0,9 do
        markedTargets[id] = {}
        externalTargets[id] = {}
        templateTargets[id] = {}
    end

    spellIdToCCID = MagicComm.spellIdToCCID
end

function mod:OnEnable()
    mod:SetupLDB()
    playerName = UnitName("player")

    self:RegisterEvent("ZONE_CHANGED_NEW_AREA","ZoneChangedNewArea")
    self:ZoneChangedNewArea()
    self:GenerateOptions()
    self:RegisterChatCommand("mmtmpl", function() mod:Print("This command is deprected. Use |cffdfa9cf/mm tmpl|r or |cffdfa9cf/magic tmpl|r instead.")  end, false, true)

    MagicComm:RegisterListener(self, "MM")
end

function mod:OnDisable()
    MagicComm:UnregisterListener(self, "MM")
    self:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
    self:UnregisterChatCommand("magic")
    self:DisableEvents()
end

function mod:OnMobdataReceive(zone, data, version, sender)
    if version ~= MagicMarkerDB.version then
        if self.hasTrace then self:trace("[Net] MagicMarkerDB version mismatch (got = %s, have %d).", tostring(version), MagicMarkerDB.version) end
        return
    end
    if db.acceptMobData then
        if self.hasDebug then self:debug("[Net] Received mob data for %s from %s.", data.name, sender) end
        self:MergeZoneData(zone, data)
    end
    self:NotifyChange()
end

function mod:OnMobdataPartialReceive(data, version, sender)
    if version ~= MagicMarkerDB.version then
        if self.hasTrace then self:trace("[Net] MagicMarkerDB version mismatch (got = %s, have %d).", tostring(version), MagicMarkerDB.version) end
        return
    end
    if db.acceptMobData then
        if self.hasDebug then self:debug("[Net] Received partial mob database update from %s.", sender) end
        for zone, zonedata in pairs(data) do
            self:MergeZoneData(zone, zonedata, nil, true)
        end
    end
    self:NotifyChange()
end

function mod:OnTargetReceive(data, version, sender)
    if version ~= MagicMarkerDB.version then
        if self.hasTrace then self:trace("[Net] MagicMarkerDB version mismatch (got = %s, have %d).", tostring(version), MagicMarkerDB.version) end
        return
    end
    if db.acceptRaidMarks then
        if self.hasDebug then self:debug("[Net] Received raid mark configuration from %s.", sender) end
        db.targetdata = data
    end
    self:NotifyChange()
end

function mod:OnCCPrioReceive(data, version, sender)
    if version ~= MagicMarkerDB.version then
        if self.hasTrace then self:trace("[Net] MagicMarkerDB version mismatch (got = %s, have %d).", tostring(version), MagicMarkerDB.version) end
        return
    end
    if db.acceptCCPrio then
        if self.hasDebug then self:debug("[Net] Received crowd control prioritizations %s.", sender) end
        db.ccprio = data
    end
    self:NotifyChange()
end


local function InsertUnitData(unitdata, hash)
    for id, data in ipairs(hash) do
        if data.guid == unitdata.guid then
            hash[id] = unitdata
            return
        end
    end
    hash[#hash+1] = unitdata
end

function mod:OnCommUnmarkV2(guid, mark, sender)
    local data = assignedTargets[guid]
    local changed = mod:SmartMark_RemoveGUID(guid, mark, true)
    local name = guid
    if self.hasDebug then
        name = (data and data.name) or name
        if not sender then sender = "Unknown" end
    end
    if changed then
        if self.hasDebug then self:debug("[Net:%s] Removing %s from %s.", sender, self:GetTargetName(mark), name) end
    elseif self.hasTrace then
        self:trace("[Net:%s] Already removed %s from %s.", sender, self:GetTargetName(mark), name)
    end
end

local verRespMsg = "%s: %s revision %s"

function mod:OnVersionResponse(ver, major, minor, sender)
    self:Print(format(verRespMsg, sender or "Unknown Sender", major or "Unknown", minor or "Unknown"))
end

function mod:QueryAddonVersions()
    SetNetworkData("VCHECK")
    self:SendUrgentMessage("GUILD")
    self:SendUrgentMessage("RAID")
end


-- Queue data to be sent after modifying the configuration data
local queuedData = {}
local queuedDataTimer

function mod:QueueData_Add(zone, mob, hash)
    if not queuedData[zone] then
        queuedData[zone] = {}
    end
    queuedData[zone][mob] = hash
    self:QueueData_Schedule()
    if self.hasSpam then self:spam("Queued %s in zone %s for partial update.", hash.name, zone) end
end

function mod:QueueData_Schedule()
    if queuedDataTimer then
        self:CancelTimer(queuedDataTimer, true)
    end
    queuedDataTimer = self:ScheduleTimer("QueueData_Send", 5)
end

function mod:QueueData_Send()
    if InCombatLockdown() then
        self:QueueData_Schedule()
        return
    end
    SetNetworkData("MOBDATA_PARTIAL", queuedData)
    self:SendBulkMessage("RAID")
    for id,data in pairs(queuedData) do
        queuedData[id] = nil
    end
end


-- This allows importing from the MagicMarker_Data addon

function mod:ImportData(data, version, reallyImport)
    if MagicMarkerDB.importedVersion and MagicMarkerDB.importedVersion >= version then
        return
    end

    if reallyImport then
        for zone,zoneData in pairs(data) do
            if mod.raids[zone] then
                zoneData.isRaid = true
            elseif zoneData.heroic and ends_with(zone, "Heroic") then
                zone = gsub(zone, "Heroic", "")
            elseif not zoneData.heroic and not ends_with(zone, "Normal") then
                zone = zone .. "Normal"
            end
            self:MergeZoneData(zone, zoneData, true)
        end
        MagicMarkerDB.importedVersion = version
    else
        local popup = _G.StaticPopupDialogs
        if type(popup) ~= "table" then popup = {} end
        if type(popup["MMImportQuery"]) ~= "table" then
            popup["MMImportQuery"] = {
                text = L["MagicMarker_Data version newer than the previously imported data. Do you want to import it?"],
                button1 = L["Yes"],
                button2 = L["No"],
                whileDead = 1,
                hideOnEscape = 1,
                timeout = 0,
                OnAccept = function() mod:ImportData(data, version, true) end

            }
        end
        StaticPopup_Show("MMImportQuery")
    end
end

function mod:MergeCCMethods(dest, source)
    if not source or not source.ccopt or not dest then return end
    if not dest.ccopt then
        dest.ccopt = source.ccopt
        return
    end
    for id in pairs(source.ccopt) do
        dest.ccopt[id] = true
    end
end

function mod:MergeZoneData(zone, zoneData, override, partial)
    local localData = mobdata[zone]
    local localMob, simpleName
    if self.hasDebug then self:debug("Merging data for zone %s [%s].", zoneData.name or zone, zone) end
    if not partial and (not localData or (db.mobDataBehavior == 3 and not override)) then  -- replace
        if self.hasTrace then self:trace("Replacing local data with networked data.") end
        mobdata[zone] = zoneData
    elseif localData then
        if zoneData.isRaid then
            localData.isRaid = zoneData.isRaid
        end
        localData = localData.mobs
        if zoneData.mobs then
            zoneData = zoneData.mobs
        end
        for mob, data in pairs(zoneData) do
            -- Enable me for 2.4 to handle numeric ID keys
            simpleName = self:SimplifyName(mob.name)
            if simpleName ~= mob then
                -- mob is a 2.4 numeric ID
                if localData[simpleName] then
                    localData[mob] = localData[simpleName]
                    localData[simpleName] = nil
                end
            else
                for lm, ld in pairs(localData) do
                    simpleName = self:SimplifyName(ld.name)
                    if simpleName == mob then
                        -- We found a numeric id locally, use that instead
                        mob = lm
                        break
                    end
                end
            end
            if not localData[mob] or (db.mobDataBehavior == 2 and not override) or
                    (db.mobDataBehavior == 3 and partial) then
                if self.hasTrace then self:trace("Replacing entry for %s from merged data.", data.name) end
                local oldData = localData[mob]
                localData[mob] = data
                self:MergeCCMethods(data, oldData)
            else
                if self.hasTrace then self:trace("Adding additional crowd control methods for %s from merged data.", data.name) end
                self:MergeCCMethods(localData[mob], data)
            end
        end
    end

    if mobdata[zone] then
        self:AddZoneConfig(zone, mobdata[zone])
    end
end

function mod:BroadcastZoneData(zone)
    zone = mod:SimplifyName(zone)
    if mobdata[zone] then
        SetNetworkData("MOBDATA", mobdata[zone], zone)
        self:SendBulkMessage()
    end
end

function mod:BroadcastAllZones()
    for zone, data in pairs(mobdata) do
        SetNetworkData("MOBDATA", data, zone)
        self:SendBulkMessage()
    end
end

function mod:BroadcastRaidTargets()
    if self.hasTrace then self:trace("Broadcast raid target data to the raid.") end
    SetNetworkData("TARGETS", db.targetdata)
    self:SendBulkMessage()
end

function mod:BroadcastCCPriorities()
    if self.hasTrace then self:trace("Broadcast cc priority data to the raid.") end
    SetNetworkData("CCPRIO", db.ccprio)
    self:SendBulkMessage()
end

function mod:HandleCombatEvent()
    local timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags,
    sourceRaidFlags, guid, name, destflags, destRaidFlags, spellid, spellname = CombatLogGetCurrentEventInfo()

    -- bail out early if we don't care for the subevent
    if not cleu_subevents[event] then return end

    if event == "UNIT_DIED" or event == "PARTY_KILL" then
        local data = assignedTargets[guid]

        if data then
            if self.hasDebug then self:debug("Releasing %s from dead mob %s.", self:GetTargetName(data.mark), name) end
            mod:SmartMark_RemoveGUID(guid, data.mark, false, true)
        end
        -- Special Thaddius hack; Stalagg and Feugen never dies, so unmark if we detect Thaddius death
        if mod.unmarkThaddiusAdds and GUIDToUID(guid) == "15928" then
            mod.unmarkThaddiusAdds = nil
            for id,mobdata in pairs(tankPriorityList) do
                local uid = GUIDToUID(mobdata.guid)
                if uid == "15929" or uid == "15930" then
                    mod:SmartMark_RemoveGUID(mobdata.guid, mobdata.mark, false, true)
                end
            end
        end
        return
    end
    if db.autolearncc and event == "SPELL_AURA_APPLIED" then
        local ccid = spellIdToCCID[spellid]
        if not ccid then return end
        local uid = GUIDToUID(guid)
        if not uid then return end

        local hash, zone = self:GetUnitHash(uid, true)
        if hash then
            if not hash.ccopt then
                hash.ccopt = {}
            end
            local addcc = function(newccid)
                if not hash.ccopt[newccid] then
                    hash.ccopt[newccid] = true
                    self:QueueData_Add(zone, hash)
                    if self.hasDebug then
                        self:debug("Learned that %s can be CC'd with %s",
                                hash.name, spellname)
                    end
                end
            end
            if type(ccid) == "table" then
                for id = 1,#ccid do
                    addcc(ccid[id])
                end
            elseif type(ccid) == "number" then
                addcc(ccid)
            end
            self:NotifyChange()
        end
    end
end

do
    local notPvPInstance = { raid = true, party = true }
    function mod:ZoneChangedNewArea()
        local zone,name = self:GetZoneName()
        if zone == nil or zone == "" then
            self:ScheduleTimer(self.ZoneChangedNewArea,5,self)
        else
            local zoneData = mobdata[zone]
            local enableLogging
            if not zoneData or zoneData.mm == nil then
                local inInstance, type = IsInInstance()
                enableLogging = inInstance and notPvPInstance[type]
            else
                enableLogging = zoneData.mm
            end

            if enableLogging then
                self:EnableEvents(zoneData and zoneData.targetMark)
            else
                self:DisableEvents()
            end
        end
    end
end

function mod:RegisterMMFu(plugin)
    if self.hasWarn then
        self:warn("Please uninstall FuBar_mod. It does no longer work with this version of Magic Marker. Instead there's a built-in LDB data provider.")
    end
end

function mod:EnableEvents(markOnTarget)
    if not self.addonEnabled then
        self.addonEnabled = true
        mod:UpdateLDB()
        if self.hasInfo then self:info(L["Magic Marker enabled."]) end
        if markOnTarget then
            self:RegisterEvent("PLAYER_TARGET_CHANGED", "SmartMark_MarkUnit", "target")
        end
        self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", "SmartMark_MarkUnit", "mouseover")
        self:RegisterEvent("PLAYER_REGEN_ENABLED", "ScheduleGroupScan")
        self:RegisterEvent("GROUP_ROSTER_UPDATE", "ScheduleGroupScan")
        cleu_parser:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        self:ScheduleGroupScan()
    end
end

function mod:DisableEvents()
    if self.addonEnabled then
        self.addonEnabled = false
        mod:UpdateLDB()
        if self.hasInfo then self:info(L["Magic Marker disabled."]) end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED") -- rescan group every time we exit combat.
        self:UnregisterEvent("PLAYER_TARGET_CHANGED")
        self:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
        self:UnregisterEvent("RAID_ROSTER_UPDATE")
        self:UnregisterEvent("PARTY_MEMBERS_CHANGED")
        cleu_parser:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
end

function mod:ToggleMagicMarker()
    if self.addonEnabled then
        self:DisableEvents()
    else
        self:EnableEvents()
    end
end

local party_idx = { "party1", "party2", "party3", "party4" }

function mod:MarkRaidTargets()
    if self.hasDebug then self:debug("Making all targets of the raid.") end
    self:IterateGroup(function (self, unit) self:SmartMark_MarkUnit(unit.."target") end, true)
end

local groupScanTimer

function mod:LogClassInformation(unitName, class)
    if not class then _,class = UnitClass(unitName)  end
    if class then
        if self.hasTrace then self:trace("  found %s => %s.", unitName, class) end
        raidClassList[class] = (raidClassList[class] or 0) + 1
        class = class:upper()
        raidClassNames[class] = raidClassNames[class] or {}
        raidClassNames[class][#raidClassNames[class] +1] = unitName
    elseif self.hasWarn then
        self:warn(L["Unable to determine the class for %s."], unitName)
    end
end

function mod:ScanGroupMembers()
    if raidClassList.FAKE then return end
    for id,_ in pairs(raidClassList) do raidClassList[id] = 0 end
    for id,_ in pairs(raidClassNames) do
        for num, _ in ipairs(raidClassNames[id]) do
            raidClassNames[id][num] = nil
        end
    end

    if UnitClass("player") then
        if self.hasTrace then self:trace("Rescanning raid/party member classes.") end
        self:IterateGroup(self.LogClassInformation)
    end
end


function mod:CacheRaidMarkForUnit(unit)
    local id = GetRaidTargetIndex(unit)
    if id then
        MagicMarkerDB.raidMarkCache[unit] = id
        if self.hasDebug then self:debug("Cached "..id.." for "..unit); end
    end
end

function mod:CacheRaidMarks()
    MagicMarkerDB.raidMarkCache = {}
    if self.hasDebug then self:debug("Caching raid / party marks.") end
    self:IterateGroup(self.CacheRaidMarkForUnit)
end

function mod:MarkRaidFromCache()
    if not MagicMarkerDB.raidMarkCache then
        return
    end
    for unit,id in pairs(MagicMarkerDB.raidMarkCache) do
        if markedTargets[id].uid and markedTargets[id].uid ~= unit then
            mod:SmartMark_RemoveGUID(markedTargets[id].guid, nil, nil, true)
        end
        SetTemplateTarget(id, unit)
        self:SetRaidTarget(unit, id)
    end
    self:SmartMark_RecalculateMarks()
end

function mod:IterateGroup(callback, useID, ...)
    local id, name
    if self.hasSpam then self:spam("Iterating group...") end

    if IsInRaid() then
        local maxgrp, class, groupid, online, dead
        local playerName = UnitName("player")
        local zoneID, zone = self:GetZoneName()

        maxgrp = self.zoneGroupNum[zoneID]

        for id = 1,GetNumGroupMembers() do
            name, _, groupid, _, _, class, _, online, dead = GetRaidRosterInfo(id)
            if name == playerName or (online and (not db.filterdead or not dead) and (not maxgrp or groupid <= maxgrp)) then
                callback(self, (useID and "raid"..id) or name, class, ...)
            end
        end
    else
        if GetNumGroupMembers() > 0 then
            for id = 1,GetNumGroupMembers()-1 do
                callback(self, (useID and party_idx[id]) or UnitName(party_idx[id]), nil, ...)
            end
        end
        callback(self, (useID and "player") or UnitName("player"), nil, ...);
    end
end

function mod:MarkRaidFromTemplate(template)
    if self.hasDebug then self:debug("Marking from template: "..template) end
    local usedMarks = {}
    if template == "arch" or template == "archimonde" then
        self:IterateGroup(mod.MarkTemplates.decursers.func, false, usedMarks)
        self:IterateGroup(mod.MarkTemplates.shamans.func, false, usedMarks)
    elseif mod.MarkTemplates[template] and mod.MarkTemplates[template].func then
        self:IterateGroup(mod.MarkTemplates[template].func, false, usedMarks)
    else
        if self.hasWarn then self:warn(L["Unknown raid template: %s"], template) end
    end

    if next(usedMarks) then
        for id in pairs(usedMarks) do
            if markedTargets[id].uid and markedTargets[id].uid ~= usedMarks[id] then
                mod:SmartMark_RemoveGUID(markedTargets[id].guid, nil, nil, true)
            end
            SetTemplateTarget(id, usedMarks[id])
        end
        self:SmartMark_RecalculateMarks()
    end
end

function mod:ScheduleGroupScan()
    if groupScanTimer then self:CancelTimer(groupScanTimer, true) end
    groupScanTimer = self:ScheduleTimer("ScanGroupMembers", 5)
end


-- Return whether a target is eligable for marking
local function UnitIsEligable (unit)
    local type = UnitCreatureType(unit)
    return UnitExists(unit)
            and (UnitCanAttack("player", unit) or UnitIsEnemy("player", unit))
            and not UnitIsDead(unit)
            and  type ~= "Critter" and type ~= "Totem"
            and not UnitPlayerControlled(unit)  and not UnitIsPlayer(unit)
end

-- Return the hash for the unit of NIL if it's not available
function mod:GetUnitHash(uid, currentZone)
    if not uid then return end
    if currentZone then
        local zone = mod:GetZoneName()
        local tmpHash = mobdata[zone]
        if tmpHash then
            return tmpHash.mobs[uid], zone
        end
    end
    for zone, data in pairs(mobdata) do
        if data.mobs[uid] then
            return data.mobs[uid], zone
        end
    end
end


local unitValueCache = {}

function mod:UnitValue(uid, hash, modifier)
    --   if unitValueCache[unit] then return unitValueCache[unit] end
    local unitData = hash or self:GetUnitHash(uid, true)
    local value, ccvalue = 0, 0
    if not modifier then modifier = 0 end
    if unitData then
        value = 10-unitData.priority
        if value > 0 then
            value = value * 2 + 2-unitData.category -- Tank > CC
        end

        if unitData.ccpriority == 6 then
            ccvalue = value
        else
            ccvalue = 10-unitData.ccpriority
            if ccvalue > 0 then
                ccvalue = ccvalue * 2 -- Tank > CC
            end
        end
    end
    if self.hasTrace then self:trace("Unit Value for %s = [%d, %d]", uid, value, ccvalue) end
    --   unitValueCache[unit]  = value
    return value+modifier, ccvalue+modifier, unitData
end

local function IsModifierPressed()
    if GetBindingKey("MAGICMARKSMARTMARK") then
        return mod.markKeyDown
    elseif db.modifier == "ALT" then
        return IsAltKeyDown()
    elseif db.modifier == "SHIFT" then
        return IsShiftKeyDown()
    elseif db.modifier == "CTRL" then
        return IsControlKeyDown()
    end
end

local function SmartMark_TankSorter(unit1, unit2)
    if unit1.value == unit2.value then
        return unit1.guid < unit2.guid -- ensure stable sort
    else
        return (unit1.value or 0) > (unit2.value or 0)
    end
end

local function SmartMark_CCSorter(unit1, unit2)
    if unit1.ccval == unit2.ccval then
        return (unit1.guid or "") < (unit2.guid or "") -- ensure stable sort
    else
        return ( unit1.ccval or 0) > (unit2.ccval or 0) -- should never happen.. but it does!?
    end
end

function mod:OnAssignData(targets, sender)
    if not sender then sender = "Unknown" end
    if self.hasDebug then self:debug("[Net:%s] Received assignment data.", sender) end
    --   for id in pairs(tankPriorityList) do
    --      tankPriorityList[id] = nil
    --      ccPriorityList[id] = nil
    --   end
    for guid,data in pairs(targets) do
        if not data.hash or not data.ccval then
            if self.hasWarn then self:warn("[Net:%s] Assignment data is not compatible. Ignoring.", sender) end
            return
        end
        data.guid = guid
        -- Set the right "value" parameter
        data.val = nil
        data.sender = sender
        InsertUnitData(data, tankPriorityList)
        if data.hash.ccopt then
            InsertUnitData(data, ccPriorityList)
        end
    end
    sort(tankPriorityList, SmartMark_TankSorter)
    sort(ccPriorityList, SmartMark_CCSorter)
    self:SmartMark_RecalculateMarks(true)
    self:UpdateLDBCount()
end

function mod:IsValidMarker()
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") or not IsInRaid()
end

-- This is solely for debugging purposes
-- i.e /dump mod.smdata
mod.smdata = {
    tank = tankPriorityList,
    cc = ccPriorityList,
    assigned = assignedTargets,
    external = externalTargets,
    tmpl = templateTargets,
    marked = markedTargets
}

local valueModifier = 0.99

local function SmartMark_FindUnusedMark(list, used)
    for _,id in pairs(list) do
        if not used[id] then
            used[id] = true
            return id
        end
    end
end

-- recalculate mark assignments based on the priority lists

do
    local ccUsed = {}
    local marksUsed = {}
    local categoryMarkCache = {}
    local newCcCount = {}

    function mod:OnCommResetV2()
        if self.hasDebug then
            self:debug("[Net] Raid cache clear received.")
        end

        valueModifier = 0.99

        for id in pairs(ccUsed)            do ccUsed[id] = nil            end
        for id in pairs(newCcCount)        do newCcCount[id] = nil        end
        for id in pairs(assignedTargets)   do assignedTargets[id] = nil   end
        for id in pairs(categoryMarkCache) do categoryMarkCache[id] = nil end
        for id in pairs(tankPriorityList)  do tankPriorityList[id] = nil  end
        for id in pairs(ccPriorityList)    do ccPriorityList[id] = nil    end

        for id = 1,8 do
            LowSetTarget(id)
            SetExternalTarget(id)
            SetTemplateTarget(id)
            marksUsed[id] = nil
        end
        mod:SetTargetCount(0, 0)
    end

    function mod:SmartMark_RecalculateMarks(network)
        local id, data, ccount
        local inCombat = InCombatLockdown()
        local canReprioritize = not inCombat or not next(assignedTargets)
        -- empty data from the previous run
        for id in pairs(categoryMarkCache) do categoryMarkCache[id] = nil end
        for id in pairs(markedTargets)     do LowSetTarget(id)  end

        if canReprioritize then
            -- reprioritize mid-combat
            for id in pairs(ccUsed)            do ccUsed[id] = nil            end
            for id in pairs(newCcCount)        do newCcCount[id] = nil        end
            for id in pairs(marksUsed)         do marksUsed[id] = nil         end
            for id in pairs(assignedTargets)   do assignedTargets[id] = nil   end
        end


        if self.hasDebug then self:debug("Recalculating mark priority list:") end

        -- cache external targets
        for id = 1,8 do
            if db.honorMarks and externalTargets[id].guid then
                marksUsed[id] = true
                assignedTargets[externalTargets[id].guid] = externalTargets[id]
                if self.hasDebug then self:debug("++ %s => %s [external]", self:GetTargetName(id), externalTargets[id].name) end
            elseif templateTargets[id].guid then
                marksUsed[id] = true
                assignedTargets[templateTargets[id].guid] = templateTargets[id]
                if self.hasDebug then self:debug("++ %s => %s [tmpl]", self:GetTargetName(id), templateTargets[id].name) end
            end
        end

        -- This will hard-prioritize network assigned targets
        local assignedCount = 0

        for id,data in ipairs(tankPriorityList) do
            if data.sender and data.sender ~= playerName and data.mark then
                if self.hasTrace then self:trace("Reserving %s for %s (from %s).", self:GetTargetName(data.mark), data.name, data.sender) end
                assignedTargets[data.guid] = data
                marksUsed[data.mark] = true
                if data.ccused ~= 1 then
                    assignedCount = assignedCount + 1
                    ccUsed[data.ccused] = (ccUsed[data.ccused] or 0) + 1
                    newCcCount[ data.uid ] = (newCcCount[ data.uid ] or 0) + 1
                end
            end
        end

        -- Update list of marks used on the raid
        if db.honorRaidMarks then
            self:IterateGroup(function(self, unit)
                local id = GetRaidTargetIndex(unit)
                if id and not templateTargets[id].guid then
                    local guid = UnitGUID(unit)
                    assignedTargets[guid] = { name = unit, mark = id, guid = guid, uid = unit }
                    marksUsed[id] = true
                    if self.hasDebug then
                        self:debug("++ %s => %s [raid]", self:GetTargetName(id), unit)
                    end
                end
            end)
        end

        -- Calculate marks for crowd control first
        for id = 1, #ccPriorityList do
            data = ccPriorityList[id]
            ccount = newCcCount[data.uid] or 0
            if not assignedTargets[data.guid] and data.hash and ccount < data.hash.ccnum then -- still got more cc for this UID
                for _,category in ipairs(db.ccprio) do
                    local class = CC_CLASS[category]
                    local cc = data.hash.ccopt
                    if cc[category] and (not class or raidClassList[class] and raidClassList[class] > 0) then
                        local cc_used_count = ccUsed[category] or 0
                        if not class or cc_used_count < raidClassList[class] then
                            categoryMarkCache[category] = categoryMarkCache[category] or self:GetMarkForCategory(category)
                            local nextid = SmartMark_FindUnusedMark(categoryMarkCache[category], marksUsed)
                            if nextid then
                                data.mark = nextid
                                data.ccused = category
                                assignedTargets[data.guid] = data
                                newCcCount[ data.uid ] = ccount + 1
                                ccUsed[category] = cc_used_count + 1
                                assignedCount = assignedCount + 1
                                if self.hasDebug then
                                    self:debug("++ %s => %s [%s]", self:GetTargetName(nextid), data.name, self:GetCCName(category) or "none")
                                end
                                break
                            end
                        end
                    end
                end
            end
        end

        if not inCombat then -- Never change cc targets to tank targets during combat
            local maxCCTargets = #tankPriorityList - db.minTankTargets
            -- Ensure we have sufficient available targets for tanking.
            if self.hasTrace then self:trace("Found %d assigned targets, %d CC'd out of %d total, %d minimum (max %d cc'd so need to release %d targets).",
                    assignedCount, #ccPriorityList, #tankPriorityList, db.minTankTargets,  maxCCTargets, assignedCount - maxCCTargets - #ccPriorityList) end

            if assignedCount > maxCCTargets then
                for id = #ccPriorityList, 1, -1 do
                    data = ccPriorityList[id]
                    if (not data.sender or data.sender == playerName) and assignedTargets[data.guid] and (not db.burnDownIsTank or data.ccused ~= self:GetCCID("BURN")) then
                        assignedTargets[data.guid] = nil
                        assignedCount = assignedCount - 1
                        if self.hasDebug then self:debug("-- %s => %s [insufficient tank targets] = %s", self:GetTargetName(data.mark), data.name, data.guid) end
                        marksUsed[data.mark] = nil
                        data.mark = nil

                        if assignedCount <= maxCCTargets then
                            -- released enough
                            break
                        end
                    end
                end
            end
        end

        local tankMarkList = self:GetMarkForCategory(1)
        for id = 1, #tankPriorityList do
            data = tankPriorityList[id]
            if not assignedTargets[data.guid] then
                -- Target is not crowd controlled, make it a tank target
                local nextid = SmartMark_FindUnusedMark(tankMarkList, marksUsed)
                if not nextid then
                    data.mark = nil
                    data.ccused = nil
                    if self.hasDebug then self:debug("== No mark available for %s = %s.", data.name, data.guid) end
                else
                    data.mark = nextid
                    data.ccused = 1
                    assignedTargets[data.guid] = data
                    if self.hasDebug then self:debug("++ %s => %s [tank] = %s", self:GetTargetName(nextid), data.name or "Unknown name", data.guid) end
                end
            end
        end


        self:ScheduleAssignDataSend(network)

        if self.hasDebug then self:debug("Done.") end

        -- TODO - need to rework syncing for this.
        for guid,data in pairs(assignedTargets) do
            if data.ccused then
                LowSetTarget(data.mark, data.uid, data.ccused == 1 and data.value or data.ccval, data.ccused, guid)
            elseif data.uid ~= data.name then
                LowSetTarget(data.mark, data.uid, 0, -1, guid)
            elseif data.mark then
                LowSetTarget(data.mark, data.uid, nil, -2, data.name)
            end
        end
    end

    local updateAssignDataTimer

    function mod:ScheduleAssignDataSend(network)
        if updateAssignDataTimer then
            self:CancelTimer(updateAssignDataTimer, true)
            updateAssignDataTimer = nil
        end
        if not network then
            updateAssignDataTimer = self:ScheduleTimer("SmartMark_SendAssignments", 2.0)
        end
        self:UpdateLDBCount()
    end

    function mod:UpdateLDBCount()
        local total = 0
        local marked = 0
        local mmdata = self:GetMarkData()
        if mmdata  then
            for id, data in pairs(mmdata) do
                if data.uid and data.value then
                    total = total + 1
                    if data.valid then
                        marked = marked + 1
                    end
                end
            end
        end
        mod:SetTargetCount(marked, total)
    end

    local MT
    function mod:SmartMark_SendAssignments()
        if updateAssignDataTimer then
            self:CancelTimer(updateAssignDataTimer, true)
            updateAssignDataTimer = nil
        end
        SetNetworkData("ASSIGN", self:GetAssignData())
        self:SendBulkMessage()
    end

    function mod:SmartMark_AddGUID(guid, uid, name, mobHash)
        for id, data in ipairs(tankPriorityList) do
            if data.guid == guid then
                return data -- already known
            end
        end
        local value, ccval, hash = self:UnitValue(uid, mobHash, valueModifier)
        if hash and self:IsUnitIgnored(hash.priority) then return end

        local newhash = {
            uid = uid,
            name = hash and hash.name or name,
            guid = guid,
            value = value,
            ccval = ccval,
            hash = hash
        }
        valueModifier = valueModifier - 0.001

        tankPriorityList[#tankPriorityList+1] = newhash
        sort(tankPriorityList, SmartMark_TankSorter)

        if newhash.hash and newhash.hash.category == 2 and newhash.hash.ccopt then
            ccPriorityList[#ccPriorityList+1]     = newhash
            sort(ccPriorityList, SmartMark_CCSorter)
        end

        self:SmartMark_RecalculateMarks()
        self:UpdateLDBCount()

        return assignedTargets[guid], newhash
    end

    local function SmartMark_CleanList(hash, guid)
        local found
        for id, data in ipairs(hash) do
            if found then
                hash[id-1] = data
            elseif data.guid == guid then
                if mod.trace then mod:trace(" Found unit to remove: %s", data.guid) end
                found = data
            end
        end
        if found then
            hash[#hash] = nil
        end
        return found
    end

    function mod:SmartMark_RemoveGUID(guid, mark, fromNetwork, delay)
        local changed
        if self.hasTrace then self:trace("Looking for unit on tank list...") end
        local changed = SmartMark_CleanList(tankPriorityList, guid)
        if changed then
            if self.hasTrace then self:trace("Removed from tank list, checking for CC.") end
            if changed.hash.category == 2 and changed.hash.ccopt then
                -- We only clean cc list if needed
                if SmartMark_CleanList(ccPriorityList, guid) and self.hasTrace then self:trace("Removed from cc list...") end
            end
            mark = changed.mark
        end

        if mark then
            if externalTargets[mark] and externalTargets[mark].guid == guid then
                SetExternalTarget(mark)
                if self.hasTrace then self:trace("Removed external target...") end
                changed = true
            end
            if templateTargets[mark] and templateTargets[mark].guid == guid then
                SetTemplateTarget(mark)
                if self.hasTrace then self:trace("Removed template target...") end
                changed = true
            end
        end

        if changed then
            assignedTargets[guid] = nil
            if mark then -- do some cleanup
                LowSetTarget(mark)
                marksUsed[mark] = nil
                if type(changed) == "table" then
                    if changed.ccused then
                        -- Clean up crowd control cache
                        ccUsed[changed.ccused] = (ccUsed[changed.ccused] or 1) - 1
                        newCcCount[changed.uid] = (newCcCount[changed.uid] or 1) - 1
                    end
                end
            end
            if not fromNetwork then
                SetNetworkData("UNMARKV2", guid, mark)
                self:SendUrgentMessage()
            end
            if not InCombatLockdown() and not delay and not fromNetwork then
                -- only recalculate when not in combat or if battlemarking is enabled.
                if self.hasTrace then self:trace("Recalculate due to changed unit lists...") end
                self:SmartMark_RecalculateMarks()
            end
            self:UpdateLDBCount()
        end
        return changed
    end

    function mod:SmartMark_MarkUnit(unit)
        if not UnitExists(unit) then return end
        local unitName = UnitName(unit)
        if UnitIsDead(unit) then
            return
        elseif UnitIsEligable(unit) then
            local unitTarget = GetRaidTargetIndex(unit)
            local guid, uid = mod:GetUnitID(unit)
            local mobHash = self:InsertNewUnit(guid, uid, unitName, unit)
            local data, new

            if not self:IsValidMarker() then
                return
            end

            if not IsModifierPressed() and unit == "mouseover" then
                -- Modifier isn't pressed and it's a mouseover, so return
                return
            end

            -- Special hack for Thaddius, adds don't die...
            if uid == "15929" or uid == "15930" then
                mod.unmarkThaddiusAdds = true
            end

            data = assignedTargets[guid]
            if not data then -- not marked but might still be known!
                for _,tmpdata in pairs(tankPriorityList) do
                    if tmpdata.guid == guid then
                        data = tmpdata
                        break
                    end
                end
            end

            if not data and unitTarget and db.honorMarks then
                local ext = externalTargets[unitTarget]
                if ext.guid ~= guid then -- guids are not matching
                    for id,data in pairs(externalTargets) do
                        if data.guid == guid then
                            SetExternalTarget(id) -- we had it under a different target, release it
                            break
                        end
                    end
                    SetExternalTarget(unitTarget, guid, uid, unitName, mobHash) -- set it
                    if self.hasDebug then
                        self:debug(L["Added third party mark (%s) for mob %s."],
                                self:GetTargetName(unitTarget), unitName)
                    end
                    self:SmartMark_RecalculateMarks()
                    self:UpdateLDBCount()
                end
                return
            end

            if not data then
                data, new = self:SmartMark_AddGUID(guid, uid, unitName, mobHash)
            end

            if data and data.mark and data.mark > 0 and data.mark < 9 and
                    data.mark ~= unitTarget then
                if db.noCombatRemark and unitTarget  and unitTarget > 0 and unitTarget < 9 and UnitAffectingCombat(unit) then
                    local tmp = markedTargets[data.mark]
                    markedTargets[data.mark] = markedTargets[unitTarget]
                    markedTargets[unitTarget] = tmp
                    LowSetTarget(data.mark)
                    data.mark = unitTarget
                    if self.hasTrace then self:trace("[Combat] Preserving %s on %s.", self:GetTargetName(unitTarget), data.name or guid) end
                else
                    self:SetRaidTarget(unit, data.mark)
                    if self.hasTrace then
                        self:trace("Marking %s with %s [%s]",
                                data.name or guid, self:GetTargetName(data.mark),  data.sender or playerName)
                    end
                end
                data.lastSetMark = data.mark
                self:ScheduleAssignDataSend()
            end
        end
    end
end

do
    local tmpdata = {}
    function mod:GetAssignData()

        for id in pairs(tmpdata) do
            if not assignedTargets[id] then
                tmpdata[id] = nil
            end
        end
        for id,data in pairs(assignedTargets) do
            if data.value and data.mark and data.mark > 0 and data.mark < 9  and data.mark == data.lastSetMark then
                if self.hasSpam then self:spam("Adding assign target: %s [%s] => %s", data.name, id, tostring(data.mark)) end
                local m = tmpdata[id] or {}
                m.name  = data.name
                m.uid   = data.uid
                m.hash  = data.hash
                m.sender = data.sender or playerName
                m.mark  = data.mark
                m.value = data.value
                m.ccval = data.ccval
                m.lastSetMark = data.lastSetMark
                m.val   = data.ccused == 1 and data.value or data.ccval
                m.cc    = self:GetCCName(data.ccused, 1)
                m.ccused = data.ccused
                tmpdata[id] = m
            else
                tmpdata[id] = nil
            end
        end
        return tmpdata
    end
end

function mod:SetRaidTarget(unit, mark)
    if mark and unit and GetRaidTargetIndex(unit) ~= mark then
        SetRaidTarget(unit, mark)
    end
end

function mod:SendUrgentMessage(channel)
    MagicComm:SendUrgentMessage(networkData, "MM", channel)
end

function mod:SendBulkMessage(channel)
    if mod:IsValidMarker() then
        MagicComm:SendBulkMessage(networkData, "MM", channel)
    end
end

function mod:MarkSingle()
    self:SmartMark_MarkUnit("target")
end

function mod:UnmarkSingle()
    if UnitExists("target") then
        local guid = UnitGUID("target")
        local mark = GetRaidTargetIndex("target")
        self:SmartMark_RemoveGUID(guid, mark)
        if mark then
            SetRaidTarget("target", 0)
        end
        self:UpdateLDBCount()
    end
end


function mod:GetMarkData()
    local atdata
    for id,data in ipairs(markedTargets) do
        local atdata = assignedTargets[data.guid]
        if atdata then
            data.valid = atdata.mark == atdata.lastSetMark
        end
    end
    return markedTargets
end

-- Disable memoried marksdata
function mod:ResetMarkData(hardReset)
    local id
    local usedRaidIcons
    local playerIcon
    local playerName = UnitName("player")
    local targets = {}
    local markToUID = {}
    valueModifier = 0.99

    self:ScheduleAssignDataSend(true)

    for id in pairs(tankPriorityList) do tankPriorityList[id] = nil end
    for id in pairs(ccPriorityList) do ccPriorityList[id] = nil end

    for id,data in pairs(assignedTargets) do
        if type(data) == "table" and data.mark then
            markToUID[data.mark] = data.uid
        end
        assignedTargets[id] = nil
    end


    if db.honorRaidMarks and not hardReset then
        usedRaidIcons = {}
        -- Look at the marks in the raid to ensure we don't reset them.
        self:IterateGroup(function(self, unit)
            local id = GetRaidTargetIndex(unit)
            if id and not templateTargets[id].guid then
                usedRaidIcons[id] = unit
                if unit == playerName then
                    playerIcon = id
                end
            end
        end)
    end


    for id = 1, 8 do
        if not (usedRaidIcons and usedRaidIcons[id]) then
            LowSetTarget(id)
            if hardReset or db.resetRaidIcons then SetRaidTarget("player", id) end
            SetTemplateTarget(id)
            SetExternalTarget(id)
        end
    end

    SetNetworkData("CLEARV2")
    self:SendUrgentMessage()

    -- Hack, sometimes the last mark isn't removed.
    if hardReset or db.resetRaidIcons then
        if playerIcon then
            SetRaidTarget("player", playerIcon)
        else
            self:ScheduleTimer(function() SetRaidTarget("player", 0) end, 0.75)
        end
    end
    if self.hasInfo then self:info(L["Resetting raid targets."]) end
    self:ScanGroupMembers()
    mod:SetTargetCount(0, 0)
end

local function myconcat(hash, key, str)
    if hash[key] then
        hash[key] = str.join(" ", hash[key], str)
    else
        hash[key] = str
    end
end

function mod:ReportRaidMarks()
    local assign = {}
    local dest, test
    if IsInRaid() then
        dest = "RAID"
    elseif GetNumGroupMembers() > 0 then
        dest = "PARTY"
    else
        return
    end

    local sortData = {}
    local hasData

    local valueToId = {}
    for id, data in pairs(markedTargets) do
        if data.value then
            local key = data.value * 10000 + id
            valueToId[key] = id
            tinsert(sortData, key)
            hasData = true
        end
    end
    if hasData then
        SendChatMessage("*** Raid Target assignments:", dest)
        sort(sortData, function(a,b) return a > b end)
        local classIndex = {}
        for _, id in pairs(sortData) do
            id = valueToId[id]
            local data = markedTargets[id]
            local unitData = self:GetUnitHash(data.uid)
            if unitData then
                if data.ccid then
                    local ccClass = CC_CLASS[data.ccid]
                    local playerName
                    if ccClass then
                        local index = classIndex[ccClass] or 1
                        playerName = raidClassNames[ccClass][index] and (raidClassNames[ccClass][index] .. " ") or nil
                        classIndex[ccClass] = index + 1
                    end
                    test = format("%s %s%s: %s",
                            self:GetTargetName(id, true),
                            playerName or "",
                            self:GetCCName(data.ccid, 1),
                            unitData.name)

                    if data.ccid == 1 then
                        SendChatMessage(test,dest)
                    else
                        assign[#assign+1] = test
                    end
                elseif data.value == 50 then
                    assign[#assign+1] = format("%s Other: %s",
                            self:GetTargetName(id, true),
                            unitData.name)
                end
            end
        end
        for i = 1,#assign do
            SendChatMessage(assign[i], dest)
        end
    end
end

-- can use this to set an override for the raid setup - hash like this
-- { DRUID = 2, MAGE = 1 }
-- etc
function mod:SetFakeRaidMakeUp(map)
    raidClassList = map
    map.FAKE = 1
end

function mod:FixProfileDefaults()
    if not db.ccprio then
        db.ccprio = {
            10, -- sap
            3, -- banish
            2, -- sheep
            4, -- shackle
            5, -- hibernate
            6, -- trap
            9, -- fear
            11, -- enslave
            12, -- root
        }
    end
    if not db.targetdata then
        db.targetdata = {
            TANK = { 8, 1, 2, 3, 4, 5, 6, 7 }
        }
    end
end

function mod:OnProfileChanged(event, newdb)
    if event ~= "OnProfileDeleted" then
        db = self.db.profile
        self:FixProfileDefaults()

        for key,val in pairs(db.ccprio) do
            if not val or val == 1 then
                db.ccprio[key] = nil
            end
        end
        self:SetLogLevel(db.logLevel)
        self:SetStatusText(format(L["Active profile: %s"], self.db:GetCurrentProfile()))
    end

    self:NotifyChange()

    mod:UpdateLDBConfig()
end

-- number of groups able to enter the instance, used when scanning groups for CC etc.
mod.zoneGroupNum = {
    ["BlackTemple"] = 5,
    ["Gruul'sLair"] = 5,
    ["HyjalSummit"] = 5,
    ["Karazhan"] = 2,
    ["Magtheridon'sLair"] = 5,
    ["SerpentshrineCavern"] = 5,
    ["SunwellPlateau"] = 5,
    ["TempestKeep"] = 5,
    ["Zul'Aman"] = 2,
}
