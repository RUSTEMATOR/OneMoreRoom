--!strict
-- One room, run end to end: enter -> seal -> fight -> clear -> exit opens.
--
-- Phase 4's FloorService will orchestrate rooms; this service owns what happens
-- *inside* one. That is the seam: `RoomService.create(template, cframe, parent)` returns
-- a room that runs itself, and the floor just decides where rooms go and when.
--
-- Occupancy is polled with GetPartBoundsInBox on the same Heartbeat as everything else,
-- not detected with .Touched. Touched is tied to network ownership, so a client can
-- fire it — the same reason the sword does not use it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local EnemyConfig = require(ReplicatedStorage.Shared.EnemyConfig)
local FloorConfig = require(ReplicatedStorage.Shared.FloorConfig)
local FloorPlan = require(ReplicatedStorage.Shared.FloorPlan)
local RoomConfig = require(ReplicatedStorage.Shared.RoomConfig)
local BossService = require(script.Parent.BossService)
local EnemyService = require(script.Parent.EnemyService)
local PlayerService = require(script.Parent.PlayerService)
local RunSessionService = require(script.Parent.RunSessionService)
local RoomBuilder = require(script.Parent.Parent.World.RoomBuilder)
local WorldFolders = require(script.Parent.Parent.World.WorldFolders)

local RoomService = {}

export type RoomPhase = "Open" | "Sealing" | "Clearing" | "Clearing_Done" | "Cleared"

export type Room = {
	id: number,
	template: string,
	model: Model,
	floor: BasePart,
	entranceDoor: BasePart,
	exitDoors: { BasePart },
	exitOffsetsX: { number },
	prize: BasePart?,
	prizeTaken: boolean,
	-- What this room was generated as. Passed in, never fetched: if RoomService
	-- asked FloorService for the current plan that would close a boot-fatal cycle.
	plan: FloorPlan.Plan?,

	phase: RoomPhase,
	phaseEndsAt: number,
	enemyIds: { number },
	-- Set only for a boss room. The room is not cleared until this falls.
	bossId: number?,
	generation: number,
}

local rooms: { [number]: Room } = {}
local nextId = 0

RoomService.onCleared = Instance.new("BindableEvent")
RoomService.onPrizeTaken = Instance.new("BindableEvent")
RoomService.onSealed = Instance.new("BindableEvent")

local function spec(template: string)
	return RoomConfig.templates[template]
end

-- ------------------------------------------------------------------- doors

local function moveDoor(room: Room, door: BasePart, open: boolean)
	local roomSpec = spec(room.template)
	local closedY = roomSpec.doorway.height / 2
	local targetY = if open then closedY - roomSpec.doorTravel else closedY

	-- Doors are anchored and server-owned, so a server-side tween is authoritative
	-- and there is no client to fight over the CFrame.
	local localTarget = CFrame.new(door.Position.X, 0, door.Position.Z)
	local worldY = room.floor.Position.Y + targetY
	local goal = CFrame.new(localTarget.X, worldY, localTarget.Z)

	TweenService
		:Create(door, TweenInfo.new(roomSpec.doorTime, Enum.EasingStyle.Quad), { CFrame = goal })
		:Play()
end

function RoomService.isDoorOpen(room: Room, door: BasePart): boolean
	local roomSpec = spec(room.template)
	local closedY = room.floor.Position.Y + roomSpec.doorway.height / 2
	-- Halfway counts as open: the tween is still running when the player walks through.
	return door.Position.Y < closedY - roomSpec.doorTravel / 2
end

-- ----------------------------------------------------------------- enemies

local function despawnRoomEnemies(room: Room)
	for _, id in room.enemyIds do
		local enemy = EnemyService.get(id)
		if enemy ~= nil then
			enemy.model:Destroy()
		end
	end
	table.clear(room.enemyIds)

	if room.bossId ~= nil then
		local boss = BossService.get(room.bossId)
		if boss ~= nil then
			BossService.despawn(boss)
		end
		room.bossId = nil
	end
