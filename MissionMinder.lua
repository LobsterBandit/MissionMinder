local addonName = ...
MissionMinder = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
MissionMinder.DatabaseName = "MissionMinderDB"

local AceGUI = LibStub("AceGUI-3.0")
-- database version
local DB_VERSION = 1
-- color of console output
local CHAT_COLOR = "ff82bf4c"

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
        Missions = {
            ["*"] = {
                -- static mission info, rewards, etc
            }
        }
    }
}

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
    MissionMinder.Character.LastSeen = time()
end

------------------------------------
-- Mixins
------------------------------------

function MissionMinder:SetCurrentCharacter()
    local account = "Default"
    local realm = GetRealmName()
    local char = UnitName("player")
    local key = format("%s:%s:%s", account, realm, char)

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

function MissionMinder:PrintCharacterMetadata()
    self:PrintMessage("Key >> %s", self.Character.Key)
    self:PrintMessage("Realm >> %s", self.Character.Realm)
    self:PrintMessage("Name >> %s", self.Character.Name)
    self:PrintMessage("Class >> %s", self.Character.Class)
    self:PrintMessage("Race >> %s", self.Character.Race)
    self:PrintMessage("Gender >> %s", self.Character.Gender)
    self:PrintMessage("Level >> %s", self.Character.Level)
    self:PrintMessage("LastSeen >> %s", self.Character.LastSeen)
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
    self:PrintMessage("  /mm         - print this usage info")
    self:PrintMessage("  /mm version - print version info")
    self:PrintMessage("  /mm char    - print character data")
    self:PrintMessage("  /mm export  - export character data")
    self:PrintMessage("------------------------------------")
end

function MissionMinder:ShowExportString()
    local json = LibStub("json.lua")
    local base64 = LibStub("base64.lua")
    local data = json:encode(self.db.global.Characters)
    local printable = base64:encode(data)

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
    editBox:SetText(printable)
    editBox:SetFocus()
    editBox:HighlightText()

    frame:AddChild(editBox)
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

    if command == "version" then
        self:PrintVersion()
        return
    end

    if command == "char" then
        self:PrintCharacterMetadata()
        return
    end

    if command == "export" then
        self:ShowExportString()
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
    self.db = LibStub("AceDB-3.0"):New(self.DatabaseName, MissionMinderDB_defaults, true)
    self:UpgradeDB()

    self:SetCurrentCharacter()
    self:RegisterChatCommand("missionminder", "MissionMinderSlashHandler")
end

function MissionMinder:OnEnable()
    self:PrintVersion()

    self:UpdateCharacterMetadata()
    self:PrintCharacterMetadata()

    self:RegisterEvent("PLAYER_LOGOUT", OnPlayerLogout)
    self:RegisterEvent("TIME_PLAYED_MSG", OnTimePlayedMsg)

    RequestTimePlayed()
end

function MissionMinder:OnDisable()
    self:UnregisterEvent("PLAYER_LOGOUT")
    self:UnregisterEvent("TIME_PLAYED_MSG")
    self:UnregisterEvent("PLAYER_LEVEL_UP")
    self:UnregisterEvent("PLAYER_XP_UPDATE")
    self:UnregisterChatCommand("missionminder")
end
