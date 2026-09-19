--!strict
-- Phase 3 acceptance: the vertical slice. Enter -> seal -> fight -> clear -> exit.
--
-- The test room is built AROUND the player rather than teleporting the player into a
-- room. Room parts are anchored and server-owned, so moving them is reliable; a
-- player's character is client-owned and a server-set CFrame can be fought.
--
-- Untestable here: whether the slice is fun. That is the Phase 3 gate, and it is
-- yours to call.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Spec = require(script.Parent.Spec)

local RoomConfig = require(ReplicatedStorage.Shared.RoomConfig)
local CombatService = require(ServerScriptService.Services.CombatService)
local EnemyService = require(ServerScriptService.Services.EnemyService)
local FloorService = require(ServerScriptService.Services.FloorService)
local PlayerService = require(ServerScriptService.Services.PlayerService)
local RoomService = require(ServerScriptService.Services.RoomService)

local TEMPLATE = "Combat"
local COMBAT = RoomConfig.templates.Combat

local function killEveryEnemyIn(room: RoomService.Room)
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

return function()
	local spec = Spec.new("Phase03_Room")

	-- ---------------------------------------------------------- A. config

	spec:truthy("combat template present", COMBAT ~= nil)
	spec:check("interior has volume", COMBAT.interior.X > 0 and COMBAT.interior.Z > 0)
	spec:check("the encounter has enemies", #COMBAT.enemySpawns > 0, #COMBAT.enemySpawns)
	-- An open door has to actually clear the doorway, or the player is sealed in a
	-- room the state machine believes is open.
	spec:check(
		"door travel fully clears the doorway",
		COMBAT.doorTravel >= COMBAT.doorway.height,
		`travel {COMBAT.doorTravel} vs height {COMBAT.doorway.height}`
	)
	spec:check(
		"every enemy spawn sits inside the interior",
		(function()
			for _, offset in COMBAT.enemySpawns do
				if
					math.abs(offset.X) >= COMBAT.interior.X / 2
					or math.abs(offset.Z) >= COMBAT.interior.Z / 2
				then
					return false
				end
			end
			return true
		end)()
	)

	-- ----------------------------------------------------- B. practice room

	local static = workspace:FindFirstChild("Static")
	local practiceHolder = static and static:FindFirstChild("PracticeRoom")
	spec:truthy("practice room folder exists", practiceHolder)
	local practice = RoomService.practiceRoom()
	spec:truthy("practice room was created", practice)
	if practice ~= nil then
		spec:truthy("practice room has a floor", practice.floor)
		spec:truthy("practice room has an entrance door", practice.entranceDoor)
		spec:truthy("practice room has an exit door", practice.exitDoor)
		spec:truthy(
			"practice room parented under Static",
			practice.model:IsDescendantOf(static :: Instance)
		)
	end

	local generated = FloorService.generatedFolder()

	-- ------------------------------------------------ player-driven checks

	local player = Players:GetPlayers()[1]
	if player == nil or not PlayerService.isActionable(player) then
		spec:check("a live player is present to walk the slice", false, "run in Play mode")
		return spec:finish()
	end

	local playerState = PlayerService.get(player)
	local playerRoot = if playerState ~= nil then playerState.rootPart else nil
	if playerRoot == nil then
		spec:check("player has a root part", false)
		return spec:finish()
	end

	local room: RoomService.Room? = nil

	local ok, err = pcall(function()
		local root = playerRoot :: BasePart

		-- --------------------------------------- C. geometry and open state

		-- Build the room around the player: floor origin at their feet.
		local origin = CFrame.new(root.Position - Vector3.new(0, 3, 0))
		room = RoomService.create(TEMPLATE, origin, generated)
		spec:truthy("room created", room)
		local live = room
		if live == nil then
			return
		end

		spec:truthy("room has walls", live.model:FindFirstChild("WallLeft"))
		spec:truthy("room has an entrance lintel", live.model:FindFirstChild("EntranceLintel"))
		spec:truthy("room has an exit lintel", live.model:FindFirstChild("ExitLintel"))
		spec:check("entrance door starts open", RoomService.isDoorOpen(live, live.entranceDoor))
		spec:check("exit door starts closed", not RoomService.isDoorOpen(live, live.exitDoor))

		-- ------------------------------------------ D. entering seals the room

		task.wait(0.3)
		local occupants = RoomService.playersInside(live)
		spec:equals("the player is detected inside", #occupants, 1)
		spec:check("entering leaves the Open phase", live.phase ~= "Open", live.phase)

		task.wait(COMBAT.sealDelay + COMBAT.doorTime + 0.3)
		spec:check(
			"entrance door seals behind the player",
			not RoomService.isDoorOpen(live, live.entranceDoor)
		)
		spec:equals("room is Clearing once sealed", live.phase, "Clearing")

		-- ------------------------------------------------- E. the encounter

		spec:equals(
			"the encounter spawned the configured enemies",
			#live.enemyIds,
			RoomService.expectedEnemyCount(TEMPLATE)
		)
		spec:equals(
			"every spawned enemy is alive",
			RoomService.liveEnemyCount(live),
			RoomService.expectedEnemyCount(TEMPLATE)
		)
		spec:check(
			"exit stays shut while enemies live",
			not RoomService.isDoorOpen(live, live.exitDoor)
		)

		for _, id in live.enemyIds do
			local enemy = EnemyService.get(id)
			if enemy ~= nil then
				spec:truthy(
					"enemies are parented to the room",
					enemy.model:IsDescendantOf(live.model)
				)
				break
			end
		end

		-- ------------------------------------------ F. clearing opens the exit

		killEveryEnemyIn(live)
		task.wait(0.2)
		spec:equals("all enemies dead after the kill", RoomService.liveEnemyCount(live), 0)

		task.wait(COMBAT.clearDelay + COMBAT.doorTime + 0.4)
		spec:equals("room reports Cleared", live.phase, "Cleared")
		spec:check("exit door opens on clear", RoomService.isDoorOpen(live, live.exitDoor))

		-- ------------------------------ G. leaving mid-fight resets the room

		-- A player who dies mid-room respawns outside it. If the room stayed sealed
		-- it would be unenterable and the run would be stuck, so leaving resets it.
		RoomService.destroy(live)
		room = nil

		local away = CFrame.new(root.Position + Vector3.new(0, 0, -260))
		local remote = RoomService.create(TEMPLATE, away, generated)
		room = remote
		if remote == nil then
			spec:check("second room created", false)
			return
		end

		task.wait(0.3)
		spec:equals("a room with nobody inside stays Open", remote.phase, "Open")

		-- Move it onto the player to seal it, then move it away again.
		remote.model:PivotTo(CFrame.new(root.Position - Vector3.new(0, 3, 0)))
		task.wait(COMBAT.sealDelay + 0.4)
		spec:check("the room sealed with the player inside", remote.phase ~= "Open", remote.phase)
		local sealedEnemies = #remote.enemyIds
		spec:check("the encounter spawned", sealedEnemies > 0, sealedEnemies)

		remote.model:PivotTo(away)
		task.wait(0.4)
		spec:equals("leaving mid-fight resets the room to Open", remote.phase, "Open")
		spec:equals("reset despawned the encounter", #remote.enemyIds, 0)
		spec:check(
			"reset reopened the entrance",
			RoomService.isDoorOpen(remote, remote.entranceDoor)
		)
	end)

	if not ok then
		spec:check("room checks completed without error", false, err)
	end

	-- ------------------------------------------------------ H. teardown

	if room ~= nil then
		RoomService.destroy(room :: RoomService.Room)
	end
	EnemyService.despawnAll()
	PlayerService.setHealth(player, 100)

	-- Phase00_Boot asserts this is empty; a room left behind fails a passing
	-- regression test on the next run rather than this one.
	spec:equals("teardown left Generated empty", #generated:GetChildren(), 0)
	spec:truthy("the practice room survived teardown", RoomService.practiceRoom() ~= nil)

	return spec:finish()
end
