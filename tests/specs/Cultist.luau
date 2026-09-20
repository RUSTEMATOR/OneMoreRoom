--!strict
-- The Signal Cultist: the third enemy the design named alongside Skeleton and Archer.
--
-- Not a roadmap phase, so not named for one -- same footing as Archer.luau. The
-- decision this enemy exists to teach is the opposite of the Archer's: Skeleton is a
-- trade, Archer is a threat you close on, Cultist is a threat you back AWAY from. It
-- rushes, arms a fuse on contact range, and detonates for area damage instead of a
-- normal hit. Killing it before the fuse ends denies the explosion outright.
--
-- Offsets run along +X for the same reason every other live enemy spec's do: the
-- training dummy sits on the -Z axis and `Humanoid:MoveTo` has no pathfinding.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Spec = require(script.Parent.Spec)

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local EnemyConfig = require(ReplicatedStorage.Shared.EnemyConfig)
local WeaponStats = require(ReplicatedStorage.Shared.WeaponStats)
local EnemyService = require(ServerScriptService.Services.EnemyService)
local PlayerService = require(ServerScriptService.Services.PlayerService)

local CULTIST = EnemyConfig.kinds.Cultist
local SKELETON = EnemyConfig.kinds.Skeleton
local ARCHER = EnemyConfig.kinds.Archer

