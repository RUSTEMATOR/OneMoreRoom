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

-- The rig itself, independent of EnemyConfig, so a boss can use the same builder
-- with its own dimensions. A boss is a bigger enemy, not a different kind of object,
-- and duplicating rig construction for it would mean fixing every rig bug twice.
function EnemyBuilder.buildFromRig(
	name: string,
	rig: any,
	maxHealth: number,
	walkSpeed: number
): Model
	local model = Instance.new("Model")
	model.Name = name

	local root = makePart("HumanoidRootPart", rig.rootSize, rig.boneColor, false)
	root.Transparency = 1
	root.Material = rig.material
	root.Parent = model
	model.PrimaryPart = root

	local torso = makePart("Torso", rig.torsoSize, rig.torsoColor, true)
	torso.Material = rig.material
	torso.Parent = model

	-- A skin is a Decal layered over the material/colour, never a replacement for
	-- them: `rig.torsoColor` is what reads at a glance and at range (the actual
	-- gameplay signal -- cyan means Sentry, ember means Cultist), the texture is
	-- surface detail for when a player is close enough to look. Wrapped on all four
	-- side faces so it holds together from any angle a top-down camera catches.
	if rig.textureId ~= nil and rig.textureId ~= "" then
		for _, face in
			{ Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }
		do
			local skin = Instance.new("Decal")
			skin.Name = "Skin"
			skin.Texture = rig.textureId
			skin.Face = face
			skin.Parent = torso
		end
	end

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
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = walkSpeed
	-- We own death: the state machine despawns the model. Letting Roblox run its own
	-- death behaviour would fight the despawn timer.
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model

	return model
end

function EnemyBuilder.build(kind: string): Model
	local spec = EnemyConfig.kinds[kind]
	return EnemyBuilder.buildFromRig(spec.id, spec.rig, spec.maxHealth, spec.walkSpeed)
end

return EnemyBuilder
