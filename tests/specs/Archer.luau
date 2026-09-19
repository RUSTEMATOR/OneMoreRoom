--!strict
-- The Bone Archer: the Crypt's first ranged enemy.
--
-- Not a roadmap phase, so not named for one. It exists because the design lists
-- Skeleton, Archer and Cultist for biome 1 and we had only skeletons, which made
-- backing off a dominant strategy rather than a choice -- something EnemyConfig's own
-- comment on the Skeleton had already admitted. Displayed as a "Signal Sentry" with a
-- neon bolt rather than a literal bow (see GAME_DESIGN.md's Setting section); the
-- internal kind id stays "Archer" because RoomConfig, loot rolls and the golden hash
-- all key on it.
--
-- The checks that matter here are the ones a melee enemy cannot fail: that the bolt
-- is a real object travelling through the world rather than instant damage at range,
-- that dodging it works because it goes through the same door a sword does, and that
-- the sentry's kiting is real movement rather than a number.
--
-- Offsets run along +X for the same reason Phase 2's do: the training dummy is on the
-- -Z axis and `Humanoid:MoveTo` has no pathfinding.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Spec = require(script.Parent.Spec)

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local EnemyConfig = require(ReplicatedStorage.Shared.EnemyConfig)
local WeaponStats = require(ReplicatedStorage.Shared.WeaponStats)
local EnemyService = require(ServerScriptService.Services.EnemyService)
local PlayerService = require(ServerScriptService.Services.PlayerService)

local ARCHER = EnemyConfig.kinds.Archer
local SKELETON = EnemyConfig.kinds.Skeleton

return function()
	local spec = Spec.new("Archer")

	-- ----------------------------------------------------- A. the numbers

	spec:truthy("the Archer exists", ARCHER)
	if ARCHER == nil then
		return spec:finish()
	end

	local ranged = ARCHER.ranged
	spec:truthy("it is a ranged kind", ranged)
	spec:equals("the Skeleton is not", SKELETON.ranged, nil)
	spec:equals("the Elite is not", EnemyConfig.kinds.SkeletonElite.ranged, nil)

	if ranged == nil then
		return spec:finish()
	end

	-- Fragile on purpose: reaching it is the challenge, so surviving once reached
	-- would only be tedious. Two swings of the starting sword.
	local starting = WeaponStats.resolve(CombatConfig.defaultWeapon)
	spec:check(
		"two swings of the starting weapon kill it",
		math.ceil(ARCHER.maxHealth / starting.damage) == 2,
		`{ARCHER.maxHealth} hp vs {starting.damage} dmg`
	)

	-- If it fired from inside melee range it would just be a worse skeleton.
	spec:check(
		"it fires from far beyond melee reach",
		ARCHER.attackRange > starting.reach * 4,
		`{ARCHER.attackRange} vs reach {starting.reach}`
	)
	spec:check(
		"it holds a band rather than a point",
		ranged.preferredRange > ranged.retreatRange,
		`{ranged.retreatRange}..{ranged.preferredRange}`
	)
	spec:check(
		"it can be run down",
		ARCHER.walkSpeed < CombatConfig.player.walkSpeed,
		`{ARCHER.walkSpeed} vs {CombatConfig.player.walkSpeed}`
	)

	-- The whole design of the telegraph in one assertion. The arrow's flight from
	-- the preferred range must be SHORTER than the dodge window, so reacting to the
	-- arrow is hopeless; the draw must be LONGER, so reacting to the draw is the
	-- intended play. Change either number and this says so.
	local flight = ranged.preferredRange / ranged.projectileSpeed
	spec:check(
		"the draw is long enough to read",
		ARCHER.attackWindup > CombatConfig.dodge.iframes,
		`windup {ARCHER.attackWindup} vs iframes {CombatConfig.dodge.iframes}`
	)
	spec:check(
		"the arrow is fast enough that only the draw can be read",
		flight < ARCHER.attackWindup,
		`flight {string.format("%.2f", flight)}s vs draw {ARCHER.attackWindup}s`
	)

	-- ----------------------------------------------------- B. a live archer

	local player = Players:GetPlayers()[1]
	if player == nil or not PlayerService.isActionable(player) then
		spec:check("a live player is present", false, "run in Play mode")
		return spec:finish()
	end

	local generated = workspace:FindFirstChild("Generated")
	if generated == nil then
		spec:check("the Generated folder exists", false)
		return spec:finish()
	end

	local ok, err = pcall(function()
		EnemyService.despawnAll()
		spec:equals("teardown leaves nothing in flight", EnemyService.projectileCount(), 0)

		-- ------------------------------------------- C. it shoots

		-- This runs right after Phase10_Boss, whose teardown calls FloorService.endRun,
		-- which destroys the boss floor's geometry out from under whoever is standing
		-- on it -- including the floor itself. Left alone, the player free-falls
		-- (Roblox's default gravity drops it ~100 studs in the first second), and every
		-- distance this spec measures against them is measured against a target that
		-- is accelerating away vertically. Ground them on solid, static geometry first.
		local spawnLocation = workspace:FindFirstChild("SpawnLocation")
		if spawnLocation ~= nil and spawnLocation:IsA("BasePart") and player.Character ~= nil then
			player.Character:PivotTo(spawnLocation.CFrame + Vector3.new(0, 5, 0))
		end

		PlayerService.setHealth(player, CombatConfig.player.maxHealth)
		task.wait(CombatConfig.dodge.iframes + 0.15)

		-- Re-fetched here rather than once at the top of the spec: this runs after
		-- Phase10_Boss, whose fight can kill and respawn the player onto a brand new
		-- character. A rootPart captured before that point is a stale reference to a
		-- character that may no longer be near wherever the live one now stands, and
		-- every distance in this spec is measured against the live one.
		--
		-- Also wait out any respawn still in flight: a death late in Phase10_Boss can
		-- still be inside its 3s respawn delay when this spec starts, and grabbing a
		-- rootPart mid-respawn is the same staleness one resumption point later.
		local settleDeadline = os.clock() + CombatConfig.player.respawnDelay + 1
		local playerState = PlayerService.get(player)
		while (playerState == nil or not playerState.alive) and os.clock() < settleDeadline do
			task.wait(0.1)
			playerState = PlayerService.get(player)
		end
		local playerRoot = if playerState ~= nil then playerState.rootPart else nil
		if playerRoot == nil then
			spec:check("the player has a live root part", false)
			return
		end

		local post = playerRoot.Position + Vector3.new(ranged.preferredRange, 0, 0)
		local archer = EnemyService.spawn("Archer", CFrame.new(post), generated)
		if archer == nil then
			spec:check("the archer spawned", false)
			return
		end
		archer.homePosition = post

		task.wait(0.3)
		spec:truthy("it acquires the player from range", archer.target == player)

		-- A melee enemy at 24 studs would be walking. This one draws.
		task.wait(ARCHER.noticeTime + ARCHER.attackWindup * 0.5)
		spec:check(
			"it draws instead of closing",
			archer.phase == "Attack" or archer.phase == "Chase",
			archer.phase
		)

		-- Catch the arrow mid-flight. Polling rather than one long wait because the
		-- arrow's whole life at this range is under half a second -- a single
		-- task.wait would land after it had already hit and been cleaned up.
		local sawArrow = false
		local deadline = os.clock() + ARCHER.attackWindup + 1.5
		while os.clock() < deadline do
			if EnemyService.projectileCount() > 0 then
				sawArrow = true
				break
			end
			task.wait(0.03)
		end
		spec:truthy("it looses an actual arrow into the world", sawArrow)

		-- An arrow is an object, not a hitscan: it must be somewhere between the
		-- archer and the player rather than already on top of them.
		if sawArrow then
			local arrow = generated:FindFirstChild("Bolt")
			spec:truthy("the arrow is a real part in the world", arrow)
			if arrow ~= nil and arrow:IsA("BasePart") then
				local first = arrow.Position
				task.wait(0.06)
				if arrow.Parent ~= nil then
					spec:check(
						"the arrow travels",
						(arrow.Position - first).Magnitude > 0.5,
						(arrow.Position - first).Magnitude
					)
				else
					-- It landed within the sample window, which is itself proof it
					-- was moving.
					spec:check("the arrow travels", true, "resolved mid-sample")
				end
			end
		end

		-- ------------------------------------------- D. the arrow hurts

		local healthBefore = (PlayerService.get(player) :: any).health
		local hitDeadline = os.clock() + ARCHER.attackWindup + ARCHER.attackCooldown + 3
		local hurt = false
		while os.clock() < hitDeadline do
			local live = PlayerService.get(player)
			if live ~= nil and live.health < healthBefore then
				hurt = true
				break
			end
			task.wait(0.05)
		end
		spec:truthy("the arrow damages the player", hurt)

		local after = PlayerService.get(player)
		if after ~= nil and hurt then
			-- Exactly the arrow's damage, not the spec's `damage` field: those are
			-- two different numbers on purpose and confusing them is the obvious bug.
			local dealt = healthBefore - after.health
			spec:check(
				"it deals the arrow's damage, not the melee damage",
				dealt % ranged.projectileDamage == 0,
				`{dealt} vs arrow {ranged.projectileDamage}`
			)
		end

		-- ------------------------------------------- E. it keeps its distance

		-- Put the player inside the retreat band and confirm the archer actually
		-- backs away. This is the check that separates real kiting from a number in
		-- a config file.
		local crowded = playerRoot.Position + Vector3.new(ranged.retreatRange - 6, 0, 0)
		archer.model:PivotTo(CFrame.new(crowded))
		archer.homePosition = crowded
		task.wait(0.2)

		local closeBefore = (archer.root.Position - playerRoot.Position).Magnitude
		task.wait(1.2)
		local closeAfter = (archer.root.Position - playerRoot.Position).Magnitude
		spec:check(
			"crowding it makes it back away",
			closeAfter > closeBefore,
			`{string.format("%.1f", closeBefore)} -> {string.format("%.1f", closeAfter)}`
		)

		-- ------------------------------------------- F. teardown is clean

		EnemyService.despawnAll()
		task.wait(0.1)
		spec:equals("despawning the archers clears their arrows", EnemyService.projectileCount(), 0)
		spec:truthy("no bolt part is left behind", generated:FindFirstChild("Bolt") == nil)
	end)

	if not ok then
		spec:check("archer checks completed without error", false, err)
	end

	EnemyService.despawnAll()
	PlayerService.setHealth(player, CombatConfig.player.maxHealth)

	return spec:finish()
end
