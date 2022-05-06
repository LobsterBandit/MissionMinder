std = "lua51"
exclude_files = {
	"libs/",
	".luacheckrc"
}
ignore = {}
globals = {
	-- external libs
	"LibStub",
	-- Lua APIs
	"format",
	"gsub",
	"tContains",
	"time",
	"tinsert",
	"tremove",
	"wipe",
	-- WoW APIs
	"C_CurrencyInfo",
	"C_Garrison",
	"Enum",
	"GetAddOnMetadata",
	"GetCoinText",
	"GetMoney",
	"GetRealmName",
	"RequestTimePlayed",
	"UnitClass",
	"UnitLevel",
	"UnitName",
	"UnitRace",
	"UnitSex",
	-- this addon
	"MissionMinder"
}
