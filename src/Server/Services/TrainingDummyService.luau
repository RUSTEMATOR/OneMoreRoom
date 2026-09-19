--!strict
-- A static target with health, a hit reaction and an auto-reset. Not the Skeleton:
-- no AI, no chasing. It exists so the Phase 1 gate ("does swinging feel good?") can be
-- judged against something instead of against a void, and it stays afterwards as a
-- fixture for every later combat change.
--
-- It lives in Workspace/Static, not Workspace/Generated. Those two are about LIFETIME
-- (Generated is run-scoped and cleared by FloorService.clear()); "content is Lua data"
-- is about PROVENANCE, and this is built from CombatConfig.trainingDummy. Both rules
-- are satisfied.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local CombatTypes = require(ReplicatedStorage.Shared.CombatTypes)
local CombatService = require(script.Parent.CombatService)
local WorldFolders = require(script.Parent.Parent.World.WorldFolders)

local TrainingDummyService = {}

local config = CombatConfig.trainingDummy

local model: Model? = nil
local pivot: Motor6D? = nil
local readout: TextLabel? = nil
local health = config.maxHealth
local generation = 0

local function updateReadout()
	if readout ~= nil then
		readout.Text = `{math.floor(health + 0.5)} / {config.maxHealth}`
	end
end

local function tiltTo(degrees: number, seconds: number)
	local joint = pivot
	if joint == nil then
		return
	end
	local goal = CFrame.new(0, config.baseSize.Y / 2, 0) * CFrame.Angles(math.rad(degrees), 0, 0)
	TweenService:Create(joint, TweenInfo.new(seconds, Enum.EasingStyle.Quad), { C0 = goal }):Play()
end

function TrainingDummyService.isKnockedOut(): boolean
	return health <= 0
end

function TrainingDummyService.getHealth(): (number, number)
	return health, config.maxHealth
end

function TrainingDummyService.reset()
	generation += 1
	health = config.maxHealth
	updateReadout()
	tiltTo(0, config.hitReactionTime)
	local current = model
	if current ~= nil then
		CombatService.broadcast({ kind = "TargetReset", target = current })
	end
end

local function applyDamage(amount: number, _info: CombatTypes.DamageInfo): (number, string?)
	if model == nil then
		return 0, "nodummy"
	end
	if health <= 0 then
		return 0, "dead"
	end

	local before = health
	health = math.clamp(health - amount, 0, config.maxHealth)
	local dealt = before - health
	updateReadout()

	if health <= 0 then
		-- The hit reaction is server-side: this is an anchored, server-owned object,
		-- and Phase 2 skeletons need authoritative reactions anyway. Only the flash
		-- is client-side. World geometry is the server's; screen juice is the client's.
		tiltTo(config.koTilt, config.hitReactionTime * 2)
		local gen = generation
		task.delay(config.resetDelay, function()
			if gen ~= generation then
				return
			end
			TrainingDummyService.reset()
		end)
	else
		tiltTo(config.hitReactionTilt, config.hitReactionTime)
		local gen = generation
		task.delay(config.hitReactionTime, function()
			if gen ~= generation or health <= 0 then
				return
			end
			tiltTo(0, config.hitReactionTime)
		end)
	end

	return dealt, nil
end

local function build(parent: Folder): Model
	local dummy = Instance.new("Model")
	dummy.Name = config.name

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = config.baseSize
	base.Color = config.baseColor
	base.Material = Enum.Material.Slate
	base.Anchored = true
	base.Position = config.basePosition
	base.Parent = dummy
	dummy.PrimaryPart = base

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = config.bodySize
	body.Color = config.bodyColor
	body.Material = config.material
	body.Anchored = false
	body.CanCollide = true
	body.Position = config.basePosition
		+ Vector3.new(0, config.baseSize.Y / 2 + config.bodySize.Y / 2, 0)
	body.Parent = dummy

	-- Base is anchored, so the whole assembly is anchored and Body is positioned purely
	-- by the joint. That makes the hit reaction a single C0 tween.
	local joint = Instance.new("Motor6D")
	joint.Name = "Pivot"
	joint.Part0 = base
	joint.Part1 = body
	joint.C0 = CFrame.new(0, config.baseSize.Y / 2, 0)
	joint.C1 = CFrame.new(0, -config.bodySize.Y / 2, 0)
	joint.Parent = base

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Readout"
	billboard.Size = UDim2.fromScale(6, 1.4)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, config.bodySize.Y / 2 + 1.4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = body

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.Parent = billboard

	pivot = joint
	readout = label
	dummy.Parent = parent
	return dummy
end

function TrainingDummyService.model(): Model?
	return model
end

function TrainingDummyService.Init()
	health = config.maxHealth
	generation = 0
end

function TrainingDummyService.Start()
	if not config.enabled then
		return
	end

	local static = WorldFolders.static()

	-- Destroy any survivor first, so a hot resync cannot duplicate the dummy.
	local stale = static:FindFirstChild(config.name)
	if stale ~= nil then
		stale:Destroy()
	end

	model = build(static)
	updateReadout()

	local built = model
	if built ~= nil then
		CombatService.registerDamageable({
			model = built,
			kind = "Dummy",
			getHealth = TrainingDummyService.getHealth,
			applyDamage = applyDamage,
		})
	end
end

return TrainingDummyService
