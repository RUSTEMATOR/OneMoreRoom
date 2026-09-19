--!strict
-- Floor structure and the generation parameters FloorPlan draws from.
--
-- This module must NOT require FloorPlan: FloorPlan requires this, and ServerMain
-- resolves every module at top level, so the cycle would be a hard boot error.

local FloorConfig = {}

-- Bumped deliberately whenever generation is *meant* to change. The golden-hash spec
-- pairs its committed constant with this, so an intentional change is one line plus a
-- regenerated hash, and an unintentional one is a loud failure.
FloorConfig.generationVersion = 4

FloorConfig.run = {
	firstFloor = 1,
	-- Gold for clearing a floor, on top of what the enemies drop. This is the
	-- "Reward" beat between Combat and Exit; Phase 7 turns it into real loot.
	clearBonusGold = 15,
}

FloorConfig.layout = {
	-- Each floor is built well clear of the last so a lingering enemy or a stray
	-- physics object cannot reach across. Cheaper than chasing cleanup bugs.
	floorSpacing = 400,
	origin = Vector3.new(2000, 0, 0),
	-- Player lands just inside the entrance, facing the exits. Deliberately centred
	-- between the two doors rather than in front of one, so neither is favoured.
	entranceOffset = Vector3.new(0, 5, 16),
	entranceClearRadius = 10,
	exitTriggerDepth = 14,
	exitTriggerWidth = 12,
}

-- The ordered pool generation draws from. ORDER MATTERS AND IS PART OF THE SEED
-- CONTRACT: `Rng:int(1, #pool)` indexes this list, so reordering or inserting changes
-- every seed's output. Never iterate RoomConfig.templates with pairs to build this —
-- Luau hash order is not stable and the golden hash would flap between runs.
FloorConfig.pool = {
	"Combat",
	"Treasure",
	"Elite",
	"Healing",
}

-- Every tenth floor is a boss, regardless of what the seed would otherwise pick.
-- Deliberately NOT in the pool: a boss must be a landmark you can count toward, not
-- something that might turn up on floor 3.
FloorConfig.bossEvery = 10
FloorConfig.bossTemplate = "Boss"

function FloorConfig.isBossDepth(depth: number): boolean
	return depth > 0 and depth % FloorConfig.bossEvery == 0
end

-- Two doors per cleared room.
FloorConfig.exitCount = 2

-- Encounter size grows with depth. Without a curve, floor 30 fights floor 1's
-- encounter and the climb has no shape.
FloorConfig.encounter = {
	-- count = clamp(base + floor(depth * perFloor), min, max), then the template's
	-- own min/max clamp on top.
	base = 1.0,
	perFloor = 0.34,
	hardMax = 6,
	-- Enemies are never placed closer than this multiple of their own root width.
	separationFactor = 2.0,
	-- Bounded rejection sampling: give up after this many tries and fall back to a
	-- deterministic ring slot, so generation always terminates.
	maxAttempts = 12,
}

-- Where a player lands inside a room. The base Z is clamped into the template's own
-- interior: a fixed 16 is fine in a 40-deep Combat room but lands OUTSIDE a 28-deep
-- Healing room, which means the room never registers anyone inside and never seals.
function FloorConfig.entranceOffsetFor(interiorZ: number): Vector3
	local base = FloorConfig.layout.entranceOffset
	return Vector3.new(base.X, base.Y, math.min(base.Z, interiorZ / 2 - 4))
end

function FloorConfig.countForDepth(depth: number, minCount: number, maxCount: number): number
	local raw = FloorConfig.encounter.base + math.floor(depth * FloorConfig.encounter.perFloor)
	local capped = math.min(raw, FloorConfig.encounter.hardMax)
	return math.clamp(math.floor(capped), minCount, maxCount)
end

return FloorConfig
