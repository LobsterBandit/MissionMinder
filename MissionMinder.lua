local addonName = ...
MissionMinder = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceBucket-3.0", "AceConsole-3.0", "AceEvent-3.0")
MissionMinder.DBName = "MMDB"
MissionMinder.ExportDBName = "MMExportDB"
MissionMinder.HistoryDBName = "MMHistoryDB"

local AceGUI = LibStub("AceGUI-3.0")
local Base64 = LibStub("base64.lua")
local JSON = LibStub("json.lua")
local LibDeflate = LibStub("LibDeflate")
local IPMDB = _G["IPMDB"]

-- Lua API
local tostring = tostring
local tinsert = tinsert

-- WoW API
-- local C_Covenants_GetActiveCovenantID = C_Covenants.GetActiveCovenantID
local C_CurrencyInfo_GetCurrencyInfo = C_CurrencyInfo.GetCurrencyInfo
-- local C_Garrison = C_Garrison
local GetMoney = GetMoney
local GetCoinText = GetCoinText
local tContains = tContains

-- database version
local DB_VERSION = 1
-- color of console output
local CHAT_COLOR = "ff82bf4c"
-- convenant adventure table follower
local SHADOWLANDS_FOLLOWER = Enum.GarrisonFollowerType.FollowerType_9_0
local TRACKED_TABLES = { SHADOWLANDS_FOLLOWER }

-- convert integer returned from UnitSex() to description
local GenderMap = {
    [1] = "Unknown",
    [2] = "Male",
    [3] = "Female"
}

local MMDB_defaults = {
    global = {
        Characters = {
            ["*"] = {
                Key = nil,
                Class = nil,
                Gender = nil, -- enum, need map table
                LastSeen = nil, -- timestamp in seconds
                Level = nil,
                Money = 0,
                MoneyText = "",
                Name = nil,
                PlayedLevel = 0, -- in seconds
                PlayedTotal = 0, -- in seconds
                Race = nil,
                Realm = nil,
                ReservoirAnima = 0,

                AdventureTables = {
                    ["*"] = {
                        Type = nil,
                        Followers = {}, -- list of non-auto companions
        Missions = {}
                    }
                }
            }
        }
    }
}

local MExportDB_defaults = {
    global = {
        export = "",
    }
}

local MMHistoryDB_defaults = {
    global = {
        Characters = {
            ["*"] = {
                Key = nil,
                AdventureTables = {
                    ["*"] = {
                        Type = nil,
                        Missions = {}
                    }
                }
            }
        },
        Data = {
            ["*"] = {}
        }
    }
}

-- local currency = {
--     -- Shadowlands
--     1191, -- Valor
--     1602, -- Conquest
--     1792, -- Honor
--     1822, -- Renown
--     1767, -- Stygia
--     1828, -- Soul Ash
--     1810, -- Redeemed Soul
--     1813, -- Reservoir Anima
--     1889, -- Adventure Campaign Progress
--     1904, -- Tower Knowledge
--     1906, -- Soul Cinders
--     1931, -- Cataloged Research
--     1979, -- Cyphers of the First Ones
--     2009, -- Cosmic Flux
-- }

------------------------------------
-- Helpers
------------------------------------

local function compressAndEncode(data)
    local jsonData = JSON.encode(data)
    local compressed = LibDeflate:CompressZlib(jsonData)
    return Base64:encode(compressed)
end

local function missionKey(char)
    return format("%s-%s", char.Name, char.Realm)
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

local function UpdateCurrency()
    local char = MissionMinder.Character
    -- gold
    char.Money = GetMoney()
    char.MoneyText = GetCoinText(char.Money)

    -- anima
    local data = C_CurrencyInfo_GetCurrencyInfo(1813)
    if data.discovered then
        char.ReservoirAnima = data.quantity
    end
end

------------------------------------
-- Mixins
------------------------------------

function MissionMinder:SetCurrentCharacter()
    local account = "Default"
    local realm = GetRealmName()
    local char = UnitName("player")
    local key = format("%s.%s.%s", account, realm, char)

    -- main db char
    if self.db.global.Characters[key].Key == nil then
        self.db.global.Characters[key].Key = key
    end

    -- history db char
    if self.db_history.global.Characters[key].Key == nil then
        self.db_history.global.Characters[key].Key = key
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

-- Updates mission and follower data for the current character. Alt data will be gathered as each character logs in.
function MissionMinder:UpdateMissions()
    local char = self.Character
    for _, t in ipairs(TRACKED_TABLES) do
        local charTable = char.AdventureTables[tostring(t)]
        charTable.Type = charTable.Type or t
        -- charTable.Followers = charTable.Followers or {}
        -- wipe missions before fetching new
        charTable.Missions = wipe(charTable.Missions or {})
    end

    local missions = IPMDB.profiles[missionKey(char)] or {}
        for _, mission in ipairs(missions) do
        if tContains(TRACKED_TABLES, mission.followerTypeID) then
            local tableType = tostring(mission.followerTypeID)
            local charTable = char.AdventureTables[tableType]
            local tmp = {}
            tmp.baseCost = mission.baseCost
            tmp.charText = mission.charText
            tmp.cost = mission.cost
            tmp.costCurrencyTypesID = mission.costCurrencyTypesID
            tmp.durationSeconds = mission.durationSeconds
            tmp.encounterIconInfo = mission.encounterIconInfo
            tmp.followers = mission.followers
            tmp.followerInfo = mission.followerInfo
            tmp.followerTypeID = mission.followerTypeID
            tmp.inProgress = mission.inProgress
            tmp.missionEndTime = mission.missionEndTime
            tmp.missionID = mission.missionID
            tmp.missionScalar = mission.missionScalar
            tmp.name = mission.name
            tmp.rewards = mission.rewards
            tmp.type = mission.type
            tmp.xp = mission.xp

            -- keep running list of unique followers
            for id, finfo in pairs(mission.followerInfo) do
                if not charTable.Followers[id] then
                    charTable.Followers[id] = {}
                end

                local followerInfo = {}
                followerInfo.followerTypeID = finfo.followerTypeID
                followerInfo.health = finfo.health
                followerInfo.isAutoTroop = finfo.isAutoTroop
                followerInfo.isSoulbind = finfo.isSoulbind
                followerInfo.level = finfo.level
                followerInfo.levelXP = finfo.levelXP
                followerInfo.maxHealth = finfo.maxHealth
                followerInfo.name = finfo.name
                followerInfo.role = finfo.role
                followerInfo.xp = finfo.xp

                charTable.Followers[id] = followerInfo
            end

            tinsert(charTable.Missions, tmp)
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

    self.db = LibStub("AceDB-3.0"):New(self.DBName, MMDB_defaults, true)
    self:UpgradeDB()

    -- TODO: move these to separate addons for slimmer saved variables files
    self.db_export = LibStub("AceDB-3.0"):New(self.ExportDBName, MExportDB_defaults, true)
    self.db_history = LibStub("AceDB-3.0"):New(self.HistoryDBName, MMHistoryDB_defaults, true)

    self:SetCurrentCharacter()
    self:RegisterChatCommand("missionminder", "MissionMinderSlashHandler")
    self:RegisterChatCommand("mm", "MissionMinderSlashHandler")
end

function MissionMinder:OnEnable()
    self:PrintVersion()

    self:UpdateCharacterMetadata()
    self:UpdateMissions()

    self:RegisterBucketEvent("CURRENCY_DISPLAY_UPDATE", 0.25, UpdateCurrency)
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
