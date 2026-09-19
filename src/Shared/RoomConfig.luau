--!strict
-- Room templates as data. A room is a ~30-line table, which is the whole reason
-- geometry is generated rather than modelled: it diffs one line at a time and Phase 6
-- can parameterize it by seed.

local RoomConfig = {}

RoomConfig.templates = {
	Combat = {
		id = "Combat",
		displayName = "Combat Room",

		-- Interior clear space. 40x40 gives room to back off from three skeletons
		-- without the fight turning into a corridor shuffle.
		interior = Vector3.new(40, 18, 40),
		wallThickness = 2,
		floorThickness = 1,

		doorway = { width = 10, height = 12 },

		floorColor = Color3.fromRGB(74, 72, 78),
		wallColor = Color3.fromRGB(96, 93, 88),
		doorColor = Color3.fromRGB(58, 52, 46),
		trimColor = Color3.fromRGB(184, 138, 58),
		material = Enum.Material.Slate,
		doorMaterial = Enum.Material.WoodPlanks,

		enemyKind = "Skeleton",
		-- Offsets from the room centre, on the floor.
		enemySpawns = {
			Vector3.new(-9, 0, -9),
			Vector3.new(9, 0, -9),
			Vector3.new(0, 0, -13),
		},

		-- Doors drop into the floor to open and rise to seal.
		doorTravel = 12,
		doorTime = 0.55,
		sealDelay = 0.25,
		clearDelay = 0.6,
	},
}

-- A playable room next to the practice area, so the vertical slice can be walked
-- through before FloorService exists. Lives in Workspace/Static like the dummy and the
-- practice skeleton: Generated is run-scoped and Phase00_Boot asserts it starts empty.
RoomConfig.practice = {
	enabled = true,
	template = "Combat",
	-- Far enough from the spawn pad that you walk to it deliberately.
	position = Vector3.new(0, 0, -78),
}

return RoomConfig
