--!strict
-- Seeded generation, as a pure function of (seed, depth, template). No Instances, no
-- services, no world — which is the whole point: the golden-hash regression test is
-- arithmetic, needing no Studio, no player and no waiting.
--
-- Every draw comes from its own named sub-stream, `Rng.new(seed, "<key>", depth, ...)`.
-- Because Rng folds the ordered, separated key tuple into the sub-seed, adding a new
-- consumer later cannot shift an existing one. A Phase 7 loot roll will not silently
-- move Phase 6's enemies.
--
-- This module must construct its own sub-streams and never accept a live Rng from a
-- caller: otherwise call ORDER becomes load-bearing, and reordering two lines
-- somewhere else silently changes the world.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyConfig = require(ReplicatedStorage.Shared.EnemyConfig)
local FloorConfig = require(ReplicatedStorage.Shared.FloorConfig)
local LootConfig = require(ReplicatedStorage.Shared.LootConfig)
local RoomConfig = require(ReplicatedStorage.Shared.RoomConfig)
local Rng = require(ReplicatedStorage.Shared.Rng)

local FloorPlan = {}

export type EnemyPlacement = {
	kind: string,
	offset: Vector3,
	-- Loot is PRE-ROLLED here but not PRE-DECIDED. The plan stores a 0..1 roll and
	-- what the drop would be; whether it actually drops is compared against the
	-- live chance at kill time, which includes the player's Lucky Coin bonus.
	--
	-- That is what lets a relic affect drop rates without making generation depend
	-- on inventory. The roll stays a pure function of the seed, so it hashes; and
	-- since inventory is itself determined by seed and path, the whole thing is
	-- still reproducible.
	dropRoll: number,
	dropItem: string,
	bonusGold: number,
}

export type RewardPlan = {
	kind: string,
	amount: number,
}

export type Plan = {
	depth: number,
	template: string,
	enemies: { EnemyPlacement },
	reward: RewardPlan?,
	exits: { string },
}

-- Offsets are quantized before they are stored, so the hash cannot drift on
-- floating-point noise that no player could ever perceive.
local function quantize(value: number): number
	return math.floor(value * 100 + 0.5) / 100
end

-- ------------------------------------------------------------------- exits