return function()
	local spec = Spec.new("Cultist")

	-- ----------------------------------------------------- A. the numbers

	spec:truthy("the Cultist exists", CULTIST)
	if CULTIST == nil then
		return spec:finish()
	end

	local explosive = CULTIST.explosive
	spec:truthy("it is an explosive kind", explosive)
	spec:equals("the Skeleton is not", SKELETON.explosive, nil)
	spec:equals("the Archer is not", ARCHER.explosive, nil)
	spec:equals("it is not also a ranged kind", CULTIST.ranged, nil)

	if explosive == nil then
		return spec:finish()
	end

	spec:check(
		"it can be run down",
		CULTIST.walkSpeed < CombatConfig.player.walkSpeed,
		`{CULTIST.walkSpeed} vs {CombatConfig.player.walkSpeed}`
	)
	spec:check(
		"it closes faster than the Skeleton",
		CULTIST.walkSpeed > SKELETON.walkSpeed,
		`{CULTIST.walkSpeed} vs {SKELETON.walkSpeed}`
	)

	-- The core safety property: the fuse triggers before contact, and the blast
	-- radius reaches past where it triggered. Without both halves this is either a
	-- normal melee hit with extra steps, or unavoidable the instant it reaches you.
	spec:check("the fuse arms before melee contact", CULTIST.attackRange > 0, CULTIST.attackRange)
	spec:check(
		"the blast reaches past the arming distance",
		explosive.radius > CULTIST.attackRange,
		`radius {explosive.radius} vs trigger {CULTIST.attackRange}`
	)

	-- Fragile: reaching it is not the challenge the way it is for the Sentry, so it
	-- does not need to survive a trade the way a Rust Husk does.
	local starting = WeaponStats.resolve(CombatConfig.defaultWeapon)
	spec:check(
		"two swings of the starting weapon kill it",
		math.ceil(CULTIST.maxHealth / starting.damage) <= 2,
		`{CULTIST.maxHealth} hp vs {starting.damage} dmg`
	)

	-- ----------------------------------------------------- B. a live cultist

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

		-- Same hazard Archer's spec found and fixed: whatever ran before this may
		-- have left the player mid-respawn or standing on ground about to vanish.
		-- Ground them on something solid and settled before measuring anything
		-- relative to their position.
		local spawnLocation = workspace:FindFirstChild("SpawnLocation")
		if spawnLocation ~= nil and spawnLocation:IsA("BasePart") and player.Character ~= nil then
			player.Character:PivotTo(spawnLocation.CFrame + Vector3.new(0, 5, 0))
		end
		PlayerService.setHealth(player, CombatConfig.player.maxHealth)
		task.wait(CombatConfig.dodge.iframes + 0.15)

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

		-- ------------------------------------------- C. it rushes and arms

		-- Inside detectRange (unlike Archer's spec, which deliberately starts a
		-- ranged enemy beyond it): the point of this section is watching it close
		-- the distance and arm, not testing detection itself.
		local start = playerRoot.Position + Vector3.new(CULTIST.detectRange - 5, 0, 0)
		local cultist = EnemyService.spawn("Cultist", CFrame.new(start), generated)
		if cultist == nil then
			spec:check("the cultist spawned", false)
			return
		end
		cultist.homePosition = start

		local torso = cultist.model:FindFirstChild("Torso") :: BasePart
		local restingColor = torso.Color

		task.wait(0.3)
		spec:truthy("it notices the player from range", cultist.target == player)

		-- Poll for it closing distance and arming, rather than one fixed wait: exact
		-- timing depends on how far `far` put it relative to detectRange, which
		-- varies with player position.
		local armedAt: number? = nil
		local deadline = os.clock() + 6
		while os.clock() < deadline do
			if cultist.phase == "Attack" then
				armedAt = os.clock()
				break
			end
			task.wait(0.05)
		end
		spec:truthy("it rushes in and arms the fuse", armedAt ~= nil)

		if armedAt ~= nil then
			task.wait(CULTIST.attackWindup * 0.5)
			spec:check(
				"the telegraph changes its colour before it goes off",
				torso.Color ~= restingColor,
				tostring(torso.Color)
			)
		end

		-- ------------------------------------------- D. retreating avoids it

		-- Only meaningful once armed: back off past the blast radius and confirm no
		-- damage lands when the fuse ends anyway.
		if armedAt ~= nil then
			local healthBefore = (PlayerService.get(player) :: any).health
			local safe = cultist.root.Position + Vector3.new(explosive.radius + 6, 0, 0)
			if player.Character ~= nil then
				player.Character:PivotTo(CFrame.new(safe + Vector3.new(0, 3, 0)))
			end

			local fuseDeadline = armedAt + CULTIST.attackWindup + 0.5
			while os.clock() < fuseDeadline do
				task.wait(0.05)
			end
			task.wait(0.2)

			spec:equals("the cultist is gone once the fuse ends", cultist.phase, "Dead")
			local afterRetreat = PlayerService.get(player)
			spec:check(
				"retreating past the blast radius takes no damage",
				afterRetreat ~= nil and afterRetreat.health >= healthBefore,
				afterRetreat and afterRetreat.health
			)
		end

		-- ------------------------------------------- E. the blast actually hurts

		PlayerService.setHealth(player, CombatConfig.player.maxHealth)
		local second = EnemyService.spawn(
			"Cultist",
			CFrame.new(playerRoot.Position + Vector3.new(CULTIST.attackRange - 1, 0, 0)),
			generated
		)
		if second ~= nil then
			second.homePosition = second.root.Position
			second.phase = "Chase"
			second.target = player

			local healthBefore = (PlayerService.get(player) :: any).health
			local hitDeadline = os.clock() + CULTIST.attackWindup + 2
			local hurt = false
			while os.clock() < hitDeadline do
				local live = PlayerService.get(player)
				if live ~= nil and live.health < healthBefore then
					hurt = true
					break
				end
				task.wait(0.05)
			end
			spec:truthy("standing in the blast radius takes damage", hurt)

			local after = PlayerService.get(player)
			if after ~= nil and hurt then
				spec:check(
					"it deals the explosion's damage, not the melee `damage` field",
					(healthBefore - after.health) % explosive.damage == 0,
					healthBefore - after.health
				)
			end
		end

		-- ------------------------------------------- F. killing it early denies it

		PlayerService.setHealth(player, CombatConfig.player.maxHealth)
		local third = EnemyService.spawn(
			"Cultist",
			CFrame.new(playerRoot.Position + Vector3.new(CULTIST.attackRange - 1, 0, 0)),
			generated
		)
		if third ~= nil then
			third.phase = "Chase"
			third.target = player
			task.wait(0.1)

			local healthBefore = (PlayerService.get(player) :: any).health

			-- Kill it directly, through the same door a sword swing would, before the
			-- fuse it may or may not have started can finish.
			local entry =
				require(ServerScriptService.Services.CombatService).damageableFor(third.model)
			if entry ~= nil then
				entry.applyDamage(CULTIST.maxHealth * 2, { source = player })
			end
			task.wait(0.3)

			spec:equals("it dies to direct damage before arming out", third.phase, "Dead")
			local after = PlayerService.get(player)
			spec:equals(
				"killing it early costs the player nothing",
				after ~= nil and after.health,
				healthBefore
			)
		end

		-- ------------------------------------------- G. teardown is clean

		EnemyService.despawnAll()
	end)

	if not ok then
		spec:check("cultist checks completed without error", false, err)
	end

	EnemyService.despawnAll()
	PlayerService.setHealth(player, CombatConfig.player.maxHealth)

	return spec:finish()
end
