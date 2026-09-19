--!strict
-- Phase 9 acceptance: two economies that never mix.
--
-- Death clears the run and preserves the meta. A purchased upgrade is active on the
-- next run. Together those two sentences are the loop the MVP gate is defined by:
-- die, return to the lobby, buy something, start again stronger.
--
-- Purchases are server-authoritative in the strongest available sense: there is no
-- remote at all. You walk into a shrine and the server decides, so a client cannot
-- even ask for a specific upgrade, let alone a price.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Spec = require(script.Parent.Spec)

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local LootConfig = require(ReplicatedStorage.Shared.LootConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)
local FloorService = require(ServerScriptService.Services.FloorService)
local InventoryService = require(ServerScriptService.Services.InventoryService)
local PlayerService = require(ServerScriptService.Services.PlayerService)
local ProgressionService = require(ServerScriptService.Services.ProgressionService)
local RunSessionService = require(ServerScriptService.Services.RunSessionService)
local SaveService = require(ServerScriptService.Services.SaveService)

local SEED = 990099

return function()
	local spec = Spec.new("Phase09_Progression")

	-- ------------------------------------------------------ A. the upgrades

	spec:check("there are upgrades to buy", #UpgradeConfig.pool > 0, #UpgradeConfig.pool)
	for _, id in UpgradeConfig.pool do
		local upgrade = UpgradeConfig.upgrades[id]
		spec:truthy(`{id} exists`, upgrade)
		if upgrade ~= nil then
			spec:check(`{id} has levels`, upgrade.maxLevel > 0)
			spec:check(`{id} costs something`, upgrade.baseCost > 0)
			spec:check(
				`{id} does something`,
				upgrade.healthPercentPerLevel ~= nil
					or upgrade.damagePercentPerLevel ~= nil
					or upgrade.goldPercentPerLevel ~= nil
					or upgrade.startingRelicsPerLevel ~= nil
			)
			-- Each level must cost more than the last, or buying is a formality.
			spec:check(
				`{id} gets more expensive`,
				UpgradeConfig.costFor(id, 1) > UpgradeConfig.costFor(id, 0),
				`{UpgradeConfig.costFor(id, 0)} -> {UpgradeConfig.costFor(id, 1)}`
			)
			spec:equals(
				`{id} cannot be bought past max`,
				UpgradeConfig.costFor(id, upgrade.maxLevel),
				math.huge
			)
		end
	end

	-- Restrained by design. A fully-upgraded player should be meaningfully stronger,
	-- not playing a different game.
	local vitality = UpgradeConfig.upgrades.Vitality
	local power = UpgradeConfig.upgrades.Power
	spec:check(
		"max Vitality is under +50% health",
		vitality.healthPercentPerLevel * vitality.maxLevel < 0.5,
		vitality.healthPercentPerLevel * vitality.maxLevel
	)
	spec:check(
		"max Power is under +30% damage",
		power.damagePercentPerLevel * power.maxLevel < 0.3,
		power.damagePercentPerLevel * power.maxLevel
	)

	spec:equals("an unknown upgrade costs infinity", UpgradeConfig.costFor("Nope", 0), math.huge)

	-- ------------------------------------------------ player-driven checks

	local player = Players:GetPlayers()[1]
	if player == nil or not PlayerService.isActionable(player) then
		spec:check("a live player is present", false, "run in Play mode")
		return spec:finish()
	end

	-- Snapshot the real save so the spec can spend freely and put it back.
	local data = SaveService.load(player)
	local savedShards = data.soulShards
	local savedUpgrades = table.clone(data.permanentUpgrades)

	local ok, err = pcall(function()
		FloorService.endRun()
		InventoryService.clearRun()
		InventoryService.clearPickups()

		-- Start from a clean, known meta state.
		data.soulShards = 0
		table.clear(data.permanentUpgrades)
		InventoryService.refreshMaxHealth(player)

		-- ------------------------------------------------- B. purchasing

		local bought, reason = ProgressionService.purchase(player, "Vitality")
		spec:check("buying with no shards is refused", not bought)
		spec:equals("the refusal reason is shards", reason, "shards")
		spec:equals("a refused purchase spends nothing", SaveService.load(player).soulShards, 0)

		local _, unknownReason = ProgressionService.purchase(player, "NotAnUpgrade")
		spec:equals("an unknown upgrade is refused", unknownReason, "unknown")

		data.soulShards = 500
		local cost = ProgressionService.nextCost(player, "Vitality")
		local okBuy = ProgressionService.purchase(player, "Vitality")
		spec:check("buying with shards succeeds", okBuy)
		spec:equals("the level went up", ProgressionService.levelOf(player, "Vitality"), 1)
		spec:equals("the shards were spent", SaveService.load(player).soulShards, 500 - cost)

		-- Buy to the cap and confirm it stops.
		for _ = 1, vitality.maxLevel do
			ProgressionService.purchase(player, "Vitality")
		end
		spec:equals(
			"levels cap at the maximum",
			ProgressionService.levelOf(player, "Vitality"),
			vitality.maxLevel
		)
		spec:truthy("the upgrade reports maxed", ProgressionService.isMaxed(player, "Vitality"))
		local _, maxedReason = ProgressionService.purchase(player, "Vitality")
		spec:equals("buying past the cap is refused", maxedReason, "maxed")

		-- ------------------------------------------- C. upgrades change play

		-- Vitality scales the BASE, and run equipment adds on top of that. The order
		-- matters: Vitality should make Iron Heart better in absolute terms, not
		-- multiply it too.
		InventoryService.refreshMaxHealth(player)
		local upgradedMax = (PlayerService.get(player) :: any).maxHealth
		local expectedBase = CombatConfig.player.maxHealth
			* ProgressionService.maxHealthMultiplier(player)
		spec:check(
			"Vitality raised max health",
			upgradedMax > CombatConfig.player.maxHealth,
			`{CombatConfig.player.maxHealth} -> {upgradedMax}`
		)
		spec:check(
			"max health matches the multiplier",
			math.abs(upgradedMax - expectedBase) < 0.01,
			`{upgradedMax} vs {expectedBase}`
		)

		InventoryService.grant(player, "IronHeart")
		spec:check(
			"equipment adds on top of the upgraded base",
			math.abs((PlayerService.get(player) :: any).maxHealth - (expectedBase + 25)) < 0.01,
			(PlayerService.get(player) :: any).maxHealth
		)
		InventoryService.clearRun()
		InventoryService.refreshMaxHealth(player)

		data.soulShards = 500
		ProgressionService.purchase(player, "Power")
		spec:check(
			"Power raises the damage multiplier",
			ProgressionService.damageMultiplier(player) > 1,
			ProgressionService.damageMultiplier(player)
		)

		ProgressionService.purchase(player, "Fortune")
		local goldMultiplier = ProgressionService.goldMultiplier(player)
		spec:check("Fortune raises the gold multiplier", goldMultiplier > 1, goldMultiplier)

		-- Fortune has to apply where gold actually enters a run.
		RunSessionService.begin(SEED)
		local before = (RunSessionService.get() :: any).gold
		local awarded = RunSessionService.addGold(100)
		spec:check("Fortune scales gold as it is awarded", awarded > 100, `100 -> {awarded}`)
		spec:equals(
			"the scaled amount is what landed",
			(RunSessionService.get() :: any).gold,
			before + awarded
		)
		FloorService.endRun()

		-- ------------------------------------------- D. the Heirloom relic

		data.soulShards = 500
		spec:equals(
			"no starting relics by default",
			ProgressionService.startingRelicCount(player),
			0
		)
		ProgressionService.purchase(player, "Heirloom")
		spec:equals(
			"Heirloom grants a starting relic",
			ProgressionService.startingRelicCount(player),
			1
		)

		InventoryService.clearRun()
		FloorService.beginRun(SEED)
		task.wait(0.3)
		spec:equals("a run now begins holding a relic", #InventoryService.items(player), 1)
		local granted = InventoryService.items(player)[1]
		spec:truthy("the starting item is a relic", LootConfig.items[granted].category == "Relic")

		-- Seeded: the same seed must open with the same relic.
		local firstRelic = granted
		FloorService.endRun()
		InventoryService.clearRun()
		FloorService.beginRun(SEED)
		task.wait(0.3)
		spec:equals(
			"the same seed grants the same relic",
			InventoryService.items(player)[1],
			firstRelic
		)

		-- ------------------------------- E. death clears run, keeps meta

		InventoryService.grant(player, "IronPlate")
		local heldBeforeDeath = #InventoryService.items(player)
		local shardsBeforeDeath = SaveService.load(player).soulShards
		local levelsBeforeDeath = ProgressionService.levelOf(player, "Power")
		spec:check("the run has equipment before dying", heldBeforeDeath > 0, heldBeforeDeath)

		PlayerService.setHealth(player, 1)
		PlayerService.handleDeath(player, PlayerService.generation(player))
		task.wait(0.4)

		spec:truthy("dying ended the run", not FloorService.isRunActive())
		spec:equals("dying cleared the run's equipment", #InventoryService.items(player), 0)
		spec:equals(
			"dying restored the default weapon",
			InventoryService.equippedWeapon(player).archetype,
			CombatConfig.defaultWeapon
		)
		spec:equals(
			"dying kept the permanent levels",
			ProgressionService.levelOf(player, "Power"),
			levelsBeforeDeath
		)
		spec:check(
			"dying kept or grew the Soul Shards",
			SaveService.load(player).soulShards >= shardsBeforeDeath,
			`{shardsBeforeDeath} -> {SaveService.load(player).soulShards}`
		)

		-- ------------------------------------- F. the upgrade persists

		-- The other half of the loop: what you bought is live on the next run.
		local deadline = os.clock() + 8
		while os.clock() < deadline and not PlayerService.isActionable(player) do
			task.wait(0.2)
		end

		FloorService.beginRun(SEED)
		task.wait(0.3)
		spec:check(
			"the new run is still upgraded",
			ProgressionService.damageMultiplier(player) > 1,
			ProgressionService.damageMultiplier(player)
		)
		spec:check(
			"the new run still has the raised health ceiling",
			(PlayerService.get(player) :: any).maxHealth > CombatConfig.player.maxHealth,
			(PlayerService.get(player) :: any).maxHealth
		)
		FloorService.endRun()

		-- --------------------------------------------- G. the shrines

		spec:equals(
			"a shrine exists for every upgrade",
			ProgressionService.shrineCount(),
			#UpgradeConfig.pool
		)
		local static = workspace:FindFirstChild("Static")
		local folder = static and static:FindFirstChild("Shrines")
		spec:truthy("the shrines are in the lobby", folder)
		if folder ~= nil then
			spec:equals("every shrine was built", #folder:GetChildren(), #UpgradeConfig.pool)
		end
	end)

	if not ok then
		spec:check("progression checks completed without error", false, err)
	end

	-- ---------------------------------------------------------- H. teardown

	FloorService.endRun()
	InventoryService.clearRun()
	InventoryService.clearPickups()

	-- Put the real save back: a spec must not spend the tester's shards.
	local restore = SaveService.load(player)
	restore.soulShards = savedShards
	table.clear(restore.permanentUpgrades)
	for id, level in savedUpgrades do
		restore.permanentUpgrades[id] = level
	end
	SaveService.save(player)
	InventoryService.refreshMaxHealth(player)
	ProgressionService.refreshShrines()

	PlayerService.setHealth(player, (PlayerService.get(player) :: any).maxHealth)
	PlayerService.setStamina(player, CombatConfig.stamina.max)

	spec:equals(
		"teardown restored the saved shards",
		SaveService.load(player).soulShards,
		savedShards
	)
	spec:equals("teardown emptied the run inventory", #InventoryService.items(player), 0)
	spec:equals("teardown left Generated empty", #FloorService.generatedFolder():GetChildren(), 0)

	return spec:finish()
end
