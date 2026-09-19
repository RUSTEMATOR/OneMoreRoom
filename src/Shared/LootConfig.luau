--!strict
-- Loot tables and equipment definitions.
--
-- Three categories, as the design calls for: Weapon, Armor, Relic. Only Armor and
-- Relic are populated here. Weapon drops need the archetypes and modifiers that are
-- Phase 8's whole subject, and dropping "a Sword" when a Sword is the only weapon in
-- the game would be a reward that changes nothing. The category exists so Phase 8 is
-- a data entry.
--
-- Every effect is a plain named field. Nothing here knows how the effect is applied;
-- InventoryService aggregates, and combat reads the aggregate.

local LootConfig = {}

export type Effects = {
	-- Multiplies damage this player deals.
	damageMultiplier: number?,
	-- Multiplies damage this player takes.
	damageTakenMultiplier: number?,
	maxHealthBonus: number?,
	staminaRegenMultiplier: number?,
	-- Added to the roll chance that an enemy drops anything.
	lootChanceBonus: number?,
	-- Applies only while the holder is below this fraction of max health.
	belowHealthFraction: number?,
}

export type Item = {
	id: string,
	displayName: string,
	category: string,
	description: string,
	effects: Effects,
}

LootConfig.categories = { "Relic", "Armor", "Weapon" }

LootConfig.items = {
	-- The three the design names by hand.
	BloodCharm = {
		id = "BloodCharm",
		displayName = "Blood Charm",
		category = "Relic",
		description = "+10% damage while below 30% health",
		effects = { damageMultiplier = 1.10, belowHealthFraction = 0.30 },
	},
	IronHeart = {
		id = "IronHeart",
		displayName = "Iron Heart",
		category = "Relic",
		description = "+25 maximum health",
		effects = { maxHealthBonus = 25 },
	},
	LuckyCoin = {
		id = "LuckyCoin",
		displayName = "Lucky Coin",
		category = "Relic",
		description = "+10% chance for additional loot",
		effects = { lootChanceBonus = 0.10 },
	},

	-- Two more relics, to show the category is data rather than a hard-coded three.
	Whetstone = {
		id = "Whetstone",
		displayName = "Whetstone",
		category = "Relic",
		description = "+8% damage",
		effects = { damageMultiplier = 1.08 },
	},
	SecondWind = {
		id = "SecondWind",
		displayName = "Second Wind",
		category = "Relic",
		description = "+25% stamina regeneration",
		effects = { staminaRegenMultiplier = 1.25 },
	},

	LeatherVest = {
		id = "LeatherVest",
		displayName = "Leather Vest",
		category = "Armor",
		description = "+15 maximum health",
		effects = { maxHealthBonus = 15 },
	},
	IronPlate = {
		id = "IronPlate",
		displayName = "Iron Plate",
		category = "Armor",
		description = "-12% damage taken",
		effects = { damageTakenMultiplier = 0.88 },
	},
	Shroud = {
		id = "Shroud",
		displayName = "Shroud",
		category = "Armor",
		description = "-6% damage taken, +10% stamina regeneration",
		effects = { damageTakenMultiplier = 0.94, staminaRegenMultiplier = 1.10 },
	},
}

-- The ordered pool a drop is rolled from. ORDER IS PART OF THE SEED CONTRACT, exactly
-- as FloorConfig.pool is: the roll indexes this list, so reordering it changes every
-- seed's loot. Never build it by iterating LootConfig.items — Luau hash order is not
-- stable and the golden hash would flap.
LootConfig.dropPool = {
	"BloodCharm",
	"IronHeart",
	"LuckyCoin",
	"Whetstone",
	"SecondWind",
	"LeatherVest",
	"IronPlate",
	"Shroud",
}

LootConfig.drops = {
	-- Chance that a given enemy carries equipment at all. Elites are worth killing.
	baseChance = 0.18,
	eliteChance = 0.55,
	-- Ceiling so Lucky Coin stacking cannot make every enemy a piñata.
	maxChance = 0.85,
	-- Gold carried by a dropped stack, on top of the flat per-kill award.
	bonusGoldMin = 4,
	bonusGoldMax = 14,
}

-- Permanent currency. Awarded when a run ends, scaled by how far it got, so a deep
-- failed run is still worth something.
LootConfig.soulShards = {
	perFloorCleared = 2,
	completionBonus = 5,
}

LootConfig.pickup = {
	size = Vector3.new(1.6, 1.6, 1.6),
	height = 2.2,
	radius = 5,
	spinPerSecond = 2.0,
	relicColor = Color3.fromRGB(196, 132, 232),
	armorColor = Color3.fromRGB(124, 178, 226),
	weaponColor = Color3.fromRGB(226, 156, 96),
}

function LootConfig.colorFor(category: string): Color3
	if category == "Armor" then
		return LootConfig.pickup.armorColor
	elseif category == "Weapon" then
		return LootConfig.pickup.weaponColor
	end
	return LootConfig.pickup.relicColor
end

return LootConfig
