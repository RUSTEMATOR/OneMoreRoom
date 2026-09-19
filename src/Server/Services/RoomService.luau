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
local RoomConfig = require(ReplicatedStorage.Shared.RoomConfig)
local EnemyService = require(script.Parent.EnemyService)
local FloorService = require(script.Parent.FloorService)
local PlayerService = require(script.Parent.PlayerService)
local RoomBuilder = require(script.Parent.Parent.World.RoomBuilder)

local RoomService = {}

export type RoomPhase = "Open" | "Sealing" | "Clearing" | "Clearing_Done" | "Cleared"

export type Room = {
	id: number,
	template: string,
	model: Model,
	floor: BasePart,
	entranceDoor: BasePart,
	exitDoor: BasePart,

	phase: RoomPhase,
	phaseEndsAt: number,
	enemyIds: { number },
	generation: number,
}

local rooms: { [number]: Room } = {}
local nextId = 0

RoomService.onCleared = Instance.new("BindableEvent")
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
end

local function spawnEncounter(room: Room)
	local roomSpec = spec(room.template)
	local origin = room.model:GetPivot()

	for _, offset in roomSpec.enemySpawns do
		local worldCFrame = origin * CFrame.new(offset + Vector3.new(0, 3, 0))
		local enemy = EnemyService.spawn(roomSpec.enemyKind, worldCFrame, room.model)
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

-- ------------------------------------------------------------------ resets

function RoomService.reset(room: Room)
	room.generation += 1
	despawnRoomEnemies(room)
	room.phase = "Open"
	room.phaseEndsAt = 0
	moveDoor(room, room.entranceDoor, true)
	moveDoor(room, room.exitDoor, false)
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
		if liveEnemyCount(room) == 0 then
			room.phase = "Clearing_Done"
			room.phaseEndsAt = now + roomSpec.clearDelay
		end
		return
	end

	if room.phase == "Clearing_Done" and now >= room.phaseEndsAt then
		room.phase = "Cleared"
		moveDoor(room, room.exitDoor, true)
		RoomService.onCleared:Fire(room)
		return
	end
end

local function step()
	local now = os.clock()
	for _, room in rooms do
		stepRoom(room, now)
	end
end

-- -------------------------------------------------------------------- api

function RoomService.create(template: string, cframe: CFrame, parent: Instance?): Room?
	local parts = RoomBuilder.build(template)
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
		exitDoor = parts.exitDoor,
		phase = "Open",
		phaseEndsAt = 0,
		enemyIds = {},
		generation = 0,
	}

	parts.model.Parent = parent or FloorService.generatedFolder()
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
	local static = FloorService.staticFolder()
	local stale = static:FindFirstChild("PracticeRoom")
	if stale ~= nil then
		stale:Destroy()
	end

	local holder = Instance.new("Folder")
	holder.Name = "PracticeRoom"
	holder.Parent = static

	local room = RoomService.create(
		RoomConfig.practice.template,
		CFrame.new(RoomConfig.practice.position),
		holder
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

-- Kept so the encounter size is asserted against config rather than a literal.
function RoomService.expectedEnemyCount(template: string): number
	local roomSpec = spec(template)
	if roomSpec == nil then
		return 0
	end
	return #roomSpec.enemySpawns
end

RoomService.enemyKindFor = function(template: string): string
	return spec(template).enemyKind
end

RoomService.enemyConfig = EnemyConfig

return RoomService
