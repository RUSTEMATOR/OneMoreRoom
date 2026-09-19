--!strict
-- Phase 6 acceptance: same seed and same path produce the same run.
--
-- Most of this is pure arithmetic — no world, no player, no waiting — which is the
-- payoff of splitting generation (FloorPlan) from realization (RoomService). Only the
-- last section needs a live run.
--
-- The reproducibility guarantee is precisely: **same seed AND same path** gives
-- identical geometry, encounters and rewards. Combat outcomes still differ, because
-- you play differently. A repro therefore needs both halves, which is why
-- RunSessionService records the path.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Spec = require(script.Parent.Spec)

local EnemyConfig = require(ReplicatedStorage.Shared.EnemyConfig)
local FloorConfig = require(ReplicatedStorage.Shared.FloorConfig)
local FloorPlan = require(ReplicatedStorage.Shared.FloorPlan)
local RoomConfig = require(ReplicatedStorage.Shared.RoomConfig)
local FloorService = require(ServerScriptService.Services.FloorService)
local PlayerService = require(ServerScriptService.Services.PlayerService)
local RoomService = require(ServerScriptService.Services.RoomService)
local RunSessionService = require(ServerScriptService.Services.RunSessionService)

local SEED = 839271
local DIGEST_DEPTH = 8

-- The committed golden hash. It lives HERE, next to the assertion, and deliberately
-- not in Shared: a constant sitting beside the generator gets "fixed" alongside the
-- very bug it was supposed to catch.
--
-- When generation is MEANT to change, bump FloorConfig.generationVersion and
-- regenerate this together, in the same commit, with the reason in the message.
local GOLDEN_VERSION = 1
local GOLDEN_FINGERPRINT = "d27e8f08a8252f29"

