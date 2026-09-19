--!strict
-- In-memory stub. Phase 13 swaps the backend for DataStore; the schema and this surface
-- stay put. The place is unpublished (PlaceId == 0), so DataStore cannot work yet — the
-- fallback is what keeps that from looking like a code bug.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataSchema = require(ReplicatedStorage.Shared.PlayerDataSchema)

local SaveService = {}

local cache: { [Player]: PlayerDataSchema.PlayerData } = {}

function SaveService.Init()
	table.clear(cache)
end

function SaveService.isPersistent(): boolean
	return game.PlaceId ~= 0
end

function SaveService.load(player: Player): PlayerDataSchema.PlayerData
	local existing = cache[player]
	if existing then
		return existing
	end
	local fresh = PlayerDataSchema.default()
	cache[player] = fresh
	return fresh
end

function SaveService.save(player: Player): boolean
	local data = cache[player]
	if data == nil then
		return false
	end
	local ok = PlayerDataSchema.validate(data)
	return ok
end

return SaveService
