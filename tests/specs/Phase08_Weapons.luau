--!strict
-- Phase 8 acceptance: three archetypes that are genuinely different, and a modifier
-- system where a variant is a data row rather than a new weapon.
--
-- "Each archetype feels distinct" is a human judgement and is on the manual list. What
-- IS testable is that they are distinct in the numbers, and that the distinction is
-- the intended shape: the Greatsword trades commitment for power, the Daggers trade
-- power for safety, and neither is simply better than the Sword.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Spec = require(script.Parent.Spec)

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local FloorConfig = require(ReplicatedStorage.Shared.FloorConfig)
local FloorPlan = require(ReplicatedStorage.Shared.FloorPlan)
local WeaponStats = require(ReplicatedStorage.Shared.WeaponStats)
local CombatService = require(ServerScriptService.Services.CombatService)
local InventoryService = require(ServerScriptService.Services.InventoryService)
local PlayerService = require(ServerScriptService.Services.PlayerService)

local SEED = 880088

return function()
	local spec = Spec.new("Phase08_Weapons")

	-- ---------------------------------------------------- A. the archetypes

	spec:equals("there are three archetypes", #CombatConfig.archetypePool, 3)
	for _, id in CombatConfig.archetypePool do
		spec:truthy(`{id} is a real weapon`, CombatConfig.weapons[id])
		spec:truthy(`{id} resolves`, WeaponStats.isArchetype(id))
	end

	local sword = WeaponStats.resolve("Sword", {})
	local great = WeaponStats.resolve("Greatsword", {})
	local daggers = WeaponStats.resolve("Daggers", {})

	-- The shape the design asks for: balanced / slow and powerful / fast.
	spec:check(
		"the Greatsword hits hardest",
		great.damage > sword.damage and sword.damage > daggers.damage,
		`{daggers.damage} / {sword.damage} / {great.damage}`
	)
	spec:check(
		"the Daggers are fastest",
		daggers.cycle < sword.cycle and sword.cycle < great.cycle,
		`{daggers.cycle} / {sword.cycle} / {great.cycle}`
	)
	spec:check(
		"the Greatsword reaches furthest",
		great.reach > sword.reach and sword.reach > daggers.reach,
		`{daggers.reach} / {sword.reach} / {great.reach}`
	)
	spec:check(
		"the Greatsword sweeps widest",
		great.arcHalfAngleCos < sword.arcHalfAngleCos
			and sword.arcHalfAngleCos < daggers.arcHalfAngleCos
	)

	-- No archetype may simply dominate. If one had both the best sustained damage
	-- and the shortest commitment there would be no choice to make.
	local dpsSword = WeaponStats.damagePerSecond(sword)
	local dpsGreat = WeaponStats.damagePerSecond(great)
	local dpsDaggers = WeaponStats.damagePerSecond(daggers)
	local spread = math.max(dpsSword, dpsGreat, dpsDaggers)
		/ math.min(dpsSword, dpsGreat, dpsDaggers)
	spec:check(
		"sustained damage is within 25% across archetypes",
		spread < 1.25,
		`{dpsDaggers} / {dpsSword} / {dpsGreat}`
	)
	spec:check(
		"the highest-damage weapon is also the most committing",
		great.cycle == math.max(sword.cycle, great.cycle, daggers.cycle)
	)

	-- Dodging out of a swing must work for the LONGEST weapon, not just the Sword.
	local longest = math.max(sword.reach, great.reach, daggers.reach)
	spec:check(
		"a dodge still outruns the longest reach",
		CombatConfig.dodge.speed * CombatConfig.dodge.duration > longest,
		`dodge {CombatConfig.dodge.speed * CombatConfig.dodge.duration} vs reach {longest}`
	)

	-- ----------------------------------------------------- B. the modifiers

	spec:check("there are modifiers to apply", #CombatConfig.modifierPool > 0)
	for _, id in CombatConfig.modifierPool do
		local modifier = CombatConfig.modifiers[id]
		spec:truthy(`{id} exists`, modifier)
		if modifier ~= nil then
			spec:check(`{id} has a prefix`, #modifier.prefix > 0)
			spec:check(
				`{id} actually changes something`,
				modifier.damage ~= nil or modifier.speed ~= nil or modifier.reach ~= nil
			)
		end
	end

	-- The example the design names by hand: "Rusted Dagger, +15% speed, -10% damage".
	local rusted = WeaponStats.resolve("Daggers", { "Rusted" })
	spec:check(
		"Rusted reduces damage by 10%",
		math.abs(rusted.damage - daggers.damage * 0.90) < 1e-6,
		`{daggers.damage} -> {rusted.damage}`
	)
	spec:check(
		"Rusted speeds the whole cycle by 15%",
		math.abs(rusted.cycle - daggers.cycle / 1.15) < 1e-6,
		`{daggers.cycle} -> {rusted.cycle}`
	)
	spec:equals("a modifier names the weapon", rusted.displayName, "Rusted Daggers")

	-- Speed must scale the WHOLE cycle. Scaling only the windup would let a "fast"
	-- weapon keep a slow recovery, which is the opposite of what the word means.
	spec:check("speed scales windup", rusted.windup < daggers.windup)
	spec:check("speed scales active", rusted.active < daggers.active)
	spec:check("speed scales recovery", rusted.recovery < daggers.recovery)

	-- A modifier must behave the same way on every archetype.
	for _, archetype in CombatConfig.archetypePool do
		local plain = WeaponStats.resolve(archetype, {})
		local keen = WeaponStats.resolve(archetype, { "Keen" })
		local reaching = WeaponStats.resolve(archetype, { "Reaching" })
		spec:check(
			`Keen raises {archetype} damage by 12%`,
			math.abs(keen.damage - plain.damage * 1.12) < 1e-6,
			`{plain.damage} -> {keen.damage}`
		)
		spec:check(
			`Reaching extends {archetype} by 1.5 studs`,
			math.abs(reaching.reach - (plain.reach + 1.5)) < 1e-6,
			`{plain.reach} -> {reaching.reach}`
		)
		spec:equals(
			`{archetype} keeps its identity under a modifier`,
			keen.archetype,
			plain.archetype
		)
	end

	-- Stacking, and the naming that follows from it.
	local stacked = WeaponStats.resolve("Greatsword", { "Keen", "Swift" })
	spec:check(
		"stacked modifiers multiply",
		math.abs(stacked.damage - great.damage * 1.12) < 1e-6
			and math.abs(stacked.cycle - great.cycle / 1.20) < 1e-6,
		`{stacked.damage} / {stacked.cycle}`
	)
	spec:equals("stacked names read in order", stacked.displayName, "Keen Swift Greatsword")

	-- Opposed modifiers must cancel rather than compound in one direction.
	local both = WeaponStats.resolve("Sword", { "Rusted", "Heavy" })
	spec:check(
		"Rusted and Heavy partly cancel",
		both.damage > WeaponStats.resolve("Sword", { "Rusted" }).damage
			and both.damage < WeaponStats.resolve("Sword", { "Heavy" }).damage,
		both.damage
	)

	-- Garbage in must not produce garbage out.
	local junk = WeaponStats.resolve("Sword", { "NotAModifier" })
	spec:equals("an unknown modifier is ignored", junk.damage, sword.damage)
	spec:equals("an unknown modifier is not named", junk.displayName, "Sword")
	spec:equals(
		"an unknown archetype falls back to the default",
		WeaponStats.resolve("NotAWeapon", {}).archetype,
		CombatConfig.defaultWeapon
	)

	-- A faster weapon must never resolve to a zero-length phase, or the state
	-- machine would skip straight through Active and never hit anything.
	local absurd = WeaponStats.resolve("Daggers", { "Swift", "Swift", "Swift", "Swift", "Swift" })
	spec:check(
		"phases never collapse to zero",
		absurd.windup > 0 and absurd.active > 0,
		absurd.active
	)

	-- --------------------------------------------------- C. weapon drops

	local sawWeapon = false
	local sawModified = false
	for depth = 1, 8 do
		for _, template in FloorConfig.pool do
			for _, placement in FloorPlan.generate(SEED, depth, template).enemies do
				spec:truthy(
					`a drop declares its kind`,
					placement.dropKind == "item" or placement.dropKind == "weapon"
				)
				if placement.dropKind == "weapon" then
					sawWeapon = true
					spec:truthy(
						`weapon drop {placement.dropItem} is an archetype`,
						WeaponStats.isArchetype(placement.dropItem)
					)
					for _, id in placement.dropModifiers do
						spec:truthy(`modifier {id} is real`, WeaponStats.isModifier(id))
					end
					if #placement.dropModifiers > 0 then
						sawModified = true
					end
					spec:check(
						"a weapon carries at most two modifiers",
						#placement.dropModifiers <= 2,
						#placement.dropModifiers
					)
				else
					spec:equals("item drops carry no modifiers", #placement.dropModifiers, 0)
				end
			end
		end
	end
	spec:truthy("weapons do drop", sawWeapon)
	spec:truthy("some dropped weapons are modified", sawModified)

	-- ------------------------------------------------ player-driven checks

	local player = Players:GetPlayers()[1]
	if player == nil or not PlayerService.isActionable(player) then
		spec:check("a live player is present", false, "run in Play mode")
		return spec:finish()
	end

	local ok, err = pcall(function()
		InventoryService.clearRun()
		InventoryService.clearPickups()

		-- ------------------------------------------------- D. equipping

		spec:equals(
			"a run starts on the default weapon",
			InventoryService.equippedWeapon(player).archetype,
			CombatConfig.defaultWeapon
		)

		spec:truthy(
			"a real archetype equips",
			InventoryService.equipWeapon(player, "Greatsword", { "Keen" })
		)
		spec:equals(
			"the archetype took",
			InventoryService.equippedWeapon(player).archetype,
			"Greatsword"
		)
		spec:equals("the modifier took", #InventoryService.equippedWeapon(player).modifiers, 1)
		spec:check(
			"equipped stats reflect the modifier",
			math.abs(InventoryService.weaponStats(player).damage - great.damage * 1.12) < 1e-6,
			InventoryService.weaponStats(player).damage
		)

		spec:truthy(
			"a fake archetype is refused",
			not InventoryService.equipWeapon(player, "Banana")
		)
		spec:equals(
			"a refused equip leaves the weapon alone",
			InventoryService.equippedWeapon(player).archetype,
			"Greatsword"
		)

		InventoryService.equipWeapon(player, "Daggers", { "Rusted", "NotReal" })
		spec:equals(
			"unknown modifiers are dropped on equip",
			#InventoryService.equippedWeapon(player).modifiers,
			1
		)

		-- The model has to follow the stats, or you are swinging an invisible lie.
		task.wait(0.3)
		local character = (PlayerService.get(player) :: any).character :: Model
		spec:truthy("the weapon model exists", character:FindFirstChild("OMF_Weapon"))

		-- -------------------------------------- E. the swing uses the weapon

		-- A swing snapshots its stats, so the arc and timing belong to the weapon
		-- that started it.
		task.wait(sword.cycle + 0.2)
		local started = CombatService.tryAttack(player)
		spec:check("attacking with the equipped weapon works", started)

		local combatState = CombatService.stateOf(player)
		if combatState ~= nil then
			spec:equals(
				"the swing snapshotted the equipped archetype",
				combatState.swingStats.archetype,
				"Daggers"
			)
			spec:check(
				"the swing uses the modified timing",
				combatState.swingStats.cycle < daggers.cycle,
				combatState.swingStats.cycle
			)
		end

		-- Swapping mid-swing must not retune the swing already in flight.
		InventoryService.equipWeapon(player, "Greatsword", {})
		local midSwing = CombatService.stateOf(player)
		if midSwing ~= nil then
			spec:equals(
				"a mid-swing swap does not change the swing in flight",
				midSwing.swingStats.archetype,
				"Daggers"
			)
		end

		task.wait(great.cycle + 0.3)
		CombatService.tryAttack(player)
		local nextSwing = CombatService.stateOf(player)
		if nextSwing ~= nil then
			spec:equals(
				"the next swing uses the new weapon",
				nextSwing.swingStats.archetype,
				"Greatsword"
			)
		end

		-- ------------------------------------------- F. a weapon pickup

		task.wait(great.cycle + 0.3)
		InventoryService.clearRun()
		local root = (PlayerService.get(player) :: any).rootPart :: BasePart
		InventoryService.spawnPickup(
			"Daggers",
			5,
			CFrame.new(root.Position),
			workspace,
			"weapon",
			{ "Swift" }
		)
		spec:equals("the weapon pickup exists", InventoryService.activePickupCount(), 1)

		task.wait(0.5)
		spec:equals(
			"walking into a weapon equips it",
			InventoryService.equippedWeapon(player).archetype,
			"Daggers"
		)
		spec:equals(
			"the pickup's modifier came with it",
			InventoryService.equippedWeapon(player).modifiers[1],
			"Swift"
		)
		spec:equals("a weapon pickup is not an item", #InventoryService.items(player), 0)
	end)

	if not ok then
		spec:check("weapon checks completed without error", false, err)
	end

	-- ---------------------------------------------------------- G. teardown

	InventoryService.clearRun()
	InventoryService.clearPickups()
	PlayerService.setHealth(player, CombatConfig.player.maxHealth)
	PlayerService.setStamina(player, CombatConfig.stamina.max)

	spec:equals(
		"teardown restored the default weapon",
		InventoryService.equippedWeapon(player).archetype,
		CombatConfig.defaultWeapon
	)
	spec:equals("teardown removed every pickup", InventoryService.activePickupCount(), 0)

	return spec:finish()
end