return function()
	local spec = Spec.new("Phase06_Generation")

	-- ------------------------------------------------------ A. determinism

	local digestA = FloorPlan.digest(SEED, DIGEST_DEPTH)
	local digestB = FloorPlan.digest(SEED, DIGEST_DEPTH)
	spec:equals("the same seed digests identically", digestA, digestB)
	spec:check(
		"a different seed digests differently",
		FloorPlan.digest(SEED + 1, DIGEST_DEPTH) ~= digestA
	)

	for _, template in FloorConfig.pool do
		local one = FloorPlan.generate(SEED, 3, template)
		local two = FloorPlan.generate(SEED, 3, template)
		spec:equals(
			`{template} replays field-identically`,
			FloorPlan.hash(one),
			FloorPlan.hash(two)
		)
		spec:check(
			`{template} differs across depths`,
			FloorPlan.hash(one) ~= FloorPlan.hash(FloorPlan.generate(SEED, 4, template))
		)
	end

	-- ----------------------------------------------------- B. golden hash

	local fingerprint = FloorPlan.fingerprint(SEED, DIGEST_DEPTH)
	spec:equals(
		"generation version matches the committed golden hash",
		FloorConfig.generationVersion,
		GOLDEN_VERSION
	)
	spec:equals(
		"generation matches the committed golden fingerprint",
		fingerprint,
		GOLDEN_FINGERPRINT
	)

	-- -------------------------------------------------- C. hash sensitivity

	-- The hash must move when something a player would notice moves, and stay put
	-- when it would not. Colours and door timings are read by RoomBuilder and are
	-- deliberately outside the hash.
	local plan = FloorPlan.generate(SEED, 2, "Combat")
	local baseline = FloorPlan.hash(plan)

	local shifted = FloorPlan.generate(SEED, 2, "Combat")
	if #shifted.enemies > 0 then
		shifted.enemies[1].offset += Vector3.new(1, 0, 0)
		spec:check("a moved enemy changes the hash", FloorPlan.hash(shifted) ~= baseline)
	end

	local reExited = FloorPlan.generate(SEED, 2, "Combat")
	reExited.exits = { reExited.exits[2], reExited.exits[1] }
	spec:check("exit ORDER is part of the hash", FloorPlan.hash(reExited) ~= baseline)

	-- ----------------------------------------------------- D. the branching

	local distinctSeen = false
	for depth = 1, DIGEST_DEPTH do
		for _, template in FloorConfig.pool do
			local exits = FloorPlan.exitOptions(SEED, depth, template)
			spec:equals(`depth {depth} {template} offers two doors`, #exits, FloorConfig.exitCount)
			spec:check(
				`depth {depth} {template} offers two DIFFERENT rooms`,
				exits[1] ~= exits[2],
				`{exits[1]} / {exits[2]}`
			)
			spec:truthy(
				`depth {depth} {template} option 1 is pooled`,
				table.find(FloorConfig.pool, exits[1])
			)
			spec:truthy(
				`depth {depth} {template} option 2 is pooled`,
				table.find(FloorConfig.pool, exits[2])
			)
		end

		-- Keyed on the current template, so arriving from somewhere else must be
		-- able to offer something else. If this never differs, the branch is
		-- decorative and the choice means nothing.
		local first = FloorPlan.exitOptions(SEED, depth, FloorConfig.pool[1])
		local second = FloorPlan.exitOptions(SEED, depth, FloorConfig.pool[2])
		if first[1] ~= second[1] or first[2] ~= second[2] then
			distinctSeen = true
		end
	end
	spec:truthy("where you came from changes what is offered", distinctSeen)

	-- ------------------------------------------------ E. placement validity

	for depth = 1, 10 do
		for _, template in FloorConfig.pool do
			local roomSpec = RoomConfig.templates[template]
			local generated = FloorPlan.generate(SEED, depth, template)

			local count = #generated.enemies
			spec:check(
				`{template} d{depth} count within template bounds`,
				count >= roomSpec.encounter.minCount and count <= roomSpec.encounter.maxCount,
				count
			)

			local rootWidth = EnemyConfig.kinds[roomSpec.encounter.kind].rig.rootSize.X
			local separation = rootWidth * FloorConfig.encounter.separationFactor
			local limitX = roomSpec.interior.X / 2 - roomSpec.wallThickness
			local limitZ = roomSpec.interior.Z / 2 - roomSpec.wallThickness

			local inBounds = true
			local apart = true
			for i, placement in generated.enemies do
				if
					math.abs(placement.offset.X) > limitX
					or math.abs(placement.offset.Z) > limitZ
				then
					inBounds = false
				end
				for j, other in generated.enemies do
					if
						i ~= j
						and (placement.offset - other.offset).Magnitude < separation - 0.01
					then
						apart = false
					end
				end
			end
			spec:check(`{template} d{depth} enemies are inside the walls`, inBounds)
			spec:check(`{template} d{depth} enemies do not overlap`, apart)
		end
	end

	-- Depth must actually matter, or the climb has no shape.
	spec:check(
		"encounters grow with depth",
		#FloorPlan.generate(SEED, 10, "Combat").enemies
			> #FloorPlan.generate(SEED, 1, "Combat").enemies,
		`{#FloorPlan.generate(SEED, 1, "Combat").enemies} -> {#FloorPlan.generate(
			SEED,
			10,
			"Combat"
		).enemies}`
	)

	-- -------------------------------------------------------- F. rewards

	for _, template in FloorConfig.pool do
		local roomSpec = RoomConfig.templates[template]
		local generated = FloorPlan.generate(SEED, 1, template)
		if roomSpec.reward == nil then
			spec:truthy(`{template} has no reward in its plan`, generated.reward == nil)
		else
			local reward = generated.reward
			spec:truthy(`{template} rolled a reward`, reward)
			if reward ~= nil then
				spec:equals(
					`{template} reward kind is fixed by the template`,
					reward.kind,
					roomSpec.reward.kind
				)
				spec:check(
					`{template} reward amount is inside its range`,
					reward.amount >= roomSpec.reward.minAmount - 0.5
						and reward.amount <= roomSpec.reward.maxAmount + 0.5,
					reward.amount
				)
			end
		end
	end

	-- ------------------------------------------------------- G. a live run

	local player = Players:GetPlayers()[1]
	if player == nil or not PlayerService.isActionable(player) then
		spec:check("a live player is present", false, "run in Play mode")
		return spec:finish()
	end

	local startCFrame = (PlayerService.get(player) :: any).character:GetPivot()

	local ok, err = pcall(function()
		local room = FloorService.beginRun(SEED)
		spec:truthy("a seeded run begins", room)
		if room == nil then
			return
		end

		local runState = RunSessionService.get() :: any
		spec:equals("the run carries the seed it was given", runState.seed, SEED)
		spec:equals("the path starts empty", #runState.path, 0)

		local livePlan = FloorService.currentPlan()
		spec:truthy("the floor carries a plan", livePlan)
		if livePlan ~= nil then
			spec:equals("the room matches the plan's template", room.template, livePlan.template)
			spec:equals(
				"floor 1 opens on the seeded starting template",
				livePlan.template,
				FloorPlan.startingTemplate(SEED)
			)
			spec:equals(
				"the room built one door per planned exit",
				#room.exitDoors,
				#livePlan.exits
			)
		end

		spec:equals("the room offers two exits", RoomService.exitCount(room), FloorConfig.exitCount)
		for index, door in room.exitDoors do
			spec:check(`exit {index} starts closed`, not RoomService.isDoorOpen(room, door))
		end

		-- Seeded placement has to survive the trip into the world, not just the
		-- plan: this is the check that catches realization dropping enemies.
		local combat = RoomConfig.templates[room.template]
		task.wait(combat.sealDelay + combat.doorTime + 0.6)
		if livePlan ~= nil then
			spec:equals(
				"the world spawned exactly the planned encounter",
				#room.enemyIds,
				#livePlan.enemies
			)
		end

		-- A second run on the same seed must lay out identically.
		local firstTemplate = room.template
		local firstEnemyCount = #room.enemyIds
		FloorService.endRun()
		task.wait(0.2)

		local replay = FloorService.beginRun(SEED)
		spec:truthy("the same seed replays", replay)
		if replay ~= nil then
			spec:equals("replay opens on the same template", replay.template, firstTemplate)
			task.wait(combat.sealDelay + combat.doorTime + 0.6)
			spec:equals("replay spawns the same encounter size", #replay.enemyIds, firstEnemyCount)
		end

		spec:check(
			"describe() carries seed and path",
			string.find(RunSessionService.describe(), "seed:") ~= nil,
			RunSessionService.describe()
		)

		-- Death ends the run rather than stranding the player on a floor they can
		-- never return to.
		PlayerService.setHealth(player, 1)
		PlayerService.handleDeath(player, PlayerService.generation(player))
		task.wait(0.3)
		spec:truthy("dying ends the run", not FloorService.isRunActive())
	end)

	if not ok then
		spec:check("generation checks completed without error", false, err)
	end

	-- --------------------------------------------------------- H. teardown

	FloorService.endRun()

	-- The death check above triggered a respawn; wait for the new character before
	-- putting the tester back, or we teleport a corpse and they reappear elsewhere.
	local deadline = os.clock() + 8
	while os.clock() < deadline and not PlayerService.isActionable(player) do
		task.wait(0.2)
	end

	PlayerService.setHealth(player, 100)
	PlayerService.setStamina(player, 100)

	local finalState = PlayerService.get(player)
	if finalState ~= nil and finalState.character ~= nil then
		finalState.character:PivotTo(startCFrame)
	end
	task.wait(0.3)

	spec:equals("teardown left Generated empty", #FloorService.generatedFolder():GetChildren(), 0)
	spec:truthy("teardown ended the run", not FloorService.isRunActive())

	return spec:finish()
end