end

-- Placements come from the plan, so the same seed puts the same enemies in the same
-- spots. A room with no plan (the practice room builds one from a fixed seed) still
-- works because FloorPlan is pure and can be called for any template.
local function spawnEncounter(room: Room)
	local plan = room.plan
	if plan == nil then
		return
	end
	local origin = room.model:GetPivot()

	-- A boss room spawns its boss instead of an encounter. Same seal, same clear,
	-- same exits — only the occupant differs.
	local roomSpec = spec(room.template)
	if roomSpec.boss ~= nil then
		local boss = BossService.spawn(roomSpec.boss, origin * CFrame.new(0, 4, -16), room.model)
		if boss ~= nil then
			room.bossId = boss.id
		end
	end

	for _, placement in plan.enemies do
		local worldCFrame = origin * CFrame.new(placement.offset + Vector3.new(0, 3, 0))
		local enemy = EnemyService.spawn(placement.kind, worldCFrame, room.model, {
			roll = placement.dropRoll,
			kind = placement.dropKind,
			item = placement.dropItem,
			modifiers = placement.dropModifiers,
			gold = placement.bonusGold,
		})
		if enemy ~= nil then
			table.insert(room.enemyIds, enemy.id)
		end
	end
end

local function liveEnemyCount(room: Room): number
	local alive = 0
	for _, id in room.enemyIds do
		local enemy = EnemyService.get(id)
		if enemy ~= nil and enemy.phase ~= "Dead" then
			alive += 1
		end
	end
	return alive
end

RoomService.liveEnemyCount = liveEnemyCount

function RoomService.boss(room: Room): BossService.Boss?
	return if room.bossId ~= nil then BossService.get(room.bossId) else nil
end

-- --------------------------------------------------------------- occupancy

local function playersInside(room: Room): { Player }
	local roomSpec = spec(room.template)
	local origin = room.model:GetPivot()
	local centre = origin * CFrame.new(0, roomSpec.interior.Y / 2, 0)
	local half = roomSpec.interior

	local found = {}
	for _, state in PlayerService.all() do
		if not state.alive then
			continue
		end
		local root = state.rootPart
		if root == nil or root.Parent == nil then
			continue
		end
		local localPoint = centre:PointToObjectSpace(root.Position)
		if
			math.abs(localPoint.X) <= half.X / 2
			and math.abs(localPoint.Y) <= half.Y / 2
			and math.abs(localPoint.Z) <= half.Z / 2
		then
			table.insert(found, state.player)
		end
	end
	return found
end

RoomService.playersInside = playersInside

-- The volume just beyond the exit doorway. A cleared room is left by walking through
-- it, and FloorService watches this to know when to advance.
-- `exitIndex` selects which door's volume to test. The trigger is centred on that
-- door's local X, not on the room centre: with two doors at +/-9 a room-centred
-- volume would sit over the middle pier and match neither.
local function playersPastExit(
	room: Room,
	exitIndex: number,
	depth: number,
	width: number
): { Player }
	local roomSpec = spec(room.template)
	local origin = room.model:GetPivot()
	local edge = roomSpec.interior.Z / 2 + roomSpec.wallThickness
	local offsetX = room.exitOffsetsX[exitIndex] or 0
	local centre = origin * CFrame.new(offsetX, roomSpec.interior.Y / 2, -(edge + depth / 2))

	local found = {}
	for _, state in PlayerService.all() do
		if not state.alive then
			continue
		end
		local root = state.rootPart
		if root == nil or root.Parent == nil then
			continue
		end
		local localPoint = centre:PointToObjectSpace(root.Position)
		if
			math.abs(localPoint.X) <= width / 2
			and math.abs(localPoint.Y) <= roomSpec.interior.Y / 2
			and math.abs(localPoint.Z) <= depth / 2
		then
			table.insert(found, state.player)
		end
	end
	return found
