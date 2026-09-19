--!strict
-- Every combat tunable lives here. Shared rather than server-only because the client
-- needs the swing timings to drive the procedural pose — knowing a number grants no
-- authority, since the server re-derives everything it enforces from this same table.
--
-- This is the file to edit when combat does not feel right. Nothing else should hold a
-- magic number.

local CombatConfig = {}

CombatConfig.player = {
	maxHealth = 100,
	walkSpeed = 16,
	respawnDelay = 3.0,
}

-- Full refill takes regenDelay + max/regenPerSecond = 5.3s. Sustained dodge period is
-- regenDelay + cost/regenPerSecond = 1.94s: dodging on a ~2s rhythm is free, dodging
-- faster than that drains into a 5s hole.
CombatConfig.stamina = {
	max = 100,
	regenPerSecond = 22,
	regenDelay = 0.8,
}

CombatConfig.weapons = {
	Sword = {
		id = "Sword",
		displayName = "Sword",
		damage = 18,

		-- Recovery is deliberately double the active window: that ratio is what makes a
		-- whiff cost something. Recovery also IS the attack cooldown — there is no
		-- separate tunable.
		windup = 0.14,
		active = 0.12,
		recovery = 0.26,
		staminaCost = 0,

		-- The box spans 0.5..5.5 studs forward of the root. arcHalfAngleCos trims the
		-- box corners to a 120 degree frontal cone; without it you can hit beside you.
		arcSize = Vector3.new(8, 6, 5),
		arcForwardOffset = 3.0,
		arcHalfAngleCos = 0.5,
		maxTargets = 8,

		blade = { size = Vector3.new(0.2, 4.0, 0.6), color = Color3.fromRGB(198, 204, 212) },
		grip = { size = Vector3.new(0.3, 1.0, 0.3), color = Color3.fromRGB(78, 58, 42) },
		guard = { size = Vector3.new(0.25, 0.25, 1.6), color = Color3.fromRGB(150, 120, 60) },
		gripOffset = CFrame.new(0, -1.1, 0) * CFrame.Angles(math.rad(-90), 0, 0),
	},
	-- Slow and heavy. Highest damage per swing and the longest reach, paid for with a
	-- 0.92s cycle — nearly twice the Sword's. Two swings kill a Skeleton, but whiffing
	-- one costs you most of a second, which is the trade.
	Greatsword = {
		id = "Greatsword",
		displayName = "Greatsword",
		damage = 34,

		windup = 0.30,
		active = 0.16,
		recovery = 0.46,
		staminaCost = 0,

		-- Wider and longer than the Sword: it sweeps a crowd.
		arcSize = Vector3.new(11, 7, 7),
		arcForwardOffset = 4.0,
		arcHalfAngleCos = 0.34, -- cos(70 degrees), a 140 degree sweep
		maxTargets = 8,

		blade = { size = Vector3.new(0.3, 5.6, 1.0), color = Color3.fromRGB(186, 192, 202) },
		grip = { size = Vector3.new(0.4, 1.6, 0.4), color = Color3.fromRGB(64, 48, 36) },
		guard = { size = Vector3.new(0.35, 0.35, 2.4), color = Color3.fromRGB(132, 106, 52) },
		gripOffset = CFrame.new(0, -1.4, 0) * CFrame.Angles(math.rad(-90), 0, 0),
	},

	-- Fast and short. Lowest damage per swing and the lowest sustained damage of the
	-- three, but a 0.28s cycle means you are committed for a third as long — the
	-- safest weapon rather than the weakest one.
	Daggers = {
		id = "Daggers",
		displayName = "Daggers",
		damage = 9,

		windup = 0.07,
		active = 0.08,
		recovery = 0.13,
		staminaCost = 0,

		-- Narrow: it does not sweep, it stabs one thing.
		arcSize = Vector3.new(5, 5, 4),
		arcForwardOffset = 2.0,
		arcHalfAngleCos = 0.70, -- cos(45 degrees), a 90 degree jab
		maxTargets = 3,

		blade = { size = Vector3.new(0.16, 2.2, 0.4), color = Color3.fromRGB(212, 216, 222) },
		grip = { size = Vector3.new(0.26, 0.8, 0.26), color = Color3.fromRGB(52, 44, 40) },
		guard = { size = Vector3.new(0.2, 0.2, 0.9), color = Color3.fromRGB(150, 150, 156) },
		gripOffset = CFrame.new(0, -0.7, 0) * CFrame.Angles(math.rad(-90), 0, 0),
	},
}

CombatConfig.defaultWeapon = "Sword"

-- Modifiers turn three weapons into dozens. A variant is a data row, never a new
-- weapon: WeaponStats folds these over an archetype and everything downstream reads
-- the resolved numbers.
--
-- `speed` scales the whole swing cycle, so a faster weapon is faster to start AND
-- faster to recover from. Scaling only one would make "attack speed" mean something
-- different on each archetype.
CombatConfig.modifiers = {
	Rusted = {
		id = "Rusted",
		prefix = "Rusted",
		description = "+15% attack speed, -10% damage",
		speed = 1.15,
		damage = 0.90,
	},
	Heavy = {
		id = "Heavy",
		prefix = "Heavy",
		description = "+25% damage, -15% attack speed",
		damage = 1.25,
		speed = 0.85,
	},
	Keen = {
		id = "Keen",
		prefix = "Keen",
		description = "+12% damage",
		damage = 1.12,
	},
	Swift = {
		id = "Swift",
		prefix = "Swift",
		description = "+20% attack speed",
		speed = 1.20,
	},
	Reaching = {
		id = "Reaching",
		prefix = "Reaching",
		description = "+1.5 studs reach",
		reach = 1.5,
	},
}

-- Ordered, because a seeded roll indexes it. Same contract as FloorConfig.pool:
-- reordering changes every seed's weapons.
CombatConfig.modifierPool = {
	"Rusted",
	"Heavy",
	"Keen",
	"Swift",
	"Reaching",
}

CombatConfig.archetypePool = {
	"Sword",
	"Greatsword",
	"Daggers",
}

-- Binding invariant: speed * duration (12.3 studs) must exceed sword reach (5.5), or
-- dodging out of an incoming swing does not work and the mechanic is decorative.
-- Phase01_Combat asserts that relation rather than the literals.
CombatConfig.dodge = {
	staminaCost = 25,
	speed = 56,
	duration = 0.22,
	iframes = 0.30,
	cooldown = 0.55,
	maxForce = 100000,
}

CombatConfig.trainingDummy = {
	enabled = true,
	name = "TrainingDummy",
	maxHealth = 250,
	resetDelay = 2.5,
	basePosition = Vector3.new(0, 0.5, -18),
	bodySize = Vector3.new(3, 6, 3),
	baseSize = Vector3.new(3, 1, 3),
	bodyColor = Color3.fromRGB(180, 140, 90),
	baseColor = Color3.fromRGB(96, 96, 104),
	material = Enum.Material.WoodPlanks,
	hitReactionTilt = 12,
	hitReactionTime = 0.18,
	koTilt = 72,
}

CombatConfig.feedback = {
	hitstop = 0.06,
	flashTime = 0.12,
	flashColor = Color3.fromRGB(255, 255, 255),
	soundMaxDistance = 90,
}

CombatConfig.limits = {
	minRequestInterval = 0.05,
}

return CombatConfig
