--!strict
-- Floor structure. Phase 6 replaces `sequence` with a seeded graph; until then a run
-- is a fixed list of room templates, which is enough to prove the loop advances.

local FloorConfig = {}

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
	-- Where the run starts in world space, far from the practice area.
	origin = Vector3.new(2000, 0, 0),
	-- Player lands just inside the entrance, facing the exit.
	entranceOffset = Vector3.new(0, 5, 16),
	-- The volume just beyond the exit doorway that counts as "left the floor".
	exitTriggerDepth = 14,
	exitTriggerWidth = 12,
}

-- A fixed rotation until Phase 6 makes the choice seeded. The shape matters more than
-- the order: fight, breathe, fight harder, recover. Treasure lands early so the player
-- sees a reward before the Elite, and Healing lands straight after it.
FloorConfig.sequence = {
	"Combat",
	"Treasure",
	"Combat",
	"Elite",
	"Healing",
}

function FloorConfig.templateForFloor(depth: number): string
	local index = ((depth - 1) % #FloorConfig.sequence) + 1
	return FloorConfig.sequence[index]
end

return FloorConfig
