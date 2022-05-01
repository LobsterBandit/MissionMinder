local addonName = ...
MissionMinder = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
MissionMinder.DatabaseName = "MissionMinderDB"
MissionMinder.ExportDatabaseName = "MissionMinderExportDB"

local AceGUI = LibStub("AceGUI-3.0")
local Base64 = LibStub("base64.lua")
local JSON = LibStub("json.lua")
local LibDeflate = LibStub("LibDeflate")
local IPMDB = _G["IPMDB"]

-- database version
local DB_VERSION = 1
-- color of console output
local CHAT_COLOR = "ff82bf4c"
-- convenant adventure table follower
local SL_MISSIONS = Enum.GarrisonFollowerType.FollowerType_9_0

-- convert integer returned from UnitSex() to description
local GenderMap = {
    [1] = "Unknown",
    [2] = "Male",
    [3] = "Female"
}

local MissionMinderDB_defaults = {
    global = {
        Characters = {
            ["*"] = {
                Key = nil,
                Class = nil,
                Gender = nil, -- enum, need map table
                LastSeen = nil, -- timestamp in seconds
                Level = nil,
                Name = nil,
                PlayedLevel = 0, -- in seconds
                PlayedTotal = 0, -- in seconds
                Race = nil,
                Realm = nil,
            }
        },
        Missions = {}
    }
}

local MissionMinderExportDB_defaults = {
    global = {
        export = "",
    }
}

------------------------------------
-- Helpers
------------------------------------

local function compressAndEncode(data)
    local jsonData = JSON.encode(data)
    local compressed = LibDeflate:CompressZlib(jsonData)
    return Base64:encode(compressed)
end

------------------------------------
-- Event Handlers
------------------------------------

local function OnTimePlayedMsg(_, totalTime, currentLevelTime)
    MissionMinder:UnregisterEvent("TIME_PLAYED_MSG")

    local char = MissionMinder.Character
    char.PlayedTotal = totalTime
    char.PlayedLevel = currentLevelTime
end

local function OnPlayerLogout()
    MissionMinder:UpdateMissions()
    MissionMinder.Character.LastSeen = time()

    MissionMinder.db_export.global.export = compressAndEncode(MissionMinder.db.global)
end

------------------------------------
-- Mixins
------------------------------------

function MissionMinder:SetCurrentCharacter()
    local account = "Default"
    local realm = GetRealmName()
    local char = UnitName("player")
    local key = format("%s.%s.%s", account, realm, char)

    if self.db.global.Characters[key].Key == nil then
        self.db.global.Characters[key].Key = key
    end

    self.Character = self.db.global.Characters[key]
end

function MissionMinder:UpdateCharacterMetadata()
    local char = self.Character
    char.Realm = GetRealmName()
    char.Name = UnitName("player")
    char.Class = UnitClass("player")
    char.Race = UnitRace("player")
    char.Gender = GenderMap[UnitSex("player")] or GenderMap[1]
    char.Level = UnitLevel("player")
    char.LastSeen = time()
end

function MissionMinder:PrintMessage(...)
    self:Print("|c" .. CHAT_COLOR .. format(...) .. "|r")
end

function MissionMinder:PrintVersion()
    self:PrintMessage("Version %s", self.Version)
end

function MissionMinder:PrintUsage()
    self:PrintMessage("------------------------------------")
    self:PrintVersion()
    self:Print()
    self:PrintMessage("  /mm         - alias for /mm export")
    self:PrintMessage("  /mm version - print version info")
    self:PrintMessage("  /mm export  - open export dialog")
    self:PrintMessage("------------------------------------")
end

function MissionMinder:ShowExportString()
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("MissionMinder Character Export")
    frame:SetStatusText("Exporting MissionMinder Character Data")
    frame:SetCallback(
        "OnClose",
        function(widget)
        AceGUI:Release(widget)
    end
    )
    frame:SetLayout("Fill")

    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:DisableButton(true)
    editBox:SetLabel(nil)
    editBox:SetText(compressAndEncode(self.db.global))
    editBox:SetFocus()
    editBox:HighlightText()

    frame:AddChild(editBox)
end

