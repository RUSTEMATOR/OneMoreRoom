--!strict
-- Phase 4 acceptance: a run that advances. Clear floor 1, walk out, arrive on floor 2
-- with state carried forward, and the floor number is the server's.
--
-- Like Phase 3, the ROOM is moved onto the player rather than the player into the
-- room: room parts are anchored and server-owned, a character is client-owned.
--
-- This spec teleports the player across the map, so its teardown returns them to
-- spawn. Leaving the tester stranded 2000 studs away would poison the manual pass.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Spec = require(script.Parent.Spec)

local FloorConfig = require(ReplicatedStorage.Shared.FloorConfig)
local RoomConfig = require(ReplicatedStorage.Shared.RoomConfig)
local CombatService = require(ServerScriptService.Services.CombatService)
local EnemyService = require(ServerScriptService.Services.EnemyService)
local FloorService = require(ServerScriptService.Services.FloorService)
local PlayerService = require(ServerScriptService.Services.PlayerService)
local RoomService = require(ServerScriptService.Services.RoomService)
local RunSessionService = require(ServerScriptService.Services.RunSessionService)

local SEED = 4242

local function killEncounter(room: RoomService.Room)
	for _, id in room.enemyIds do
		local enemy = EnemyService.get(id)
		if enemy ~= nil and enemy.phase ~= "Dead" then
			local entry = CombatService.damageableFor(enemy.model)
			if entry ~= nil then
				entry.applyDamage(enemy.maxHealth * 2, {})
			end
		end
	end
end

-- Put a SPECIFIC exit's trigger volume over the player, rather than walking the
-- player into it. With two doors the trigger centres sit at their local X, so a
-- room-centred pivot would land on the middle pier and match neither.
local function moveExitTriggerOnto(room: RoomService.Room, exitIndex: number, position: Vector3)
	local roomSpec = RoomConfig.templates[room.template]
	local edge = roomSpec.interior.Z / 2 + roomSpec.wallThickness
	local back = edge + FloorConfig.layout.exitTriggerDepth / 2
	local offsetX = RoomService.exitOffsetX(room, exitIndex)
	room.model:PivotTo(CFrame.new(position + Vector3.new(-offsetX, -roomSpec.interior.Y / 2, back)))
end

