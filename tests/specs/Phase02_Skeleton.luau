--!strict
-- Phase 2 acceptance: one enemy, one state machine.
--
-- Runs in the boot context via ServerStorage.OMF_RunSpecs, so it sees the real
-- services. Test enemies are spawned into Workspace/Generated (the real run path) and
-- always torn down, because Phase00_Boot asserts that folder is empty.
--
-- Untestable here: whether the fight is fun. That is the Phase 3 gate.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Spec = require(script.Parent.Spec)

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local EnemyConfig = require(ReplicatedStorage.Shared.EnemyConfig)
local CombatService = require(ServerScriptService.Services.CombatService)
local EnemyService = require(ServerScriptService.Services.EnemyService)
local FloorService = require(ServerScriptService.Services.FloorService)
local PlayerService = require(ServerScriptService.Services.PlayerService)
local RunSessionService = require(ServerScriptService.Services.RunSessionService)

local SKELETON = EnemyConfig.kinds.Skeleton
local SWORD = CombatConfig.weapons.Sword

return function()
	local spec = Spec.new("Phase02_Skeleton")

	-- ---------------------------------------------------------- A. config

	spec:truthy("skeleton config present", SKELETON ~= nil)
	spec:check("skeleton has health", SKELETON.maxHealth > 0, SKELETON.maxHealth)
	spec:check("skeleton deals damage", SKELETON.damage > 0, SKELETON.damage)

	-- Design relations, asserted instead of the literals so retuning cannot silently
	-- break the intent.
	spec:check(
		"skeleton is slower than the player, so backing off works",
		SKELETON.walkSpeed < CombatConfig.player.walkSpeed,
		`{SKELETON.walkSpeed} vs {CombatConfig.player.walkSpeed}`
	)
	spec:check(
		"attack telegraph outlasts the dodge i-frame window, so a read is possible",
		SKELETON.attackWindup > CombatConfig.dodge.iframes,
		`{SKELETON.attackWindup} vs {CombatConfig.dodge.iframes}`
	)
	spec:check(
		"skeleton outranges the player slightly",
		SKELETON.attackRange > SWORD.arcForwardOffset + SWORD.arcSize.Z / 2
	)
	spec:check("detect range is inside the leash", SKELETON.detectRange < SKELETON.leashRange)
	local hitsToKillPlayer = CombatConfig.player.maxHealth / SKELETON.damage
	spec:check(
		"player survives 6-8 skeleton hits",
		hitsToKillPlayer >= 6 and hitsToKillPlayer <= 8,
		hitsToKillPlayer
	)
	local swingsToKill = math.ceil(SKELETON.maxHealth / SWORD.damage)
	spec:check(
		"skeleton dies in 3-5 sword swings",
		swingsToKill >= 3 and swingsToKill <= 5,
		swingsToKill
	)

	-- ------------------------------------------------- B. spawn and rig

	local generated = FloorService.generatedFolder()
	local baseline = EnemyService.count()

	local spawned = EnemyService.spawn("Skeleton", CFrame.new(60, 5, 60), generated)
	spec:truthy("skeleton spawns", spawned)

	if spawned == nil then
		return spec:finish()
	end

	spec:equals("spawn increments the live count", EnemyService.count(), baseline + 1)
	spec:truthy("rig has a Humanoid", spawned.model:FindFirstChildOfClass("Humanoid"))
	spec:truthy("rig has a HumanoidRootPart", spawned.model.PrimaryPart)
	spec:truthy("rig has a Torso", spawned.model:FindFirstChild("Torso"))
	spec:truthy("rig has a Head", spawned.model:FindFirstChild("Head"))
	spec:equals("spawns at full health", spawned.health, SKELETON.maxHealth)
	spec:equals("spawns Idle", spawned.phase, "Idle")
	spec:truthy("spawned into the folder it was given", spawned.model.Parent == generated)

	-- The sword arc must resolve a limb to the enemy model, exactly as it does for
	-- the dummy — that is the whole point of the damageable registry.
	local torso = spawned.model:FindFirstChild("Torso")
	if torso ~= nil then
		local resolved = CombatService.damageableFor(torso)
		spec:truthy("a limb resolves to the enemy damageable", resolved)
		if resolved ~= nil then
			spec:equals("resolved damageable is this skeleton", resolved.model, spawned.model)
		end
	end

	-- ------------------------------------------------------- C. damage

	local entry = CombatService.damageableFor(spawned.model)
	if entry ~= nil then
		local dealt = entry.applyDamage(SWORD.damage, {})
		spec:equals("skeleton takes exact sword damage", dealt, SWORD.damage)
		spec:equals("health decreased", spawned.health, SKELETON.maxHealth - SWORD.damage)
		spec:equals(
			"Humanoid.Health mirrors the authoritative number",
			spawned.humanoid.Health,
			spawned.health
		)
		spec:check("a hit staggers the skeleton", spawned.staggerUntil > os.clock())
	else
		spec:check("skeleton registered as damageable", false, "not in registry")
	end

	-- --------------------------------------------- D. detection and chase

	local player = Players:GetPlayers()[1]
	if player == nil or not PlayerService.isActionable(player) then
		spec:check("a live player is present to be detected", false, "run in Play mode")
		EnemyService.despawnAll()
		return spec:finish()
	end

	local playerState = PlayerService.get(player)
	local playerRoot = if playerState ~= nil then playerState.rootPart else nil

	local ok, err = pcall(function()
		if playerRoot == nil then
			return
		end

		-- Park a fresh skeleton just outside detection range and confirm it ignores
		-- the player, then bring it inside and confirm it notices.
		--
		-- Offsets run along +X, not -Z: the training dummy sits on the -Z axis and
		-- Humanoid:MoveTo has no pathfinding, so a skeleton placed there walks into
		-- the dummy and the chase assertion fails for the wrong reason.
		EnemyService.despawnAll()
		local far = playerRoot.Position + Vector3.new(SKELETON.detectRange + 15, 0, 0)
		local watcher = EnemyService.spawn("Skeleton", CFrame.new(far), generated)
		if watcher == nil then
			spec:check("watcher skeleton spawned", false)
			return
		end

		task.wait(0.3)
		spec:equals("stays Idle beyond detect range", watcher.phase, "Idle")
		spec:truthy("has no target beyond detect range", watcher.target == nil)

		-- Anchor it so Humanoid physics cannot drift it while we assert.
		local near = playerRoot.Position + Vector3.new(SKELETON.detectRange - 8, 0, 0)
		watcher.model:PivotTo(CFrame.new(near))
		watcher.homePosition = near

		task.wait(0.3)
		spec:truthy("acquires the player inside detect range", watcher.target == player)
		spec:check(
			"transitions out of Idle on detection",
			watcher.phase == "Notice" or watcher.phase == "Chase",
			watcher.phase
		)

		task.wait(SKELETON.noticeTime + 0.4)
		spec:check(
			"advances past Notice into the fight",
			watcher.phase ~= "Idle" and watcher.phase ~= "Notice",
			watcher.phase
		)

		-- Closing distance: it should actually move toward the player.
		local before = (watcher.root.Position - playerRoot.Position).Magnitude
		task.wait(1.2)
		local after = (watcher.root.Position - playerRoot.Position).Magnitude
		spec:check("chases toward the player", after < before, `{before} -> {after}`)

		-- --------------------------------------------- E. leash

		local away = playerRoot.Position + Vector3.new(SKELETON.leashRange + 25, 0, 0)
		watcher.model:PivotTo(CFrame.new(away))
		watcher.homePosition = away
		task.wait(0.4)
		spec:truthy("drops its target beyond the leash", watcher.target == nil)
		spec:equals("returns to Idle beyond the leash", watcher.phase, "Idle")

		-- ------------------------------------ F. attack damages the player

		PlayerService.setHealth(player, CombatConfig.player.maxHealth)
		-- Wait out any i-frames so the blow is not silently absorbed.
		task.wait(CombatConfig.dodge.iframes + 0.15)

		local adjacent = playerRoot.Position + Vector3.new(3, 0, 0)
		watcher.model:PivotTo(CFrame.new(adjacent))
		watcher.homePosition = adjacent

		local healthBefore = CombatConfig.player.maxHealth
		task.wait(SKELETON.noticeTime + SKELETON.attackWindup + 1.2)

		local hurtState = PlayerService.get(player)
		if hurtState ~= nil then
			spec:check(
				"an adjacent skeleton damages the player",
				hurtState.health < healthBefore,
				`{healthBefore} -> {hurtState.health}`
			)
			spec:check(
				"damage is a whole number of skeleton hits",
				(healthBefore - hurtState.health) % SKELETON.damage == 0,
				healthBefore - hurtState.health
			)
		end

		-- ------------------------------------- G. death and reward

		RunSessionService.begin(1234)
		local goldBefore = RunSessionService.get()
		local startingGold = if goldBefore ~= nil then goldBefore.gold else 0

		local victim = EnemyService.spawn("Skeleton", CFrame.new(80, 5, 80), generated)
		if victim ~= nil then
			local victimEntry = CombatService.damageableFor(victim.model)
			if victimEntry ~= nil then
				victimEntry.applyDamage(SKELETON.maxHealth * 2, { source = player })
				spec:equals("a killed skeleton reports Dead", victim.phase, "Dead")
				spec:equals("health floors at zero", victim.health, 0)

				local _, deadReason = victimEntry.applyDamage(SWORD.damage, {})
				spec:equals("a dead skeleton rejects further damage", deadReason, "dead")

				local runState = RunSessionService.get()
				if runState ~= nil then
					spec:equals(
						"the kill awarded gold to the active run",
						runState.gold,
						startingGold + SKELETON.goldReward
					)
				end

				-- Despawn is on a timer; confirm it actually fires.
				task.wait(SKELETON.despawnDelay + 0.6)
				spec:truthy("a dead skeleton despawns", victim.model.Parent == nil)
			end
		end

		RunSessionService.finish()
		spec:equals(
			"gold outside an active run is not awarded",
			RunSessionService.addGold(SKELETON.goldReward),
			0
		)

		-- ----------------------- H. practice respawn is not triggered by others

		-- Regression: onKilled fires for EVERY enemy, so a listener that does not
		-- filter on the id respawns the practice skeleton whenever any unrelated
		-- skeleton dies, stacking a second one on top of the live one.
		local static = workspace:FindFirstChild("Static")
		local practiceFolder = static and static:FindFirstChild("Practice")
		if practiceFolder ~= nil then
			local originalDelay = EnemyConfig.practice.respawnDelay
			EnemyConfig.practice.respawnDelay = 0.4

			local practiceCountBefore = #practiceFolder:GetChildren()
			local bystander = EnemyService.spawn("Skeleton", CFrame.new(120, 5, 120), generated)
			if bystander ~= nil then
				local bystanderEntry = CombatService.damageableFor(bystander.model)
				if bystanderEntry ~= nil then
					bystanderEntry.applyDamage(SKELETON.maxHealth * 2, { source = player })
				end
			end
			task.wait(1.0)
			spec:equals(
				"killing an unrelated skeleton does not respawn the practice one",
				#practiceFolder:GetChildren(),
				practiceCountBefore
			)

			EnemyConfig.practice.respawnDelay = originalDelay
		end
	end)

	if not ok then
		spec:check("enemy checks completed without error", false, err)
	end

	-- ------------------------------------------------------ H. teardown

	EnemyService.despawnAll()
	PlayerService.setHealth(player, CombatConfig.player.maxHealth)
	PlayerService.setStamina(player, CombatConfig.stamina.max)

	spec:equals("teardown removed every enemy", EnemyService.count(), 0)
	-- Phase00_Boot asserts this folder is empty; leaving a skeleton behind would fail
	-- a passing regression test on the next run rather than this one.
	spec:equals("teardown left Generated empty", #generated:GetChildren(), 0)

	return spec:finish()
end
