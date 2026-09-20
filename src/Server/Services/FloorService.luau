--!strict
-- The run: which floor you are on, which room that is, and when you advance.
--
-- The division of labour with RoomService is the seam this phase needed. RoomService
-- owns what happens INSIDE a room; FloorService owns WHICH room exists and when the
-- next one loads. Procedural generation replaced only the "which" half — RoomService
-- did not learn about seeds at all, it just receives a plan.
--
-- Folder ownership lives in WorldFolders rather than here, because RoomService needs
-- somewhere to parent a room and FloorService needs RoomService to make one — as a
-- service-to-service cycle that would be a hard boot error.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FloorConfig = require(ReplicatedStorage.Shared.FloorConfig)
local FloorPlan = require(ReplicatedStorage.Shared.FloorPlan)
local LootConfig = require(ReplicatedStorage.Shared.LootConfig)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Net = require(ReplicatedStorage.Shared.Net)
local InventoryService = require(script.Parent.InventoryService)
local PlayerService = require(script.Parent.PlayerService)
local ProgressionService = require(script.Parent.ProgressionService)
local RoomService = require(script.Parent.RoomService)
local RunSessionService = require(script.Parent.RunSessionService)
local WorldFolders = require(script.Parent.Parent.World.WorldFolders)

local FloorService = {}

local grantStartingRelics: (seed: number) -> ()

local currentRoom: RoomService.Room? = nil
local currentPlan: FloorPlan.Plan? = nil
local nextTemplate: string? = nil
local advancing = false
local runStateChanged: RemoteEvent

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
	currentPlan = nil
	WorldFolders.generated():ClearAllChildren()
end

-- ------------------------------------------------------------------- layout

-- Each floor sits well clear of the last, so a lingering enemy or stray physics
-- object from the previous one cannot reach across. Deterministic from the depth, so
-- generation never has to track positions.
function FloorService.originForFloor(depth: number): CFrame
	local layout = FloorConfig.layout
	return CFrame.new(layout.origin + Vector3.new(0, 0, -layout.floorSpacing * (depth - 1)))
end

-- ---------------------------------------------------------------- accessors

function FloorService.currentRoom(): RoomService.Room?
	return currentRoom
end

function FloorService.currentPlan(): FloorPlan.Plan?
	return currentPlan
end

function FloorService.currentFloor(): number
	local run = RunSessionService.get()
	return if run ~= nil then run.floor else 0
end

function FloorService.currentSeed(): number
	local run = RunSessionService.get()
	return if run ~= nil then run.seed else 0
end

function FloorService.isRunActive(): boolean
	local run = RunSessionService.get()
	return run ~= nil and run.active
end

