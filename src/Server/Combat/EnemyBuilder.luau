--!strict
-- Builds an enemy rig from its data spec. Not a service: no lifecycle, no state.
--
-- The rig is a minimal R6 Humanoid — HumanoidRootPart, Torso, Head and two Motor6Ds.
-- A Humanoid (rather than CFrame movement) is what gives us Humanoid:MoveTo with real
-- collision, so a skeleton bumps into walls instead of walking through them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyConfig = require(ReplicatedStorage.Shared.EnemyConfig)

local EnemyBuilder = {}

local function makePart(name: string, size: Vector3, color: Color3, collide: boolean): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.CanCollide = collide
	part.Anchored = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

function EnemyBuilder.build(kind: string): Model
	local spec = EnemyConfig.kinds[kind]
	local rig = spec.rig

	local model = Instance.new("Model")
	model.Name = spec.id

	local root = makePart("HumanoidRootPart", rig.rootSize, rig.boneColor, false)
	root.Transparency = 1
	root.Material = rig.material
	root.Parent = model
	model.PrimaryPart = root

	local torso = makePart("Torso", rig.torsoSize, rig.torsoColor, true)
	torso.Material = rig.material
	torso.Parent = model

	local head = makePart("Head", rig.headSize, rig.boneColor, false)
	head.Material = rig.material
	head.Parent = model

	local rootJoint = Instance.new("Motor6D")
	rootJoint.Name = "RootJoint"
	rootJoint.Part0 = root
	rootJoint.Part1 = torso
	rootJoint.Parent = root

	local neck = Instance.new("Motor6D")
	neck.Name = "Neck"
	neck.Part0 = torso
	neck.Part1 = head
	neck.C0 = CFrame.new(0, rig.torsoSize.Y / 2, 0)
	neck.C1 = CFrame.new(0, -rig.headSize.Y / 2, 0)
	neck.Parent = torso

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.MaxHealth = spec.maxHealth
	humanoid.Health = spec.maxHealth
	humanoid.WalkSpeed = spec.walkSpeed
	-- We own death: the state machine despawns the model. Letting Roblox run its own
	-- death behaviour would fight the despawn timer.
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model

	return model
end

return EnemyBuilder
