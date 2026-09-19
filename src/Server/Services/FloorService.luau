--!strict
-- The run: which floor you are on, which room that is, and when you advance.
--
-- The division of labour with RoomService is the seam Phase 6 needs. RoomService owns
-- what happens INSIDE a room — sealing, the encounter, the doors. FloorService owns
-- WHICH room exists and when the next one loads. Procedural generation replaces only
-- the "which" half.
--
-- Folder ownership lives in WorldFolders rather than here, because RoomService needs
-- somewhere to parent a room and FloorService needs RoomService to make one — as a
-- service-to-service cycle that would be a hard boot error.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FloorConfig = require(ReplicatedStorage.Shared.FloorConfig)
local Rng = require(ReplicatedStorage.Shared.Rng)
local PlayerService = require(script.Parent.PlayerService)
local RoomService = require(script.Parent.RoomService)
local RunSessionService = require(script.Parent.RunSessionService)
local WorldFolders = require(script.Parent.Parent.World.WorldFolders)

local FloorService = {}

local currentRoom: RoomService.Room? = nil
local advancing = false

FloorService.onFloorLoaded = Instance.new("BindableEvent")
FloorService.onFloorCleared = Instance.new("BindableEvent")
FloorService.onRunEnded = Instance.new("BindableEvent")

-- ------------------------------------------------------------------ folders

function FloorService.generatedFolder(): Folder
	return WorldFolders.generated()
end

function FloorService.staticFolder(): Folder
	return WorldFolders.static()
end

function FloorService.clear()
	if currentRoom ~= nil then
		RoomService.destroy(currentRoom)
		currentRoom = nil
	end
	WorldFolders.generated():ClearAllChildren()
end

-- ------------------------------------------------------------------- layout

-- Each floor sits well clear of the last, so a lingering enemy or stray physics
-- object from the previous one cannot reach across. Deterministic from the depth, so
-- Phase 6's seeded generation does not have to track positions.
function FloorService.originForFloor(depth: number): CFrame
	local layout = FloorConfig.layout
	return CFrame.new(layout.origin + Vector3.new(0, 0, -layout.floorSpacing * (depth - 1)))
end

-- ---------------------------------------------------------------- accessors

function FloorService.currentRoom(): RoomService.Room?
	return currentRoom
end

function FloorService.currentFloor(): number
	local run = RunSessionService.get()
	return if run ~= nil then run.floor else 0
end

function FloorService.isRunActive(): boolean
	local run = RunSessionService.get()
	return run ~= nil and run.active
end

-- ------------------------------------------------------------------ loading

local function teleportPlayersTo(room: RoomService.Room)
	local target = RoomService.entranceCFrame(room, FloorConfig.layout.entranceOffset)
	for _, state in PlayerService.all() do
		local character = state.character
		if character ~= nil and character.Parent ~= nil then
			-- A deliberate teleport, not a per-frame correction: the owning client
			-- accepts a large one-shot CFrame change without fighting it.
			character:PivotTo(target)
		end
	end
end

function FloorService.loadFloor(depth: number): RoomService.Room?
	FloorService.clear()

	local template = FloorConfig.templateForFloor(depth)
	local room =
		RoomService.create(template, FloorService.originForFloor(depth), WorldFolders.generated())
	if room == nil then
		return nil
	end

	currentRoom = room
	local run = RunSessionService.get()
	if run ~= nil then
		run.floor = depth
	end

	teleportPlayersTo(room)
	FloorService.onFloorLoaded:Fire(depth, room)
	return room
end

-- -------------------------------------------------------------------- run

function FloorService.beginRun(seed: number): RoomService.Room?
	RunSessionService.begin(seed)
	advancing = false
	return FloorService.loadFloor(FloorConfig.run.firstFloor)
end

function FloorService.endRun()
	FloorService.clear()
	RunSessionService.finish()
	advancing = false
	FloorService.onRunEnded:Fire()
end

function FloorService.advance(): RoomService.Room?
	if not FloorService.isRunActive() then
		return nil
	end
	local next = FloorService.currentFloor() + 1
	return FloorService.loadFloor(next)
end

-- Phase 6 replaces this with a seeded graph. The signature is already the one the
-- golden-hash reproducibility spec will assert against.
function FloorService.buildFloor(seed: number, depth: number): Rng.Rng
	return Rng.new(seed, "floor", depth)
end

-- --------------------------------------------------------------------- tick

local function step()
	if advancing or not FloorService.isRunActive() then
		return
	end
	local room = currentRoom
	if room == nil or room.phase ~= "Cleared" then
		return
	end

	local layout = FloorConfig.layout
	local leaving =
		RoomService.playersPastExit(room, layout.exitTriggerDepth, layout.exitTriggerWidth)
	if #leaving == 0 then
		return
	end

	-- Latch: loadFloor destroys the room and teleports players, and without this the
	-- same frame's leftover state could advance twice.
	advancing = true
	local cleared = FloorService.currentFloor()
	RunSessionService.addGold(FloorConfig.run.clearBonusGold)
	FloorService.onFloorCleared:Fire(cleared)

	task.spawn(function()
		FloorService.advance()
		advancing = false
	end)
end

function FloorService.Init()
	currentRoom = nil
	advancing = false
	-- Created eagerly so they exist in the Explorer at boot and Phase00_Boot can
	-- assert on them.
	WorldFolders.generated()
	WorldFolders.static()
end

function FloorService.Start()
	RunService.Heartbeat:Connect(step)
end

return FloorService