-- Seeded, so two runs on one seed open with the same relics. Keyed separately from
-- floor generation, so buying Heirloom cannot shift the layouts.
function grantStartingRelics(seed: number)
	for _, state in PlayerService.all() do
		local count = ProgressionService.startingRelicCount(state.player)
		if count <= 0 then
			continue
		end
		local rng = Rng.new(seed, "startingRelics", state.player.UserId)
		for _ = 1, count do
			local pick = LootConfig.relicPool[rng:int(1, #LootConfig.relicPool)]
			InventoryService.grant(state.player, pick)
		end
	end
	for _, state in PlayerService.all() do
		InventoryService.refreshMaxHealth(state.player)
	end
end

-- ------------------------------------------------------------------ loading

local function broadcastRunState()
	if runStateChanged == nil then
		return
	end
	local run = RunSessionService.get()
	runStateChanged:FireAllClients({
		active = run ~= nil and run.active,
		floor = if run ~= nil then run.floor else 0,
		seed = if run ~= nil then run.seed else 0,
		gold = if run ~= nil then run.gold else 0,
		template = if currentPlan ~= nil then currentPlan.template else nil,
	})
end

local function teleportPlayersTo(room: RoomService.Room)
	local target = RoomService.entranceCFrame(room)
	for _, state in PlayerService.all() do
		local character = state.character
		if character ~= nil and character.Parent ~= nil then
			-- A deliberate teleport, not a per-frame correction: the owning client
			-- accepts a large one-shot CFrame change without fighting it.
			character:PivotTo(target)
		end
	end
end

-- MUST NOT YIELD. The floor slab ends exactly at the exit wall, so the exit trigger
-- volume sits over void; this whole chain completing in one frame is what stops a
-- player who just walked out from free-falling while `advancing` is latched.
function FloorService.loadFloor(depth: number, requested: string): RoomService.Room?
	FloorService.clear()

	-- The depth wins over the seed on a boss floor. Enforced here rather than only
	-- in exitOptions, so arriving by any route — advance(), a direct loadFloor, a
	-- repro — still meets the boss.
	local template = FloorPlan.forcedTemplate(depth) or requested
	local seed = FloorService.currentSeed()
	local plan = FloorPlan.generate(seed, depth, template)

	local room = RoomService.create(
		template,
		FloorService.originForFloor(depth),
		WorldFolders.generated(),
		plan
	)
	if room == nil then
		return nil
	end

	currentRoom = room
	currentPlan = plan
	nextTemplate = nil

	local run = RunSessionService.get()
	if run ~= nil then
		run.floor = depth
	end

	teleportPlayersTo(room)
	broadcastRunState()
	FloorService.onFloorLoaded:Fire(depth, room, plan)
	return room
end

-- -------------------------------------------------------------------- run

-- Unseeded Random.new() draws from system entropy, which is not math.random and is
-- the only place in the project that is allowed to be non-deterministic: it picks
-- the seed, and everything downstream of the seed is reproducible. Clamped below
-- Rng's modulus, since Rng does `seed % 2147483647` and a larger value would alias.
local entropy = Random.new()

function FloorService.rollSeed(): number
	return entropy:NextInteger(1, 2147483646)
end

function FloorService.beginRun(seed: number?): RoomService.Room?
	local chosen = seed or FloorService.rollSeed()
	RunSessionService.begin(chosen)
	advancing = false
	nextTemplate = nil

	-- A fresh run starts clean, then the Heirloom upgrade hands back whatever it
	-- has bought. Clearing first matters: otherwise a second run would inherit the
	-- first one's equipment and the run/meta split would be a lie.
	InventoryService.clearRun()
	InventoryService.clearPickups()
	grantStartingRelics(chosen)

	local template = FloorPlan.startingTemplate(chosen)
	print(`[OMF] run started — {RunSessionService.describe()} floor 1 {template}`)
	return FloorService.loadFloor(FloorConfig.run.firstFloor, template)
end

function FloorService.endRun()
	local wasActive = FloorService.isRunActive()
	local floorsCleared = math.max(0, FloorService.currentFloor() - 1)

	if wasActive then
		-- The meta half of the economy: Soul Shards survive the run, scaled by how
		-- far it got, so a deep failure still pays for something.
		local shards = InventoryService.awardRunEnd(floorsCleared)
		print(
			`[OMF] run ended — {RunSessionService.describe()} `
				.. `floors:{floorsCleared} shards:+{shards}`
		)
	end

	-- Equipment is run-scoped and goes with it; Soul Shards were already banked.
	InventoryService.clearRun()
	InventoryService.clearPickups()

	FloorService.clear()
	RunSessionService.finish()
	advancing = false
	nextTemplate = nil
	broadcastRunState()
	FloorService.onRunEnded:Fire()
end

-- `exitIndex` selects which of the current plan's exits to take. Defaults to the
-- first, so a direct call without a door context still works.
function FloorService.advance(exitIndex: number?): RoomService.Room?
	if not FloorService.isRunActive() then
		return nil
	end
	local index = exitIndex or 1
	local plan = currentPlan
	local template = nextTemplate
		or (if plan ~= nil then plan.exits[index] or plan.exits[1] else nil)
		or FloorPlan.startingTemplate(FloorService.currentSeed())

	return FloorService.loadFloor(FloorService.currentFloor() + 1, template)
end

-- --------------------------------------------------------------------- gate

-- The physical way a player starts a run. Built once, in Workspace/Static beside the
-- training dummy and the shrines -- world content, not a menu, the same as everything
-- else near spawn.
local function buildRunGate()
	local static = WorldFolders.static()
	local stale = static:FindFirstChild("RunGate")
	if stale ~= nil then
		stale:Destroy()
	end

	local spec = FloorConfig.runGate
	local pad = Instance.new("Part")
	pad.Name = "RunGate"
	pad.Size = spec.size
	pad.Anchored = true
	pad.CanCollide = true
	pad.Material = Enum.Material.DiamondPlate
	pad.Color = Color3.fromRGB(50, 54, 60)
	pad.Position = spec.position + Vector3.new(0, spec.size.Y / 2, 0)
	pad.Parent = static

	local glow = Instance.new("Part")
	glow.Name = "Glow"
	glow.Size = Vector3.new(spec.size.X - 1, 0.1, spec.size.Z - 1)
	glow.Anchored = true
	glow.CanCollide = false
	glow.CanQuery = false
	glow.Material = Enum.Material.Neon
	glow.Color = Color3.fromRGB(80, 220, 220)
	glow.CFrame = CFrame.new(pad.Position + Vector3.new(0, spec.size.Y / 2 + 0.06, 0))
	glow.Parent = pad

	-- A floor-level glow only reads once a player is already looking straight down
	-- at it. A tall, thin beam catches the eye from anywhere in the lobby and over
	-- the practice room's own walls, which a flat pad standing alone did not.
	local beam = Instance.new("Part")
	beam.Name = "Beam"
	beam.Size = Vector3.new(1.2, 24, 1.2)
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(80, 220, 220)
	beam.Transparency = 0.45
	beam.CFrame = CFrame.new(pad.Position + Vector3.new(0, spec.size.Y / 2 + 12, 0))
	beam.Parent = pad

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(14, 4)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = pad

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = billboard

	-- Two lines rather than one: "Descend" alone read as lobby flavour text, not an
	-- instruction. The first line says what it DOES in plain words; the second
	-- keeps the flavour without being the only thing a first-time player sees.
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0)
	title.AutomaticSize = Enum.AutomaticSize.Y
	title.LayoutOrder = 1
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(236, 244, 244)
	title.TextStrokeTransparency = 0.2
	title.Text = "START RUN"
	title.Parent = billboard

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.fromScale(1, 0)
	subtitle.AutomaticSize = Enum.AutomaticSize.Y
	subtitle.LayoutOrder = 2
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextScaled = true
	subtitle.TextColor3 = Color3.fromRGB(180, 230, 230)
	subtitle.TextStrokeTransparency = 0.4
	subtitle.Text = "Step here to descend"
	subtitle.Parent = billboard
end

local lastGateAttemptAt: { [Player]: number } = {}

-- Polled like every other proximity interaction in the project (shrines, the boss
-- arena's entry), never `.Touched` -- tied to network ownership, so a client could
-- fire it. Starting a run for free is exactly the kind of thing that has to stay
-- server-decided.
local function stepRunGate()
	if FloorService.isRunActive() then
		return
	end
	local spec = FloorConfig.runGate
	local now = os.clock()

	for _, state in PlayerService.all() do
		local root = state.rootPart
		if root == nil or root.Parent == nil or not state.alive then
			continue
		end
		if now - (lastGateAttemptAt[state.player] or -math.huge) < spec.cooldown then
			continue
		end
		if (root.Position - spec.position).Magnitude <= spec.radius then
			lastGateAttemptAt[state.player] = now
			FloorService.beginRun()
			return
		end
	end
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
	local chosenExit: number? = nil
	for index = 1, RoomService.exitCount(room) do
		local leaving = RoomService.playersPastExit(
			room,
			index,
			layout.exitTriggerDepth,
			layout.exitTriggerWidth
		)
		if #leaving > 0 then
			-- Lowest index wins if two players leave through different doors on the
			-- same frame. Arbitrary, but defined — undefined would be worse.
			chosenExit = index
			break
		end
	end

	if chosenExit == nil then
		return
	end

	-- Latch: loadFloor destroys the room and teleports players, and without this the
	-- same frame's leftover state could advance twice.
	advancing = true
	local cleared = FloorService.currentFloor()
	local plan = currentPlan
	nextTemplate = if plan ~= nil then plan.exits[chosenExit] else nil

	RunSessionService.addGold(FloorConfig.run.clearBonusGold)
	RunSessionService.recordChoice(chosenExit)
	FloorService.onFloorCleared:Fire(cleared, chosenExit)

	task.spawn(function()
		FloorService.advance(chosenExit)
		advancing = false
	end)
end

function FloorService.Init()
	currentRoom = nil
	currentPlan = nil
	nextTemplate = nil
	advancing = false
	table.clear(lastGateAttemptAt)
	runStateChanged = Net.event("RunStateChanged")
	-- Created eagerly so they exist in the Explorer at boot and Phase00_Boot can
	-- assert on them.
	WorldFolders.generated()
	WorldFolders.static()
end

function FloorService.Start()
	RunService.Heartbeat:Connect(step)
	RunService.Heartbeat:Connect(stepRunGate)

	-- Deferred for the same reason RoomService's practice room is: Start must not
	-- yield, and the pad wants a settled world before it is placed.
	task.spawn(function()
		task.wait(0.6)
		buildRunGate()
	end)

	-- Dying during a run ends it. This is the designed roguelite loop, and it also
	-- closes a real hole: a player who died on a cleared floor used to respawn at
	-- the lobby while the run continued 2000 studs away, unreachable, with the
	-- advance latch never firing.
	PlayerService.onDied.Event:Connect(function()
		if FloorService.isRunActive() then
			FloorService.endRun()
		end
	end)
end

return FloorService
