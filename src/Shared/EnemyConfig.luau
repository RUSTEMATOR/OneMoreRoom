--!strict
-- Enemy tunables. Same contract as CombatConfig: this is the only place an enemy
-- number lives, and the client may read it freely because the server re-derives
-- everything it enforces.
--
-- Internal `id`/kind keys ("Skeleton", "Archer", ...) are stable technical
-- identifiers, referenced by RoomConfig encounters, loot rolls and the golden hash —
-- they do NOT change with a reskin. `displayName` and `rig` are what the player
-- actually sees, and that is where a setting lives. See GAME_DESIGN.md's Setting
-- section: this biome reads as rusted machine-husks in a dead server-cathedral, not
-- literal skeletons, even though the code keeps calling them that.

local EnemyConfig = {}

EnemyConfig.kinds = {
	Skeleton = {
		id = "Skeleton",
		displayName = "Rust Husk",

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
			-- Rusted chrome rather than bone: corroded plate over a dark chassis, lit
			-- by a single failing status light instead of a face.
			boneColor = Color3.fromRGB(120, 108, 96),
			torsoColor = Color3.fromRGB(74, 70, 66),
			material = Enum.Material.CorrodedMetal,
			lungeAngle = 24,
		},
	},

	-- The Archer is the answer to the Skeleton's own design note above: "backing off
	-- is always an option". Against melee-only enemies that is not an option, it is
	-- the dominant strategy, and ten floors of it is ten floors of the same fight.
	-- An Archer punishes standing still at range, so the player has to choose which
	-- threat to close on — which is the decision the room was supposed to be asking.
	--
	-- It is deliberately fragile: 35 HP is two sword swings. Reaching it is the whole
	-- challenge, so surviving once reached would just be tedious.
	--
	-- Reskinned as a Signal Sentry: a tripod-mounted targeting drone rather than an
	-- archer with a bow. The projectile is code-named "Bolt" and coloured as a rail
	-- charge, not a fletched arrow.
	Archer = {
		id = "Archer",
		displayName = "Signal Sentry",

		maxHealth = 35,
		-- Unused by the melee path -- the arrow carries the damage -- but kept in the
		-- same field so anything reading `spec.damage` for a UI or a tooltip is right.
		damage = 12,
		-- Slower than the player's 16 so a committed charge always closes. An archer
		-- that could outrun you would be unkillable rather than difficult.
		walkSpeed = 10,

		-- Sees further than it can be seen from, which is the point of a bow.
		detectRange = 44,
		leashRange = 70,
		-- The distance at which it *fires*, not the distance at which it touches you.
		attackRange = 40,

		noticeTime = 0.4,
		-- A long, obvious draw. The arrow is fast enough that reacting to the arrow
		-- is hopeless; you are meant to read the draw and move before it looses.
		attackWindup = 0.6,
		attackRecovery = 0.3,
		attackCooldown = 1.6,

		staggerTime = 0.3,
		despawnDelay = 2.5,

		goldReward = 9,

		ranged = {
			-- Holds this far out, and backs away if you get inside retreatRange. The
			-- band between them is where it stands and shoots.
			preferredRange = 24,
			retreatRange = 15,

			-- 60 studs/s over the preferred 24 is a 0.4 s flight -- longer than the
			-- 0.30 s dodge window, so a dodge read off the draw beats the arrow and a
			-- dodge read off the arrow does not.
			projectileSpeed = 60,
			projectileRadius = 0.6,
			projectileLife = 2.5,
			projectileDamage = 12,
			-- Where the bolt leaves, measured along the line of fire rather than in
			-- rig space: the sentry stands still to charge and keeps a stale facing.
			muzzleHeight = 0.6,
			muzzleForward = 1.4,
			-- Neon rail-charge cyan. Reads as a threat across a dark room long before
			-- the tripod silhouette does.
			projectileColor = Color3.fromRGB(80, 235, 235),
		},

		rig = {
			torsoSize = Vector3.new(1.8, 2, 1),
			headSize = Vector3.new(1.3, 1.3, 1.3),
			rootSize = Vector3.new(1.8, 2, 1),
			boneColor = Color3.fromRGB(60, 62, 68),
			-- Dark chassis with the same neon accent as its own bolt, so a player who
			-- has learned to fear the cyan glow reads the threat before it fires.
			torsoColor = Color3.fromRGB(40, 44, 50),
			material = Enum.Material.Metal,
			lungeAngle = 10,
		},
	},

	-- The Elite is a data entry, not a new enemy: same state machine, harder numbers.
	-- 150 HP is 9 sword swings and 22 damage kills a full-health player in 5 hits, so
	-- it is a genuine threat without being a boss — that is Phase 10.
	SkeletonElite = {
		id = "SkeletonElite",
		displayName = "Chrome Husk",

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
			-- Polished rather than corroded: this one still has power. The magenta
			-- accent is the "elite" tell across a room, same trick as the Sentry's
			-- cyan but a colour no basic Husk carries.
			boneColor = Color3.fromRGB(200, 200, 210),
			torsoColor = Color3.fromRGB(150, 60, 150),
			material = Enum.Material.Metal,
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
	-- Deliberately beyond its own detectRange (34) from the spawn pad and the
	-- upgrade shrines. Closer than this and an idle player is chewed on while
	-- standing in the lobby reading shrine prices.
	position = Vector3.new(14, 3, -42),
	respawnDelay = 6.0,
}

return EnemyConfig
