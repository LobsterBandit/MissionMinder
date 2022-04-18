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
	"time",
	-- WoW APIs
	"GetAddOnMetadata",
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
