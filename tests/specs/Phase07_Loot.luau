--!strict
-- Phase 7 acceptance: loot drops on the run seed, relics measurably change combat
-- maths, and every award is server-granted.
--
-- The interesting property is that drops are PRE-ROLLED but not PRE-DECIDED. The plan
-- fixes a 0..1 roll per enemy; whether it clears the bar is decided at kill time
-- against the live party loot bonus. That is what lets Lucky Coin raise drop rates
-- without making generation depend on inventory — and the run stays reproducible,
-- because inventory is itself a function of seed and path.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Spec = require(script.Parent.Spec)

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local FloorConfig = require(ReplicatedStorage.Shared.FloorConfig)
local FloorPlan = require(ReplicatedStorage.Shared.FloorPlan)
local LootConfig = require(ReplicatedStorage.Shared.LootConfig)
local WeaponStats = require(ReplicatedStorage.Shared.WeaponStats)
local FloorService = require(ServerScriptService.Services.FloorService)
local InventoryService = require(ServerScriptService.Services.InventoryService)
local PlayerService = require(ServerScriptService.Services.PlayerService)
local RunSessionService = require(ServerScriptService.Services.RunSessionService)
local SaveService = require(ServerScriptService.Services.SaveService)

local SEED = 771177

return function()
	local spec = Spec.new("Phase07_Loot")

	-- ------------------------------------------------------ A. the loot data

	spec:check("there is a drop pool", #LootConfig.dropPool > 0, #LootConfig.dropPool)
	for _, id in LootConfig.dropPool do
		local item = LootConfig.items[id]
		spec:truthy(`pooled item {id} exists`, item)
		if item ~= nil then
			spec:truthy(`{id} has a category`, table.find(LootConfig.categories, item.category))
			spec:check(`{id} does something`, next(item.effects) ~= nil)
			spec:check(`{id} has a description`, #item.description > 0)
		end
	end

	-- The three the design names by hand, with the numbers it names.
	spec:equals(
		"Blood Charm is +10% damage",
		LootConfig.items.BloodCharm.effects.damageMultiplier,
		1.10
	)
	spec:equals(
		"Blood Charm is conditional on low health",
		LootConfig.items.BloodCharm.effects.belowHealthFraction,
		0.30
	)
	spec:equals(
		"Iron Heart is +25 max health",
		LootConfig.items.IronHeart.effects.maxHealthBonus,
		25
	)
	spec:equals(
		"Lucky Coin is +10% loot chance",
		LootConfig.items.LuckyCoin.effects.lootChanceBonus,
		0.10
	)

	spec:check(
		"an elite is likelier to drop than a basic enemy",
		LootConfig.drops.eliteChance > LootConfig.drops.baseChance
	)
	spec:check(
		"drop chance is capped so Lucky Coin cannot make it certain",
		LootConfig.drops.maxChance < 1
	)

	-- Weapons are GENERATED, not catalogued, so the fixed drop pool holds only
	-- relics and armour. A weapon in here would mean someone had catalogued one.
	local weaponInPool = false
	for _, id in LootConfig.dropPool do
		if LootConfig.items[id].category == "Weapon" then
			weaponInPool = true
		end
	end
	spec:truthy("the fixed pool holds no weapons", not weaponInPool)
	spec:check("weapons have a share of drops", LootConfig.drops.weaponShare > 0)

	-- ------------------------------------------------- B. drops are seeded

	for depth = 1, 6 do
		for _, template in FloorConfig.pool do
			local plan = FloorPlan.generate(SEED, depth, template)
			for index, placement in plan.enemies do
				spec:check(
					`{template} d{depth} e{index} roll is a probability`,
					placement.dropRoll >= 0 and placement.dropRoll <= 1,
					placement.dropRoll
				)
				-- A weapon drop is an archetype, not a catalogue entry: weapons are
				-- generated rather than catalogued, so "is it real" means something
				-- different for each kind.
				local realDrop = if placement.dropKind == "weapon"
					then WeaponStats.isArchetype(placement.dropItem)
					else LootConfig.items[placement.dropItem] ~= nil
				spec:truthy(
					`{template} d{depth} e{index} drop is real ({placement.dropKind})`,
					realDrop
				)
				spec:check(
					`{template} d{depth} e{index} bonus gold is in range`,
					placement.bonusGold >= LootConfig.drops.bonusGoldMin
						and placement.bonusGold <= LootConfig.drops.bonusGoldMax,
					placement.bonusGold
				)
			end
		end
	end

	-- Replaying a seed must replay its loot, not just its layout.
	local first = FloorPlan.generate(SEED, 3, "Combat")
	local again = FloorPlan.generate(SEED, 3, "Combat")
	local sameLoot = true
	for index, placement in first.enemies do
		local other = again.enemies[index]
		if
			other == nil
			or other.dropRoll ~= placement.dropRoll
			or other.dropItem ~= placement.dropItem
			or other.bonusGold ~= placement.bonusGold
		then
			sameLoot = false
		end
	end
	spec:truthy("the same seed rolls the same loot", sameLoot)
	spec:check(
		"loot is part of the hash",
		first.enemies[1] == nil
			or string.find(FloorPlan.hash(first), first.enemies[1].dropItem, 1, true) ~= nil
	)

	-- ------------------------------------------- player-driven checks

	local player = Players:GetPlayers()[1]
	if player == nil or not PlayerService.isActionable(player) then
		spec:check("a live player is present", false, "run in Play mode")
		return spec:finish()
	end

	local ok, err = pcall(function()
		InventoryService.clearRun()
		InventoryService.clearPickups()
		PlayerService.setHealth(player, CombatConfig.player.maxHealth)

		-- ------------------------------------------------- C. granting

		spec:equals("inventory starts empty", #InventoryService.items(player), 0)
		spec:truthy("an unknown item is refused", not InventoryService.grant(player, "NotAnItem"))

		spec:truthy("a real item is granted", InventoryService.grant(player, "Whetstone"))
		spec:equals("the item is held", InventoryService.count(player, "Whetstone"), 1)

		-- ------------------------------------- D. relics change the maths

		-- Whetstone is unconditional +8%.
		spec:check(
			"an unconditional relic raises outgoing damage",
			math.abs(InventoryService.outgoingDamageMultiplier(player) - 1.08) < 1e-6,
			InventoryService.outgoingDamageMultiplier(player)
		)

		-- Blood Charm is conditional, so it must be inert at full health and live
		-- when hurt. A cached total would get this wrong the instant health moved.
		InventoryService.grant(player, "BloodCharm")
		PlayerService.setHealth(player, (PlayerService.get(player) :: any).maxHealth)
		local atFull = InventoryService.outgoingDamageMultiplier(player)
		spec:check("Blood Charm is inert at full health", math.abs(atFull - 1.08) < 1e-6, atFull)

		local maxHealth = (PlayerService.get(player) :: any).maxHealth
		PlayerService.setHealth(player, maxHealth * 0.2)
		local whenHurt = InventoryService.outgoingDamageMultiplier(player)
		spec:check(
			"Blood Charm activates below the threshold",
			whenHurt > atFull,
			`{atFull} -> {whenHurt}`
		)
		spec:check(
			"the two relics multiply together",
			math.abs(whenHurt - 1.08 * 1.10) < 1e-6,
			whenHurt
		)

		-- Iron Heart raises the ceiling, and current health rises with it rather
		-- than leaving a bigger empty bar.
		PlayerService.setHealth(player, maxHealth)
		local beforeHeart = (PlayerService.get(player) :: any).maxHealth
		local healthBeforeHeart = (PlayerService.get(player) :: any).health
		InventoryService.grant(player, "IronHeart")
		local afterHeart = PlayerService.get(player) :: any
		spec:equals("Iron Heart raises max health by 25", afterHeart.maxHealth, beforeHeart + 25)
		spec:check(
			"current health rises with the ceiling",
			afterHeart.health > healthBeforeHeart,
			`{healthBeforeHeart} -> {afterHeart.health}`
		)

		-- Armour reduces incoming damage.
		InventoryService.grant(player, "IronPlate")
		spec:check(
			"armour reduces incoming damage",
			InventoryService.incomingDamageMultiplier(player) < 1,
			InventoryService.incomingDamageMultiplier(player)
		)

		InventoryService.grant(player, "LuckyCoin")
		spec:check(
			"Lucky Coin raises the loot bonus",
			InventoryService.lootChanceBonus(player) >= 0.10,
			InventoryService.lootChanceBonus(player)
		)
		spec:check(
			"the party bonus sees it",
			InventoryService.partyLootChanceBonus() >= 0.10,
			InventoryService.partyLootChanceBonus()
		)

		-- ----------------------------------------------- E. pickups

		local root = (PlayerService.get(player) :: any).rootPart :: BasePart
		InventoryService.clearRun()
		InventoryService.clearPickups()
		spec:equals("clearing the run empties the inventory", #InventoryService.items(player), 0)
		spec:equals(
			"clearing the run restores base max health",
			(PlayerService.get(player) :: any).maxHealth,
			CombatConfig.player.maxHealth
		)

		RunSessionService.begin(SEED)
		local goldBefore = (RunSessionService.get() :: any).gold

		-- Spawn it right on the player so the proximity poll takes it.
		InventoryService.spawnPickup("SecondWind", 9, CFrame.new(root.Position), workspace)
		spec:equals("the pickup exists", InventoryService.activePickupCount(), 1)

		task.wait(0.5)
		spec:equals(
			"walking into a pickup grants it",
			InventoryService.count(player, "SecondWind"),
			1
		)
		spec:equals("the pickup is consumed", InventoryService.activePickupCount(), 0)
		spec:check(
			"the pickup paid its bonus gold",
			(RunSessionService.get() :: any).gold >= goldBefore + 9,
			`{goldBefore} -> {(RunSessionService.get() :: any).gold}`
		)
		spec:check(
			"stamina regen relic applies",
			InventoryService.staminaRegenMultiplier(player) > 1,
			InventoryService.staminaRegenMultiplier(player)
		)

		-- --------------------------------------------- F. soul shards

		local data = SaveService.load(player)
		local shardsBefore = data.soulShards

		local awarded = InventoryService.awardRunEnd(4)
		spec:check("ending a run pays Soul Shards", awarded > 0, awarded)
		spec:equals(
			"the payout scales with floors cleared",
			awarded,
			4 * LootConfig.soulShards.perFloorCleared
		)
		spec:equals(
			"the shards were banked",
			SaveService.load(player).soulShards,
			shardsBefore + awarded
		)
		spec:equals("a zero-floor run pays nothing", InventoryService.awardRunEnd(0), 0)

		-- Equipment is run-scoped; Soul Shards are not. That split is the economy.
		local shardsAfter = SaveService.load(player).soulShards
		FloorService.endRun()
		spec:equals("ending the run cleared equipment", #InventoryService.items(player), 0)
		spec:check(
			"ending the run kept the Soul Shards",
			SaveService.load(player).soulShards >= shardsAfter,
			SaveService.load(player).soulShards
		)
	end)

	if not ok then
		spec:check("loot checks completed without error", false, err)
	end

	-- --------------------------------------------------------- G. teardown

	FloorService.endRun()
	InventoryService.clearRun()
	InventoryService.clearPickups()
	PlayerService.setHealth(player, CombatConfig.player.maxHealth)
	PlayerService.setStamina(player, CombatConfig.stamina.max)

	spec:equals("teardown emptied the inventory", #InventoryService.items(player), 0)
	spec:equals("teardown removed every pickup", InventoryService.activePickupCount(), 0)
	spec:equals(
		"teardown restored base max health",
		(PlayerService.get(player) :: any).maxHealth,
		CombatConfig.player.maxHealth
	)
	spec:equals("teardown left Generated empty", #FloorService.generatedFolder():GetChildren(), 0)

	return spec:finish()
end