-- Keyed on the CURRENT template, not on depth alone and not on the whole path.
-- Depth alone would offer the same pair however you arrived, making the choice
-- cosmetic; the full path prefix would make the digest O(2^depth) and untestable.
function FloorPlan.exitOptions(seed: number, depth: number, fromTemplate: string): { string }
	local pool = FloorConfig.pool
	local rng = Rng.new(seed, "exits", depth, fromTemplate)

	local first = pool[rng:int(1, #pool)]

	-- Walk forward from a seeded offset to guarantee a distinct second option
	-- without rejection-looping.
	local step = rng:int(1, #pool - 1)
	local firstIndex = table.find(pool, first) or 1
	local secondIndex = ((firstIndex - 1 + step) % #pool) + 1
	local second = pool[secondIndex]

	return { first, second }
end

-- --------------------------------------------------------------- encounter

-- Bounded rejection sampling. A plain ring sampler would stack unanchored rigs and
-- let physics resolve the overlap — and physics is not seeded, which would break
-- reproducibility in exactly the way this phase exists to prevent.
local function placeEnemies(seed: number, depth: number, template: string): { EnemyPlacement }
	local roomSpec = RoomConfig.templates[template]
	local encounter = roomSpec.encounter
	local placements: { EnemyPlacement } = {}

	local count = FloorConfig.countForDepth(depth, encounter.minCount, encounter.maxCount)
	if count <= 0 then
		return placements
	end

	local enemySpec = EnemyConfig.kinds[encounter.kind]
	local rootWidth = enemySpec.rig.rootSize.X
	local separation = rootWidth * FloorConfig.encounter.separationFactor

	-- Keep clear of the walls by the enemy's own width, so a rig never spawns
	-- intersecting geometry.
	local clearance = roomSpec.wallThickness + rootWidth + 2
	local limitX = math.max(2, roomSpec.interior.X / 2 - clearance)
	local limitZ = math.max(2, roomSpec.interior.Z / 2 - clearance)
	local radius = math.min(encounter.radius, math.min(limitX, limitZ))

	-- The real landing spot for THIS template, not the unclamped default, or a small
	-- room would reserve clearance around a point nobody ever stands on.
	local landing = FloorConfig.entranceOffsetFor(roomSpec.interior.Z)
	local entrance = Vector3.new(landing.X, 0, landing.Z)
	local entranceClear = FloorConfig.layout.entranceClearRadius
	local prizeClear = if roomSpec.reward ~= nil then RoomConfig.prize.pickupRadius else 0

	local rng = Rng.new(seed, "encounter", depth, template)

	local function acceptable(point: Vector3): boolean
		if (point - entrance).Magnitude < entranceClear then
			return false
		end
		if prizeClear > 0 and point.Magnitude < prizeClear then
			return false
		end
		for _, placed in placements do
			if (point - placed.offset).Magnitude < separation then
				return false
			end
		end
		return true
	end

	for index = 1, count do
		local chosen: Vector3? = nil
		for _ = 1, FloorConfig.encounter.maxAttempts do
			local candidate = Vector3.new(
				quantize(rng:number(-radius, radius)),
				0,
				quantize(rng:number(-radius, radius))
			)
			if acceptable(candidate) then
				chosen = candidate
				break
			end
		end

		-- Deterministic fallback so generation always terminates: a fixed ring slot
		-- derived from the index, which cannot collide with another index's slot.
		if chosen == nil then
			local angle = (index / count) * math.pi * 2
			chosen = Vector3.new(
				quantize(math.cos(angle) * radius * 0.8),
				0,
				quantize(math.sin(angle) * radius * 0.8 - entranceClear)
			)
		end

		local lootRng = Rng.new(seed, "loot", depth, template, index)
		table.insert(placements, {
			kind = encounter.kind,
			offset = chosen :: Vector3,
			dropRoll = quantize(lootRng:number()),
			dropItem = LootConfig.dropPool[lootRng:int(1, #LootConfig.dropPool)],
			bonusGold = lootRng:int(LootConfig.drops.bonusGoldMin, LootConfig.drops.bonusGoldMax),
		})
	end

	return placements
end

-- ------------------------------------------------------------------ reward

local function rollReward(seed: number, depth: number, template: string): RewardPlan?
	local roomSpec = RoomConfig.templates[template]
	local reward = roomSpec.reward
	if reward == nil then
		return nil
	end

	local rng = Rng.new(seed, "reward", depth, template)
	local amount = rng:number(reward.minAmount, reward.maxAmount)
	-- Gold is whole; a heal is a fraction of max health.
	if reward.kind == "gold" then
		amount = math.floor(amount + 0.5)
	else
		amount = quantize(amount)
	end

	return { kind = reward.kind, amount = amount }
end

-- ---------------------------------------------------------------- generate

function FloorPlan.generate(seed: number, depth: number, template: string): Plan
	return {
		depth = depth,
		template = template,
		enemies = placeEnemies(seed, depth, template),
		reward = rollReward(seed, depth, template),
		exits = FloorPlan.exitOptions(seed, depth, template),
	}
end

-- The template a run starts on. Seeded, so two runs on one seed open the same way.
function FloorPlan.startingTemplate(seed: number): string
	local pool = FloorConfig.pool
	return pool[Rng.new(seed, "start"):int(1, #pool)]
end

-- -------------------------------------------------------------------- hash

-- Fields are delimited, never bare-concatenated, for the same reason Rng's key parts
-- are: "1" .. "23" and "12" .. "3" must not collide.
function FloorPlan.hash(plan: Plan): string
	local parts = { `d={plan.depth}`, `t={plan.template}` }

	for _, placement in plan.enemies do
		table.insert(
			parts,
			`e={placement.kind}:{quantize(placement.offset.X)}:{quantize(placement.offset.Z)}`
				.. `:{placement.dropRoll}:{placement.dropItem}:{placement.bonusGold}`
		)
	end

	local reward = plan.reward
	table.insert(parts, if reward ~= nil then `r={reward.kind}:{reward.amount}` else "r=none")

	for index, exit in plan.exits do
		table.insert(parts, `x{index}={exit}`)
	end

	return table.concat(parts, "|")
end

-- Walks every reachable (depth, template) pair rather than one path, so the golden
-- hash covers the whole generated tree and not just whichever way a tester happened
-- to walk. Linear in depth x pool, because exitOptions keys on the current template
-- rather than the full path.
function FloorPlan.digest(seed: number, maxDepth: number): string
	local parts = {
		`v={FloorConfig.generationVersion}`,
		`s={seed}`,
		`start={FloorPlan.startingTemplate(seed)}`,
	}

	for depth = 1, maxDepth do
		-- Ordered pool, never pairs over RoomConfig.templates: Luau hash order is
		-- not stable and the digest would flap between runs for no reason.
		for _, template in FloorConfig.pool do
			table.insert(parts, FloorPlan.hash(FloorPlan.generate(seed, depth, template)))
		end
	end

	return table.concat(parts, "||")
end

-- A short, stable fingerprint of the digest, for logging and for the spec's committed
-- constant. Not cryptographic — it only has to change when generation changes.
function FloorPlan.fingerprint(seed: number, maxDepth: number): string
	local text = FloorPlan.digest(seed, maxDepth)
	local h1, h2 = 0x811C9DC5, 0x01000193
	for i = 1, #text do
		h1 = bit32.bxor(h1, text:byte(i))
		h1 = bit32.band(h1 * 16777619, 0xFFFFFFFF)
		h2 = bit32.band(bit32.bxor(h2 + text:byte(i) * (i % 31 + 1), h1), 0xFFFFFFFF)
	end
	return string.format("%08x%08x", h1, h2)
end

return FloorPlan
