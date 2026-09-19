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

	-- Everything below is a data entry. No new plumbing: a room with an empty
	-- enemySpawns list simply clears the moment it seals, and `reward` adds a prize
	-- the player walks into. That is the Phase 5 acceptance criterion.

	Elite = {
		id = "Elite",
		displayName = "Elite Room",
		interior = Vector3.new(44, 18, 44),
		wallThickness = 2,
		floorThickness = 1,
		doorway = { width = 10, height = 12 },
		floorColor = Color3.fromRGB(64, 58, 72),
		wallColor = Color3.fromRGB(88, 80, 98),
		doorColor = Color3.fromRGB(52, 46, 58),
		trimColor = Color3.fromRGB(176, 122, 220),
		material = Enum.Material.Slate,
		doorMaterial = Enum.Material.WoodPlanks,
		enemyKind = "SkeletonElite",
		enemySpawns = {
			Vector3.new(0, 0, -13),
		},
		reward = { kind = "gold", amount = 40 },
		doorTravel = 12,
		doorTime = 0.55,
		sealDelay = 0.25,
		clearDelay = 0.8,
	},

	Treasure = {
		id = "Treasure",
		displayName = "Treasure Room",
		interior = Vector3.new(30, 16, 30),
		wallThickness = 2,
		floorThickness = 1,
		doorway = { width = 10, height = 12 },
		floorColor = Color3.fromRGB(78, 70, 54),
		wallColor = Color3.fromRGB(104, 94, 72),
		doorColor = Color3.fromRGB(58, 52, 46),
		trimColor = Color3.fromRGB(226, 184, 74),
		material = Enum.Material.Sandstone,
		doorMaterial = Enum.Material.WoodPlanks,
		enemyKind = "Skeleton",
		enemySpawns = {},
		reward = { kind = "gold", amount = 60 },
		doorTravel = 12,
		doorTime = 0.55,
		sealDelay = 0.25,
		clearDelay = 0.4,
	},

	Healing = {
		id = "Healing",
		displayName = "Healing Room",
		interior = Vector3.new(28, 16, 28),
		wallThickness = 2,
		floorThickness = 1,
		doorway = { width = 10, height = 12 },
		floorColor = Color3.fromRGB(58, 74, 70),
		wallColor = Color3.fromRGB(80, 100, 96),
		doorColor = Color3.fromRGB(48, 58, 56),
		trimColor = Color3.fromRGB(96, 214, 168),
		material = Enum.Material.Slate,
		doorMaterial = Enum.Material.WoodPlanks,
		enemyKind = "Skeleton",
		enemySpawns = {},
		-- A fraction, not a flat number, so it stays meaningful when Phase 9's
		-- permanent upgrades raise max health.
		reward = { kind = "heal", amount = 0.5 },
		doorTravel = 12,
		doorTime = 0.55,
		sealDelay = 0.25,
		clearDelay = 0.4,
	},
}

-- Shop and Event are deliberately absent. A shop needs somewhere to spend gold
-- (Phase 7 loot) and a way to choose (Phase 12 UI); building either now would mean
-- faking both. They are a data entry away once those exist.

RoomConfig.prize = {
	size = Vector3.new(2.4, 2.4, 2.4),
	height = 2.6,
	pickupRadius = 6,
	spinPerSecond = 1.2,
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
