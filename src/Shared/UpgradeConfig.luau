--!strict
-- Permanent upgrades, bought with Soul Shards and kept across runs.
--
-- Deliberately restrained, as the design insists: four upgrades with small
-- per-level steps. The game should not become an RPG where meta progression
-- replaces skill, so a fully-upgraded player is meaningfully stronger but not
-- playing a different game.
--
-- Same shape as every other config here: plain named fields, and the service folds
-- them. Adding an upgrade is a data entry.

local UpgradeConfig = {}

export type Upgrade = {
	id: string,
	displayName: string,
	description: string,
	maxLevel: number,
	baseCost: number,
	costStep: number,

	healthPercentPerLevel: number?,
	damagePercentPerLevel: number?,
	goldPercentPerLevel: number?,
	startingRelicsPerLevel: number?,
}

UpgradeConfig.upgrades = {
	Vitality = {
		id = "Vitality",
		displayName = "Vitality",
		description = "+5% maximum health per level",
		maxLevel = 8,
		baseCost = 6,
		costStep = 4,
		healthPercentPerLevel = 0.05,
	},
	Power = {
		id = "Power",
		displayName = "Power",
		description = "+3% damage per level",
		maxLevel = 8,
		baseCost = 8,
		costStep = 5,
		damagePercentPerLevel = 0.03,
	},
	Fortune = {
		id = "Fortune",
		displayName = "Fortune",
		description = "+5% gold per level",
		maxLevel = 6,
		baseCost = 5,
		costStep = 3,
		goldPercentPerLevel = 0.05,
	},
	-- The one that changes how a run opens rather than how it plays. Kept short and
	-- expensive: starting with three relics would flatten the early floors.
	Heirloom = {
		id = "Heirloom",
		displayName = "Heirloom",
		description = "Begin each run with one more relic",
		maxLevel = 3,
		baseCost = 14,
		costStep = 12,
		startingRelicsPerLevel = 1,
	},
}

-- Ordered, because the lobby lays shrines out in this order and a spec indexes it.
UpgradeConfig.pool = {
	"Vitality",
	"Power",
	"Fortune",
	"Heirloom",
}

-- A linear curve rather than exponential. Over 8 levels Vitality costs 6+10+...+34 =
-- 160 shards, which at 2 per floor is roughly 80 floors of play — enough that it is
-- a goal, not so much that it is a second job.
function UpgradeConfig.costFor(upgradeId: string, currentLevel: number): number
	local upgrade = UpgradeConfig.upgrades[upgradeId]
	if upgrade == nil then
		return math.huge
	end
	if currentLevel >= upgrade.maxLevel then
		return math.huge
	end
	return upgrade.baseCost + upgrade.costStep * currentLevel
end

function UpgradeConfig.totalCost(upgradeId: string, throughLevel: number): number
	local total = 0
	for level = 0, throughLevel - 1 do
		total += UpgradeConfig.costFor(upgradeId, level)
	end
	return total
end

-- Walk-into shrines in the lobby, one per upgrade. No interaction UI exists until
-- Phase 12, and proximity needs none — the same reasoning as room prizes and loot.
UpgradeConfig.shrine = {
	enabled = true,
	origin = Vector3.new(-26, 0, 6),
	spacing = 9,
	size = Vector3.new(3, 5, 3),
	baseColor = Color3.fromRGB(78, 74, 92),
	litColor = Color3.fromRGB(150, 122, 224),
	spentColor = Color3.fromRGB(96, 96, 104),
	radius = 6,
	-- A cooldown, or walking through a shrine would drain every shard you own in
	-- the handful of frames you are standing in it.
	purchaseCooldown = 1.0,
}

return UpgradeConfig