end

RoomService.playersPastExit = playersPastExit

-- Where a player should land when a floor loads them into this room. The offset is
-- derived from this template's interior rather than passed in, so a small room cannot
-- land the player outside its own walls.
function RoomService.entranceCFrame(room: Room): CFrame
	local roomSpec = spec(room.template)
	local offset = FloorConfig.entranceOffsetFor(roomSpec.interior.Z)
	local origin = room.model:GetPivot()
	-- Facing the exit, which is -Z in room space.
	return origin * CFrame.new(offset) * CFrame.Angles(0, math.pi, 0)
end

-- ------------------------------------------------------------------ resets

function RoomService.reset(room: Room)
	room.generation += 1
	despawnRoomEnemies(room)
	room.phase = "Open"
	room.phaseEndsAt = 0
	moveDoor(room, room.entranceDoor, true)
	for _, door in room.exitDoors do
		moveDoor(room, door, false)
	end
end

-- ------------------------------------------------------------------ prize

-- Walked into rather than pressed: there is no interaction UI until Phase 12, and a
-- proximity pickup needs none. Polled on the same Heartbeat as everything else.
local function stepPrize(room: Room, dt: number)
	local prize = room.prize
	if prize == nil or room.prizeTaken or prize.Parent == nil then
		return
	end

	local prizeSpec = RoomConfig.prize
	prize.CFrame = prize.CFrame * CFrame.Angles(0, prizeSpec.spinPerSecond * dt, 0)

	-- Kind comes from the template (a Treasure room is always treasure); only the
	-- amount is seeded, and it lives on the plan.
	local plan = room.plan
	local reward = if plan ~= nil then plan.reward else nil
	if reward == nil then
		return
	end

	for _, state in PlayerService.all() do
		if not state.alive then
			continue
		end
		local root = state.rootPart
		if root == nil or root.Parent == nil then
			continue
		end
		if (root.Position - prize.Position).Magnitude > prizeSpec.pickupRadius then
			continue
		end

		room.prizeTaken = true
		if reward.kind == "gold" then
			RunSessionService.addGold(reward.amount)
		elseif reward.kind == "heal" then
			-- A fraction of max health, so it keeps its value once Phase 9's
			-- permanent upgrades raise the ceiling.
			PlayerService.setHealth(state.player, state.health + state.maxHealth * reward.amount)
		end

		prize:Destroy()
		room.prize = nil
		RoomService.onPrizeTaken:Fire(room, state.player, reward.kind, reward.amount)
		return
	end
end

-- --------------------------------------------------------------------- tick

local function stepRoom(room: Room, now: number)
	if room.model.Parent == nil then
		rooms[room.id] = nil
		return
	end

	local roomSpec = spec(room.template)
	local occupants = playersInside(room)

	if room.phase == "Open" then
		if #occupants > 0 then
			room.phase = "Sealing"
			room.phaseEndsAt = now + roomSpec.sealDelay
			moveDoor(room, room.entranceDoor, false)
			RoomService.onSealed:Fire(room)
		end
		return
	end

	-- Dying mid-room has to reset cleanly, or the player respawns outside a sealed
	-- room they can never re-enter and the run is stuck.
	if room.phase ~= "Cleared" and #occupants == 0 then
		RoomService.reset(room)
		return
	end

	if room.phase == "Sealing" then
		if now >= room.phaseEndsAt then
			spawnEncounter(room)
			room.phase = "Clearing"
		end
		return
	end

	if room.phase == "Clearing" then
		local bossAlive = false
		if room.bossId ~= nil then
			local boss = BossService.get(room.bossId)
			bossAlive = boss ~= nil and not BossService.isDefeated(boss)
		end
		if liveEnemyCount(room) == 0 and not bossAlive then
			room.phase = "Clearing_Done"
			room.phaseEndsAt = now + roomSpec.clearDelay
		end
		return
	end

	if room.phase == "Clearing_Done" and now >= room.phaseEndsAt then
		room.phase = "Cleared"
		for _, door in room.exitDoors do
			moveDoor(room, door, true)
		end
		RoomService.onCleared:Fire(room)
		return
	end