function MissionMinder:UpdateMissions()
    self.db.global.Missions = wipe(self.db.global.Missions or {})
    for name, missions in pairs(IPMDB.profiles) do
        self.db.global.Missions[name] = {}
        for _, mission in ipairs(missions) do
            local tmp = {}
            tmp.baseCost = mission.baseCost
            tmp.cost = mission.cost
            tmp.inProgress = mission.inProgress
            tmp.xp = mission.xp
            tmp.missionEndTime = mission.missionEndTime
            tmp.missionID = mission.missionID
            tmp.followerTypeID = mission.followerTypeID
            tmp.durationSeconds = mission.durationSeconds
            tmp.missionScalar = mission.missionScalar
            tmp.charText = mission.charText
            tmp.type = mission.type
            tmp.rewards = mission.rewards
            tmp.costCurrencyTypesID = mission.costCurrencyTypesID
            tmp.name = mission.name
            tmp.encounterIconInfo = mission.encounterIconInfo

            -- follower info
            tmp.followers = mission.followers
            tmp.followerInfo = {}
            for id, finfo in pairs(mission.followerInfo) do
                tmp.followerInfo[id] = {}
                tmp.followerInfo[id].followerTypeID = finfo.followerTypeID
                tmp.followerInfo[id].level = finfo.level
                tmp.followerInfo[id].levelXP = finfo.levelXP
                tmp.followerInfo[id].isSoulbind = finfo.isSoulbind
                tmp.followerInfo[id].name = finfo.name
                tmp.followerInfo[id].xp = finfo.xp
                tmp.followerInfo[id].health = finfo.health
                tmp.followerInfo[id].maxHealth = finfo.maxHealth
                tmp.followerInfo[id].isAutoTroop = finfo.isAutoTroop
                tmp.followerInfo[id].role = finfo.role
            end

            tinsert(self.db.global.Missions[name], tmp)
        end
    end
end

function MissionMinder:UpgradeDB()
    local dbVersion = self.db.global.DBVersion or 1

    -- nothing to do if already at max db version
    if dbVersion == DB_VERSION then
        return
    end

    while dbVersion < DB_VERSION do
        if dbVersion == 1 then
            -- completed 1 => 2 upgrade
            dbVersion = 2
            self.db.global.DBVersion = dbVersion
        end
    end
end

------------------------------------
-- Slash Commands
------------------------------------

function MissionMinder:MissionMinderSlashHandler(input)
    if input == nil then
        self:PrintUsage()
        return
    end

    local command = self:GetArgs(input, 1)

    if command == nil then
        self:ShowExportString()
        return
    end

    if command == "version" then
        self:PrintVersion()
        return
    end

    if command == "export" then
        self:ShowExportString()
        return
    end

    if command == "help" then
        self:PrintUsage()
        return
    end

    if command ~= nil then
        self:PrintMessage("Unknown command: %s", input)
        self:Print()
    end

    self:PrintUsage()
end

------------------------------------
-- Addon Setup
------------------------------------

function MissionMinder:OnInitialize()
    self.Version = "v" .. GetAddOnMetadata("MissionMinder", "Version")
    --
    self.db = LibStub("AceDB-3.0"):New(self.DatabaseName, MissionMinderDB_defaults, true)
    self:UpgradeDB()

    self.db_export = LibStub("AceDB-3.0"):New(self.ExportDatabaseName, MissionMinderExportDB_defaults, true)

    self:SetCurrentCharacter()
    self:RegisterChatCommand("missionminder", "MissionMinderSlashHandler")
    self:RegisterChatCommand("mm", "MissionMinderSlashHandler")
end

function MissionMinder:OnEnable()
    self:PrintVersion()

    self:UpdateCharacterMetadata()
    self:UpdateMissions()

    self:RegisterEvent("PLAYER_LOGOUT", OnPlayerLogout)
    self:RegisterEvent("TIME_PLAYED_MSG", OnTimePlayedMsg)

    RequestTimePlayed()
end

function MissionMinder:OnDisable()
    self:UnregisterEvent("PLAYER_LOGOUT")
    self:UnregisterEvent("TIME_PLAYED_MSG")
    self:UnregisterChatCommand("missionminder")
    self:UnregisterChatCommand("mm")
end
