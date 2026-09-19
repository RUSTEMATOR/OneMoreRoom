--!strict
-- The persistent shape, defined now so Phase 13 swaps a backend instead of inventing a
-- schema after ten systems have improvised their own. Run-scoped state never lives here.

export type Statistics = {
	runsStarted: number,
	runsCompleted: number,
	deepestFloor: number,
	totalKills: number,
	bossKills: number,
}

export type PlayerData = {
	version: number,
	soulShards: number,
	permanentUpgrades: { [string]: number },
	unlockedWeapons: { string },
	unlockedRelics: { string },
	statistics: Statistics,
}

local PlayerDataSchema = {}

PlayerDataSchema.VERSION = 1

function PlayerDataSchema.default(): PlayerData
	return {
		version = PlayerDataSchema.VERSION,
		soulShards = 0,
		permanentUpgrades = {},
		unlockedWeapons = { "Sword" },
		unlockedRelics = {},
		statistics = {
			runsStarted = 0,
			runsCompleted = 0,
			deepestFloor = 0,
			totalKills = 0,
			bossKills = 0,
		},
	}
end

-- Returns ok, reason. Called on every DataStore load before the data is trusted.
function PlayerDataSchema.validate(data: any): (boolean, string?)
	if type(data) ~= "table" then
		return false, "not a table"
	end
	if type(data.version) ~= "number" then
		return false, "missing version"
	end
	if type(data.soulShards) ~= "number" or data.soulShards < 0 then
		return false, "invalid soulShards"
	end
	if type(data.permanentUpgrades) ~= "table" then
		return false, "invalid permanentUpgrades"
	end
	if type(data.unlockedWeapons) ~= "table" then
		return false, "invalid unlockedWeapons"
	end
	if type(data.unlockedRelics) ~= "table" then
		return false, "invalid unlockedRelics"
	end
	if type(data.statistics) ~= "table" then
		return false, "invalid statistics"
	end
	return true, nil
end

return PlayerDataSchema