return function()
	local spec = Spec.new("Phase04_Floor")

	-- ---------------------------------------------------------- A. config

	spec:truthy("floor config present", FloorConfig.run ~= nil)
	spec:check("two exits per room", FloorConfig.exitCount == 2, FloorConfig.exitCount)
	spec:check("clearing a floor is worth something", FloorConfig.run.clearBonusGold > 0)
	spec:check("the generation pool is non-empty", #FloorConfig.pool > 0, #FloorConfig.pool)
	spec:check(
		"every pooled id is a real template",
		(function()
			for _, id in FloorConfig.pool do
				if RoomConfig.templates[id] == nil then
					return false
				end
			end
			return true
		end)()
	)

	-- Floors must not overlap, or a stray enemy from the last one can reach the next.
	local combat = RoomConfig.templates.Combat
	spec:check(
		"floor spacing exceeds a room's own depth",
		FloorConfig.layout.floorSpacing > combat.interior.Z + combat.wallThickness * 2,
		`{FloorConfig.layout.floorSpacing} vs {combat.interior.Z}`
	)

	local originOne = FloorService.originForFloor(1)
	local originTwo = FloorService.originForFloor(2)
	spec:check(
		"consecutive floors are spaced apart",
		(originOne.Position - originTwo.Position).Magnitude >= FloorConfig.layout.floorSpacing - 1,
		(originOne.Position - originTwo.Position).Magnitude
	)
	spec:check(
		"floor origins are deterministic",
		FloorService.originForFloor(3).Position == FloorService.originForFloor(3).Position
	)

	-- ------------------------------------------------ player-driven checks

	local player = Players:GetPlayers()[1]
	if player == nil or not PlayerService.isActionable(player) then
		spec:check("a live player is present to walk the run", false, "run in Play mode")
		return spec:finish()
	end

	local playerState = PlayerService.get(player)
	local originalCFrame = if playerState ~= nil and playerState.character ~= nil
		then playerState.character:GetPivot()
		else CFrame.new(0, 5, 0)

	local ok, err = pcall(function()
		local generated = FloorService.generatedFolder()

		-- ------------------------------------------------- B. starting a run

		local roomOne = FloorService.beginRun(SEED)
		spec:truthy("beginRun produced a room", roomOne)
		if roomOne == nil then
			return
		end

		spec:equals("the run starts on floor 1", FloorService.currentFloor(), 1)
		spec:truthy("the run is active", FloorService.isRunActive())
		spec:equals("the run carries its seed", (RunSessionService.get() :: any).seed, SEED)
		spec:truthy("the floor's room is the current room", FloorService.currentRoom() == roomOne)
		spec:truthy("the room was built into Generated", roomOne.model.Parent == generated)

		task.wait(0.3)
		local state = PlayerService.get(player)
		local root = if state ~= nil then state.rootPart else nil
		if root ~= nil then
			local distance = (root.Position - roomOne.model:GetPivot().Position).Magnitude
			spec:check(
				"the player was moved into the new floor",
				distance < 200,
				`{distance} studs from the room`
			)
		end

		-- ---------------------------------------------- C. one floor at a time

		spec:equals("exactly one room exists in Generated", #generated:GetChildren(), 1)

		-- ---------------------------------------- D. clearing opens the exit

		-- The player is standing in it, so the room seals and spawns on its own.
		task.wait(combat.sealDelay + combat.doorTime + 0.5)

		-- Which template floor 1 opens on is seeded now, so this cannot assume an
		-- encounter: a Treasure or Healing start legitimately has nothing to fight
		-- and clears itself the moment it seals.
		local plan = FloorService.currentPlan()
		spec:truthy("the floor carries a plan", plan)
		spec:check(
			"the floor's room sealed around the player",
			roomOne.phase ~= "Open",
			roomOne.phase
		)
		spec:equals(
			"the room offers two exits",
			RoomService.exitCount(roomOne),
			FloorConfig.exitCount
		)
		spec:equals(
			"the world spawned exactly the planned encounter",
			#roomOne.enemyIds,
			if plan ~= nil then #plan.enemies else 0
		)

		killEncounter(roomOne)
		task.wait(combat.clearDelay + combat.doorTime + 0.6)
		spec:equals("the room reports Cleared", roomOne.phase, "Cleared")

		-- ------------------------------------- E. leaving advances the floor

		local goldBefore = (RunSessionService.get() :: any).gold
		local rootNow = (PlayerService.get(player) :: any).rootPart :: BasePart
		moveExitTriggerOnto(roomOne, 1, rootNow.Position)

		task.wait(1.2)
		spec:equals("walking out advances to floor 2", FloorService.currentFloor(), 2)
		spec:check(
			"clearing a floor paid the bonus",
			(RunSessionService.get() :: any).gold >= goldBefore + FloorConfig.run.clearBonusGold,
			`{goldBefore} -> {(RunSessionService.get() :: any).gold}`
		)

		local roomTwo = FloorService.currentRoom()
		spec:truthy("floor 2 has its own room", roomTwo)
		spec:check("floor 2 is a different room", roomTwo ~= roomOne)
		spec:truthy("the floor 1 room was torn down", roomOne.model.Parent == nil)
		spec:equals("still exactly one room in Generated", #generated:GetChildren(), 1)

		-- ------------------------------------------ F. state carried forward

		spec:truthy("the run is still active on floor 2", FloorService.isRunActive())
		spec:equals(
			"the seed is unchanged across floors",
			(RunSessionService.get() :: any).seed,
			SEED
		)
		spec:check(
			"gold carried across the floor boundary",
			(RunSessionService.get() :: any).gold >= goldBefore,
			(RunSessionService.get() :: any).gold
		)

		-- --------------------------------------------- G. advancing directly

		local roomThree = FloorService.advance()
		spec:truthy("advance loads the next floor", roomThree)
		spec:equals("the floor number is now 3", FloorService.currentFloor(), 3)
		spec:equals("advancing did not leave rooms behind", #generated:GetChildren(), 1)

		-- ------------------------------------------------ H. ending the run

		FloorService.endRun()
		spec:truthy("the run is no longer active", not FloorService.isRunActive())
		spec:equals("ending the run cleared Generated", #generated:GetChildren(), 0)
		spec:truthy("no current room after the run", FloorService.currentRoom() == nil)
		spec:equals("gold outside a finished run is not awarded", RunSessionService.addGold(50), 0)
	end)

	if not ok then
		spec:check("floor checks completed without error", false, err)
	end

	-- -------------------------------------------------------- I. teardown

	FloorService.endRun()
	EnemyService.despawnAll()
	PlayerService.setHealth(player, 100)
	PlayerService.setStamina(player, 100)

	-- Put the tester back where they started, or the manual pass begins 2000 studs
	-- from the practice area with no idea why.
	local finalState = PlayerService.get(player)
	if finalState ~= nil and finalState.character ~= nil then
		finalState.character:PivotTo(originalCFrame)
	end
	task.wait(0.3)

	spec:equals("teardown left Generated empty", #FloorService.generatedFolder():GetChildren(), 0)
	spec:truthy("teardown ended the run", not FloorService.isRunActive())

	local back = PlayerService.get(player)
	if back ~= nil and back.rootPart ~= nil then
		local drift = (back.rootPart.Position - originalCFrame.Position).Magnitude
		spec:check("the player was returned to where they started", drift < 60, `{drift} studs`)
	end

	return spec:finish()
end
