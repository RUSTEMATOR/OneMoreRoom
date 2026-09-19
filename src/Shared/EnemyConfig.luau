--!strict
-- Enemy tunables. Same contract as CombatConfig: this is the only place an enemy
-- number lives, and the client may read it freely because the server re-derives
-- everything it enforces.

local EnemyConfig = {}

EnemyConfig.kinds = {
	Skeleton = {
		id = "Skeleton",
		displayName = "Skeleton",

		-- 60 HP against an 18-damage sword is 4 swings: long enough to be a fight,
		-- short enough that a room full of them is not a chore.
		maxHealth = 60,

		-- 14 damage against a 100 HP player is ~7 hits to die, which is the design
		-- target Phase 1 anchored when it fixed sword damage at 18.
		damage = 14,

		-- Slower than the player's 16, so backing off is always an option and
		-- spacing stays a real decision rather than a formality.
		walkSpeed = 11,

		detectRange = 34,
		leashRange = 60,
		-- Slightly beyond the player's 5.5 reach: the skeleton can hit you from just
		-- outside your own range, so closing distance costs something.
		attackRange = 6.5,

		-- The telegraph. Longer than the dodge i-frame window (0.30) so a read is
		-- possible but the timing still has to be right.
		noticeTime = 0.35,
		attackWindup = 0.45,
		attackRecovery = 0.35,
		attackCooldown = 1.1,

		staggerTime = 0.22,
		despawnDelay = 2.5,

		goldReward = 7,

		rig = {
			torsoSize = Vector3.new(2, 2, 1),
			headSize = Vector3.new(1.4, 1.4, 1.4),
			rootSize = Vector3.new(2, 2, 1),
			boneColor = Color3.fromRGB(226, 223, 208),
			torsoColor = Color3.fromRGB(198, 194, 176),
			material = Enum.Material.Sand,
			lungeAngle = 24,
		},
	},

	-- The Elite is a data entry, not a new enemy: same state machine, harder numbers.
	-- 150 HP is 9 sword swings and 22 damage kills a full-health player in 5 hits, so
	-- it is a genuine threat without being a boss — that is Phase 10.
	SkeletonElite = {
		id = "SkeletonElite",
		displayName = "Elite Skeleton",

		maxHealth = 150,
		damage = 22,
		walkSpeed = 13,

		detectRange = 40,
		leashRange = 70,
		attackRange = 7.5,

		noticeTime = 0.3,
		-- Still readable, but tighter than the basic skeleton's 0.45.
		attackWindup = 0.38,
		attackRecovery = 0.4,
		attackCooldown = 0.95,

		staggerTime = 0.16,
		despawnDelay = 3.0,

		goldReward = 26,

		rig = {
			torsoSize = Vector3.new(2.6, 2.6, 1.3),
			headSize = Vector3.new(1.7, 1.7, 1.7),
			rootSize = Vector3.new(2.6, 2.6, 1.3),
			boneColor = Color3.fromRGB(206, 196, 224),
			torsoColor = Color3.fromRGB(122, 104, 150),
			material = Enum.Material.Slate,
			lungeAngle = 28,
		},
	},
}

-- A practice skeleton next to the training dummy, so the combat loop is playable
-- before floors exist. It spawns into Workspace/Static like the dummy, never into
-- Generated, which FloorService clears every run and Phase00_Boot asserts is empty.
EnemyConfig.practice = {
	enabled = true,
	kind = "Skeleton",
	position = Vector3.new(10, 3, -18),
	respawnDelay = 6.0,
}

return EnemyConfig
