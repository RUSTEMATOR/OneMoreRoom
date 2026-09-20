--!strict
-- Bosses as data. The acceptance criterion for this phase is architectural: a second
-- boss must be a config plus custom mechanics, never a fork of the Warden. So
-- everything here is declarative, and BossService reads it without knowing which boss
-- it is running.
--
-- Note what is NOT here: an arena. A boss arena is a room template
-- (`RoomConfig.templates.Boss`), so a boss fight goes through the same seal, clear
-- and exit machinery as every other room. Building a parallel arena system would
-- have meant re-solving sealing, occupancy, resets and doors for one encounter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.Assets.AssetIds)

local BossConfig = {}

export type Attack = {
	id: string,
	kind: string,
	damage: number,
	windup: number,
	recovery: number,
	cooldown: number,
	-- Melee arcs use range plus a half-angle cosine; radial slams use radius.
	range: number?,
	halfAngleCos: number?,
	radius: number?,
	telegraphColor: Color3,
}

export type Phase = {
	id: string,
	displayName: string,
	-- The phase is active while health fraction is at or below this and above the
	-- next phase's threshold. Listed descending.
	fromHealthFraction: number,
	attacks: { string },
	walkSpeed: number,
	-- Optional periodic summon while this phase is active.
	summonKind: string?,
	summonCount: number?,
	summonInterval: number?,
	maxSummons: number?,
}

export type Boss = {
	id: string,
	displayName: string,
	maxHealth: number,
	-- Brief invulnerability and a pause at each threshold, so a transition reads as
	-- an event rather than a number quietly changing.
	transitionTime: number,
	phases: { Phase },
	attacks: { [string]: Attack },
	rig: any,
}

BossConfig.bosses = {
	Warden = {
		id = "Warden",
		displayName = "The Warden",

		-- 900 HP is 50 Sword swings, or 27 Greatsword swings. Long enough to be a
		-- fight with three distinct acts, short enough that losing it does not cost
		-- ten minutes.
		maxHealth = 900,
		transitionTime = 1.6,

		phases = {
			{
				id = "Sword",
				displayName = "The Warden raises its blade",
				fromHealthFraction = 1.0,
				attacks = { "Cleave" },
				walkSpeed = 12,
			},
			{
				id = "Summon",
				displayName = "The Warden calls the dead",
				fromHealthFraction = 0.66,
				attacks = { "Cleave" },
				walkSpeed = 10,
				summonKind = "Skeleton",
				summonCount = 2,
				summonInterval = 9.0,
				-- Capped, or a slow kill buries the arena in skeletons.
				maxSummons = 4,
			},
			{
				id = "Arena",
				displayName = "The Warden strikes the ground",
				fromHealthFraction = 0.33,
				attacks = { "Cleave", "Slam" },
				walkSpeed = 14,
			},
		},

		attacks = {
			Cleave = {
				id = "Cleave",
				kind = "arc",
				damage = 20,
				-- Longer telegraph than a Skeleton's 0.45: a boss you cannot read is
				-- not hard, it is noise.
				windup = 0.65,
				recovery = 0.5,
				cooldown = 1.9,
				range = 11,
				halfAngleCos = 0.2,
				telegraphColor = Color3.fromRGB(226, 96, 78),
			},
			Slam = {
				id = "Slam",
				kind = "radial",
				damage = 28,
				-- The long windup is the fight's core read: it covers the whole
				-- arena, so the answer is to dodge through it, not to run.
				windup = 1.0,
				recovery = 0.8,
				cooldown = 5.5,
				radius = 24,
				telegraphColor = Color3.fromRGB(236, 158, 62),
			},
		},

		-- Reskinned alongside the Husks and the Sentry, not just renamed in flavour
		-- text: same CorrodedMetal/Metal family the rest of the biome uses, scaled up.
		-- Amber rather than the Husks' cyan/ember/magenta -- ties to the telegraph
		-- colour its own attacks already draw on the floor, so "amber glow" reads as
		-- Warden specifically before a player even sees its silhouette.
		rig = {
			torsoSize = Vector3.new(4, 4.4, 2),
			headSize = Vector3.new(2.4, 2.4, 2.4),
			rootSize = Vector3.new(4, 4.4, 2),
			boneColor = Color3.fromRGB(70, 66, 62),
			torsoColor = Color3.fromRGB(120, 92, 42),
			material = Enum.Material.CorrodedMetal,
			lungeAngle = 30,
			textureId = AssetIds.textures.theWarden,
		},
	},
}

BossConfig.rewards = {
	goldPerBoss = 120,
	soulShardBonus = 8,
}

-- The telegraph disc drawn on the floor before a radial attack lands. Purely a read,
-- but a read the fight is unfair without.
BossConfig.telegraph = {
	thickness = 0.2,
	height = 0.15,
	transparency = 0.45,
}

return BossConfig