end

local function step(dt: number)
	local now = os.clock()
	for _, room in rooms do
		stepRoom(room, now)
		stepPrize(room, dt)
	end
end

-- -------------------------------------------------------------------- api

function RoomService.create(
	template: string,
	cframe: CFrame,
	parent: Instance?,
	plan: FloorPlan.Plan?
): Room?
	local exitCount = if plan ~= nil then #plan.exits else 1
	local parts = RoomBuilder.build(template, exitCount)
	if parts == nil then
		return nil
	end

	nextId += 1
	local room: Room = {
		id = nextId,
		template = template,
		model = parts.model,
		floor = parts.floor,
		entranceDoor = parts.entranceDoor,
		exitDoors = parts.exitDoors,
		exitOffsetsX = parts.exitOffsetsX,
		prize = parts.prize,
		prizeTaken = false,
		plan = plan,
		phase = "Open",
		phaseEndsAt = 0,
		enemyIds = {},
		bossId = nil,
		generation = 0,
	}

	parts.model.Parent = parent or WorldFolders.generated()
	parts.model:PivotTo(cframe)
	rooms[room.id] = room
	return room
end

function RoomService.destroy(room: Room)
	despawnRoomEnemies(room)
	rooms[room.id] = nil
	if room.model.Parent ~= nil then
		room.model:Destroy()
	end
end

function RoomService.destroyAll()
	for _, room in rooms do
		RoomService.destroy(room)
	end
	table.clear(rooms)
end

function RoomService.get(id: number): Room?
	return rooms[id]
end

function RoomService.count(): number
	local n = 0
	for _ in rooms do
		n += 1
	end
	return n
end

-- --------------------------------------------------------------- practice

local practiceRoomId: number? = nil

function RoomService.practiceRoom(): Room?
	local id = practiceRoomId
	return if id ~= nil then rooms[id] else nil
end

local function buildPracticeRoom()
	if not RoomConfig.practice.enabled then
		return
	end
	local static = WorldFolders.static()
	local stale = static:FindFirstChild("PracticeRoom")
	if stale ~= nil then
		stale:Destroy()
	end

	local holder = Instance.new("Folder")
	holder.Name = "PracticeRoom"
	holder.Parent = static

	-- A fixed seed, so the practice room is identical every session and a manual
	-- pass compares like with like.
	local practicePlan = FloorPlan.generate(
		RoomConfig.practice.seed,
		RoomConfig.practice.depth,
		RoomConfig.practice.template
	)
	local room = RoomService.create(
		RoomConfig.practice.template,
		CFrame.new(RoomConfig.practice.position),
		holder,
		practicePlan
	)
	if room ~= nil then
		practiceRoomId = room.id
	end
end

function RoomService.Init()
	table.clear(rooms)
	nextId = 0
	practiceRoomId = nil
end

function RoomService.Start()
	RunService.Heartbeat:Connect(step)

	-- Deferred: Start must not yield, and the room wants a settled world before its
	-- anchored parts are pivoted into place.
	task.spawn(function()
		task.wait(0.6)
		buildPracticeRoom()
	end)
end

-- Plan-derived now, so the assertion tracks what was actually generated rather than
-- a fixed list that no longer exists.
function RoomService.expectedEnemyCount(room: Room): number
	local plan = room.plan
	return if plan ~= nil then #plan.enemies else 0
end

-- Local X of each exit door, for anything that needs to aim at one.
function RoomService.exitOffsetX(room: Room, exitIndex: number): number
	return room.exitOffsetsX[exitIndex] or 0
end

function RoomService.exitCount(room: Room): number
	return #room.exitDoors
end

RoomService.enemyConfig = EnemyConfig

return RoomService
