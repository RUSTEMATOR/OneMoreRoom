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

		-- Placements are generated per seed by FloorPlan; the template only says what
		-- kind, how many, and how far from the centre they may stand.
		encounter = { kind = "Skeleton", minCount = 2, maxCount = 5, radius = 15 },

		-- Doors drop into the floor to open and rise to seal.
		doorTravel = 12,
		doorTime = 0.55,
		sealDelay = 0.25,
		clearDelay = 0.6,
	},

	-- Everything below is a data entry. No new plumbing: a room whose encounter has
	-- a zero count simply clears the moment it seals, and `reward` adds a prize the
	-- player walks into. That is the Phase 5 acceptance criterion.

	-- The Sentry room: same shape as Combat, but the encounter is entirely ranged.
	-- Mirrors Elite's pattern of "same plumbing, different `encounter.kind`" exactly
	-- -- a room's encounter is always ONE kind, so a mixed melee/ranged fight is a
	-- second room type, not a branch in FloorPlan's placement code.
	Outpost = {
		id = "Outpost",
		displayName = "Sentry Outpost",
		interior = Vector3.new(44, 18, 44),
		wallThickness = 2,
		floorThickness = 1,
		doorway = { width = 10, height = 12 },
		floorColor = Color3.fromRGB(46, 48, 52),
		wallColor = Color3.fromRGB(58, 62, 68),
		doorColor = Color3.fromRGB(30, 32, 36),
		-- Cyan trim, matching the Sentry's own bolt colour -- the room tells you what
		-- is waiting inside before the door even opens.
		trimColor = Color3.fromRGB(80, 220, 220),
		material = Enum.Material.DiamondPlate,
		doorMaterial = Enum.Material.Metal,
		-- Wider radius than Combat's 15: a room built to punish standing still needs
		-- the space for that to actually be true.
		encounter = { kind = "Archer", minCount = 1, maxCount = 3, radius = 20 },
		doorTravel = 12,
		doorTime = 0.55,
		sealDelay = 0.25,
		clearDelay = 0.6,
	},

	-- The third room the third enemy needed. Same "same plumbing, different kind"
	-- pattern as Outpost -- a room's encounter is always one kind, so Cultist gets
	-- its own room rather than a branch in placement code, exactly like Sentry did.
	Sanctum = {
		id = "Sanctum",
		displayName = "Cultist Sanctum",
		interior = Vector3.new(42, 18, 42),
		wallThickness = 2,
		floorThickness = 1,
		doorway = { width = 10, height = 12 },
		floorColor = Color3.fromRGB(52, 40, 36),
		wallColor = Color3.fromRGB(66, 50, 44),
		doorColor = Color3.fromRGB(34, 24, 20),
		-- Ember-orange trim, matching the Cultist's own resting colour -- the same
		-- read-the-room-before-the-door trick Outpost's cyan trim uses.
		trimColor = Color3.fromRGB(210, 90, 50),
		material = Enum.Material.CorrodedMetal,
		doorMaterial = Enum.Material.Metal,
		-- Smaller than Outpost's 20: these rushers need less standoff room than a
		-- sniper does, but still enough to clear a blast radius of 9 once armed.
		encounter = { kind = "Cultist", minCount = 1, maxCount = 3, radius = 17 },
		doorTravel = 12,
		doorTime = 0.55,
		sealDelay = 0.25,
		clearDelay = 0.6,
	},

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
		encounter = { kind = "SkeletonElite", minCount = 1, maxCount = 2, radius = 15 },
		-- Only the amount is seeded; the kind stays fixed so a Treasure room is
		-- always treasure and a Healing room always heals.
		reward = { kind = "gold", minAmount = 30, maxAmount = 55 },
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
		encounter = { kind = "Skeleton", minCount = 0, maxCount = 0, radius = 10 },
		reward = { kind = "gold", minAmount = 45, maxAmount = 80 },
		doorTravel = 12,
		doorTime = 0.55,
		sealDelay = 0.25,
		clearDelay = 0.4,
	},

	-- The arena IS a room. A boss fight seals, clears and opens exits through the
	-- same machinery as everything else; only what is inside differs.
	Boss = {
		id = "Boss",
		displayName = "Warden's Hall",
		interior = Vector3.new(60, 26, 60),
		wallThickness = 3,
		floorThickness = 1,
		doorway = { width = 12, height = 14 },
		floorColor = Color3.fromRGB(52, 46, 62),
		wallColor = Color3.fromRGB(70, 62, 84),
		doorColor = Color3.fromRGB(42, 36, 50),
		trimColor = Color3.fromRGB(176, 122, 220),
		material = Enum.Material.Slate,
		doorMaterial = Enum.Material.WoodPlanks,
		-- No ordinary encounter: the boss is spawned instead, and the room is not
		-- cleared until it falls.
		encounter = { kind = "Skeleton", minCount = 0, maxCount = 0, radius = 10 },
		boss = "Warden",
		doorTravel = 14,
		doorTime = 0.7,
		sealDelay = 0.4,
		clearDelay = 1.4,
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
		encounter = { kind = "Skeleton", minCount = 0, maxCount = 0, radius = 10 },
		-- A fraction, not a flat number, so it stays meaningful when Phase 9's
		-- permanent upgrades raise max health.
		reward = { kind = "heal", minAmount = 0.35, maxAmount = 0.6 },
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
	-- Fixed, so the practice room is the same every session and a manual pass is
	-- comparing like with like.
	seed = 101010,
	depth = 1,
	-- Far enough from the spawn pad that you walk to it deliberately.
	position = Vector3.new(0, 0, -78),
}

return RoomConfig
