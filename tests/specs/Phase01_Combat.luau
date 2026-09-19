--!strict
-- Phase 1 acceptance. Runs server-side with a real Player present but no input and no
-- client cooperation, so it drives combat by calling tryAttack / tryDodge /
-- applyDamageToPlayer directly — the same functions the remote handlers call. Nothing
-- here fires a remote.
--
-- Budget: ~7s of real waits. That is not a hang.
--
-- Untestable here and therefore on the manual checklist in docs/PROGRESS.md: feel,
-- pose smoothness, sound, hitstop, HUD layout, and the ContextActionService bindings
-- (which live in the client datamodel).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Spec = require(script.Parent.Spec)

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local CombatService = require(ServerScriptService.Services.CombatService)
local PlayerService = require(ServerScriptService.Services.PlayerService)
local TrainingDummyService = require(ServerScriptService.Services.TrainingDummyService)

local SWORD = CombatConfig.weapons.Sword
local DODGE = CombatConfig.dodge

local function approx(a: number, b: number, tolerance: number): boolean
	return math.abs(a - b) <= tolerance
end

return function()
	local spec = Spec.new("Phase01_Combat")

	-- ---------------------------------------------------------- A. config

	spec:truthy("player config present", CombatConfig.player ~= nil)
	spec:truthy("stamina config present", CombatConfig.stamina ~= nil)
	spec:truthy("sword config present", SWORD ~= nil)
	spec:check(
		"all sword durations positive",
		SWORD.windup > 0 and SWORD.active > 0 and SWORD.recovery > 0
	)
	spec:check("sword deals damage", SWORD.damage > 0, SWORD.damage)

	-- The relations below encode design intent. Asserting them rather than the
	-- literals means retuning feel cannot silently break the design.
	local reach = SWORD.arcForwardOffset + SWORD.arcSize.Z / 2
	local dodgeDistance = DODGE.speed * DODGE.duration
	spec:check(
		"dodge distance exceeds sword reach",
		dodgeDistance > reach,
		`dodge {dodgeDistance}, reach {reach}`
	)
	spec:check(
		"i-frames outlast the dodge itself",
		DODGE.iframes >= DODGE.duration,
		`{DODGE.iframes} vs {DODGE.duration}`
	)
	spec:check("dodge cooldown exceeds its duration", DODGE.cooldown > DODGE.duration)
	spec:check(
		"at least 3 dodges from a full bar",
		CombatConfig.stamina.max // DODGE.staminaCost >= 3
	)
	spec:check(
		"recovery exceeds active, so a whiff costs something",
		SWORD.recovery > SWORD.active,
		`{SWORD.recovery} vs {SWORD.active}`
	)
	spec:check(
		"recovery under dodge cooldown, so no infinite attack-cancel-dodge",
		SWORD.recovery < DODGE.cooldown
	)

	-- -------------------------------------------------------- B. arc math

	local origin = CFrame.new(0, 0, 0)
	spec:check(
		"3 studs ahead is in arc",
		CombatService.isInArc(origin, Vector3.new(0, 0, -3), "Sword")
	)
	spec:check(
		"9 studs ahead is out of reach",
		not CombatService.isInArc(origin, Vector3.new(0, 0, -9), "Sword")
	)
	spec:check(
		"3 studs behind is out of arc",
		not CombatService.isInArc(origin, Vector3.new(0, 0, 3), "Sword")
	)
	-- This is the check that catches someone deleting the dot-product filter and
	-- silently shipping a raw box.
	local offAxis = Vector3.new(math.sin(math.rad(80)) * 3, 0, -math.cos(math.rad(80)) * 3)
	spec:check(
		"80 degrees off-axis is out of arc",
		not CombatService.isInArc(origin, offAxis, "Sword")
	)
	spec:check(
		"vertical extent is covered",
		CombatService.isInArc(origin, Vector3.new(0, 2, -2), "Sword")
	)

	local pitched = CFrame.Angles(math.rad(30), 0, 0)
	local volumeCFrame = CombatService.swingVolume(pitched, "Sword")
	spec:check(
		"swing volume is yaw-only under a pitched root",
		approx(volumeCFrame.LookVector.Y, 0, 1e-3),
		volumeCFrame.LookVector.Y
	)

	-- ----------------------------------------------------- C. world state

	local static = workspace:FindFirstChild("Static")
	spec:truthy("Workspace/Static exists", static)

	local dummy = TrainingDummyService.model()
	spec:truthy("training dummy built", dummy)
	if dummy ~= nil then
		spec:truthy("dummy has a PrimaryPart", dummy.PrimaryPart)
		spec:truthy("dummy has a Body", dummy:FindFirstChild("Body"))
		spec:truthy("dummy is parented under Static", dummy.Parent == static)
	end

	local generated = workspace:FindFirstChild("Generated")
	spec:truthy("Workspace/Generated exists", generated)
	if generated ~= nil then
		-- Regression on the Static-vs-Generated decision: the dummy must not have
		-- landed in the folder FloorService clears every run.
		spec:equals("Generated is still empty", #generated:GetChildren(), 0)
	end

	if dummy ~= nil then
		local body = dummy:FindFirstChild("Body")
		if body ~= nil then
			local resolved = CombatService.damageableFor(body)
			spec:truthy("part resolves to its damageable model", resolved)
			if resolved ~= nil then
				spec:equals("resolved damageable is the dummy", resolved.model, dummy)
			end
		end
	end

	-- ------------------------------------------------- D. dummy damage

	TrainingDummyService.reset()
	local dummyEntry = if dummy ~= nil then CombatService.damageableFor(dummy) else nil

	if dummyEntry ~= nil then
		local dealt = dummyEntry.applyDamage(SWORD.damage, {})
		spec:equals("dummy takes exact sword damage", dealt, SWORD.damage)
		local remaining = TrainingDummyService.getHealth()
		spec:equals(
			"dummy health decreased correctly",
			remaining,
			CombatConfig.trainingDummy.maxHealth - SWORD.damage
		)

		dummyEntry.applyDamage(CombatConfig.trainingDummy.maxHealth * 2, {})
		local afterOverkill = TrainingDummyService.getHealth()
		spec:equals("overkill clamps at zero, never negative", afterOverkill, 0)
		spec:truthy("dummy reports knocked out", TrainingDummyService.isKnockedOut())

		local _, reason = dummyEntry.applyDamage(SWORD.damage, {})
		spec:equals("a knocked-out dummy rejects further damage", reason, "dead")

		TrainingDummyService.reset()
		spec:equals(
			"manual reset restores full health",
			TrainingDummyService.getHealth(),
			CombatConfig.trainingDummy.maxHealth
		)
		TrainingDummyService.reset()
		spec:equals(
			"a second reset is a no-op",
			TrainingDummyService.getHealth(),
			CombatConfig.trainingDummy.maxHealth
		)

		-- The only check that catches a broken generation guard on the reset timer.
		dummyEntry.applyDamage(CombatConfig.trainingDummy.maxHealth, {})
		task.wait(CombatConfig.trainingDummy.resetDelay + 0.4)
		spec:equals(
			"auto-reset fires after resetDelay",
			TrainingDummyService.getHealth(),
			CombatConfig.trainingDummy.maxHealth
		)
	else
		spec:check("dummy damageable registered", false, "not found in registry")
	end

	-- ------------------------------------------- player-driven checks

	local player = Players:GetPlayers()[1]
	if player == nil then
		-- One honest failure instead of 25 cascading ones.
		spec:check(
			"a player is present to drive combat",
			false,
			"run the suite in Play mode, not Run mode"
		)
		return spec:finish()
	end

	if not PlayerService.isActionable(player) then
		spec:check("player character is ready", false, "no live character to drive")
		return spec:finish()
	end

	local originalRespawn = CombatConfig.player.respawnDelay

	local ok, err = pcall(function()
		-- ------------------------------------------ E. stamina gating

		PlayerService.setStamina(player, CombatConfig.stamina.max)
		task.wait(DODGE.cooldown + 0.1)

		local dodged, dodgeReason = CombatService.tryDodge(player)
		spec:check("dodge from full stamina succeeds", dodged, dodgeReason)

		local afterState = PlayerService.get(player)
		if afterState ~= nil then
			spec:equals(
				"dodge deducts exactly its cost",
				afterState.stamina,
				CombatConfig.stamina.max - DODGE.staminaCost
			)
		end

		-- The rate limit is checked before the cooldown, so a back-to-back request is
		-- throttled rather than cooled down. Both are real gates; assert each.
		local spammed, spamReason = CombatService.tryDodge(player)
		spec:check("back-to-back dodge request is rejected", not spammed)
		spec:equals("spam rejection reason is throttled", spamReason, "throttled")

		task.wait(CombatConfig.limits.minRequestInterval + 0.03)
		local again, againReason = CombatService.tryDodge(player)
		spec:check("second dodge inside the cooldown is rejected", not again, againReason)
		spec:equals("rejection reason is cooldown", againReason, "cooldown")

		task.wait(DODGE.cooldown + 0.1)
		PlayerService.setStamina(player, CombatConfig.stamina.max)
		local third = CombatService.tryDodge(player)
		spec:check("dodge succeeds again after the cooldown", third)

		-- Proves spendStamina is atomic: a rejected spend must not partially drain.
		task.wait(DODGE.cooldown + 0.1)
		PlayerService.setStamina(player, DODGE.staminaCost - 1)
		local starved, starvedReason = CombatService.tryDodge(player)
		spec:check("dodge below cost is rejected", not starved)
		spec:equals("rejection reason is stamina", starvedReason, "stamina")
		local starvedState = PlayerService.get(player)
		if starvedState ~= nil then
			spec:equals(
				"a rejected dodge leaves stamina untouched",
				starvedState.stamina,
				DODGE.staminaCost - 1
			)
		end

		-- Let the post-spend regen delay lapse BEFORE zeroing, so the measurement
		-- window is a clean second of active regen rather than a second plus however
		-- much of the delay had already elapsed.
		task.wait(CombatConfig.stamina.regenDelay + 0.1)
		PlayerService.setStamina(player, 0)
		task.wait(1.0)
		local regenState = PlayerService.get(player)
		if regenState ~= nil then
			local expected = CombatConfig.stamina.regenPerSecond * 1.0
			spec:check(
				"stamina regenerates at roughly the configured rate",
				approx(regenState.stamina, expected, expected * 0.15),
				`got {regenState.stamina}, want ~{expected}`
			)
		end

		-- ---------------------------------------------- F. i-frames

		PlayerService.setStamina(player, CombatConfig.stamina.max)
		PlayerService.setHealth(player, CombatConfig.player.maxHealth)
		task.wait(DODGE.cooldown + 0.1)

		local iframeDodge = CombatService.tryDodge(player)
		spec:check("dodge for the i-frame window", iframeDodge)

		local blocked, blockedReason = CombatService.applyDamageToPlayer(player, SWORD.damage, {})
		spec:equals("damage during i-frames deals nothing", blocked, 0)
		spec:equals("rejection reason is iframes", blockedReason, "iframes")
		local iframeState = PlayerService.get(player)
		if iframeState ~= nil then
			spec:equals(
				"health unchanged during i-frames",
				iframeState.health,
				CombatConfig.player.maxHealth
			)
		end

		task.wait(DODGE.iframes + 0.1)
		local landed = CombatService.applyDamageToPlayer(player, SWORD.damage, {})
		spec:equals("damage lands once i-frames expire", landed, SWORD.damage)

		-- ------------------------------------- G. attack state machine

		PlayerService.setHealth(player, CombatConfig.player.maxHealth)
		PlayerService.setStamina(player, CombatConfig.stamina.max)
		task.wait(SWORD.recovery + 0.1)

		local swung, swingReason = CombatService.tryAttack(player)
		spec:check("attack starts", swung, swingReason)
		spec:equals("attack enters Windup", CombatService.phaseOf(player), "Windup")

		task.wait(SWORD.windup + 0.05)
		spec:equals("attack advances to Active", CombatService.phaseOf(player), "Active")

		local double, doubleReason = CombatService.tryAttack(player)
		spec:check("attacking during Active is rejected", not double)
		spec:equals("double-attack reason is busy", doubleReason, "busy")

		local cancelActive, cancelReason = CombatService.tryDodge(player)
		spec:check("dodging during Active is rejected", not cancelActive)
		spec:equals("active-cancel reason is busy", cancelReason, "busy")

		task.wait(SWORD.active + SWORD.recovery + 0.1)
		spec:equals("attack returns to Idle", CombatService.phaseOf(player), "Idle")

		local again2 = CombatService.tryAttack(player)
		spec:check("attack is available again after recovery", again2)

		-- Windup IS cancellable, unlike Active.
		task.wait(DODGE.cooldown + 0.1)
		PlayerService.setStamina(player, CombatConfig.stamina.max)
		task.wait(SWORD.windup + SWORD.active + SWORD.recovery + 0.1)
		CombatService.tryAttack(player)
		local cancelled = CombatService.tryDodge(player)
		spec:check("dodge cancels Windup", cancelled)
		spec:equals("cancelled swing returns to Idle", CombatService.phaseOf(player), "Idle")

		-- ------------------------------------- H. death and respawn

		CombatConfig.player.respawnDelay = 0.4

		-- The dodge that cancelled the Windup above left i-frames running, and they
		-- would absorb the lethal hit. Wait them out first.
		task.wait(DODGE.iframes + 0.1)

		local beforeGeneration = PlayerService.generation(player)
		PlayerService.setHealth(player, 5)
		local killed = CombatService.applyDamageToPlayer(player, SWORD.damage, {})
		spec:check("lethal damage is capped at remaining health", killed <= 5, killed)

		local deadState = PlayerService.get(player)
		if deadState ~= nil then
			spec:equals("health floors at zero", deadState.health, 0)
			spec:equals("player is no longer alive", deadState.alive, false)
			spec:equals("death was handled", deadState.deathHandled, true)
		end

		local _, deadReason = CombatService.applyDamageToPlayer(player, SWORD.damage, {})
		spec:equals("damage to a dead player is rejected", deadReason, "dead")

		task.wait(0.4 + 1.6)
		spec:check(
			"generation advanced through the respawn",
			PlayerService.generation(player) > beforeGeneration,
			`{beforeGeneration} -> {PlayerService.generation(player)}`
		)

		local revived = PlayerService.get(player)
		if revived ~= nil then
			spec:equals("player is alive again", revived.alive, true)
			spec:equals("health restored on respawn", revived.health, CombatConfig.player.maxHealth)
			spec:equals("stamina restored on respawn", revived.stamina, CombatConfig.stamina.max)
			spec:truthy("a new character exists", revived.character)
			if revived.character ~= nil then
				spec:truthy("new character is parented", revived.character.Parent ~= nil)
			end
		end

		spec:equals("combat phase reset after respawn", CombatService.phaseOf(player), "Idle")

		task.wait(SWORD.recovery + 0.1)
		local postRespawn, postReason = CombatService.tryAttack(player)
		spec:check("attack works on the new character", postRespawn, postReason)

		-- ------------------------------- J. end-to-end swing in the world

		-- The arc checks above are pure math. This one puts a real target in a real
		-- swing and is the only thing that catches multi-frame dedupe breaking: the
		-- active window spans ~7 frames and the dummy contributes two parts, so a
		-- naive implementation deals damage a dozen times per swing.
		--
		-- The DUMMY is moved to the player, not the other way round: it is anchored
		-- and server-owned, so there is no client to fight over the CFrame.
		local live = PlayerService.get(player)
		local root = if live ~= nil then live.rootPart else nil
		if root ~= nil and dummy ~= nil and dummy.PrimaryPart ~= nil then
			local savedPivot = dummy:GetPivot()

			local look = root.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
			local basePos = Vector3.new(
				root.Position.X,
				CombatConfig.trainingDummy.basePosition.Y,
				root.Position.Z
			) + flat * 4
			dummy:PivotTo(CFrame.new(basePos))

			-- Let any swing still in flight from the section above land and finish
			-- BEFORE resetting, or its damage is counted against this one.
			task.wait(SWORD.windup + SWORD.active + SWORD.recovery + 0.2)
			TrainingDummyService.reset()

			local inRange, inRangeReason = CombatService.tryAttack(player)
			spec:check("attack starts with a target in range", inRange, inRangeReason)

			task.wait(SWORD.windup + SWORD.active + 0.1)
			local dummyHealth = TrainingDummyService.getHealth()
			spec:check(
				"a real swing damaged the real dummy",
				dummyHealth < CombatConfig.trainingDummy.maxHealth,
				dummyHealth
			)
			spec:equals(
				"one swing deals damage exactly once",
				dummyHealth,
				CombatConfig.trainingDummy.maxHealth - SWORD.damage
			)

			task.wait(SWORD.recovery + 0.1)
			dummy:PivotTo(savedPivot)
			TrainingDummyService.reset()
		end
	end)

	if not ok then
		spec:check("player-driven checks completed without error", false, err)
	end

	-- --------------------------------------------------- I. teardown

	-- Never skip: a spec that leaves the tester dead or the dummy knocked out poisons
	-- the human acceptance pass that runs next.
	CombatConfig.player.respawnDelay = originalRespawn
	PlayerService.setHealth(player, CombatConfig.player.maxHealth)
	PlayerService.setStamina(player, CombatConfig.stamina.max)
	TrainingDummyService.reset()

	-- A full swing, not just recovery: the last check above started one.
	task.wait(SWORD.windup + SWORD.active + SWORD.recovery + 0.15)
	spec:equals("teardown leaves combat Idle", CombatService.phaseOf(player), "Idle")
	spec:equals("teardown restores respawnDelay", CombatConfig.player.respawnDelay, originalRespawn)
	spec:equals(
		"teardown resets the dummy",
		TrainingDummyService.getHealth(),
		CombatConfig.trainingDummy.maxHealth
	)

	return spec:finish()
end
