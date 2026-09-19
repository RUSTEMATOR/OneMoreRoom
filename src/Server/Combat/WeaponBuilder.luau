--!strict
-- Builds a weapon from its data spec in CombatConfig. Not a service: no lifecycle, no
-- state. Exists to keep Instance.new soup out of the rules engine.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)

local WeaponBuilder = {}

local WELD_NAME = "OMF_WeaponGrip"
local MODEL_NAME = "OMF_Weapon"

local function makePart(name: string, size: Vector3, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Metal
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	return part
end

-- The sword is cosmetic. Hit detection is a volume query off the HumanoidRootPart, so
-- the blade never needs to be queryable — that also keeps it out of its own arc.
function WeaponBuilder.build(weaponId: string): Model
	local spec = CombatConfig.weapons[weaponId]

	local model = Instance.new("Model")
	model.Name = MODEL_NAME

	local grip = makePart("Grip", spec.grip.size, spec.grip.color)
	grip.Material = Enum.Material.Wood
	grip.Parent = model
	model.PrimaryPart = grip

	local guard = makePart("Guard", spec.guard.size, spec.guard.color)
	guard.Parent = model

	local blade = makePart("Blade", spec.blade.size, spec.blade.color)
	blade.Parent = model

	local guardWeld = Instance.new("Weld")
	guardWeld.Part0 = grip
	guardWeld.Part1 = guard
	guardWeld.C0 = CFrame.new(0, spec.grip.size.Y / 2, 0)
	guardWeld.Parent = grip

	local bladeWeld = Instance.new("Weld")
	bladeWeld.Part0 = grip
	bladeWeld.Part1 = blade
	bladeWeld.C0 = CFrame.new(0, spec.grip.size.Y / 2 + spec.blade.size.Y / 2, 0)
	bladeWeld.Parent = grip

	return model
end

function WeaponBuilder.equip(character: Model, weaponId: string): Model?
	local existing = character:FindFirstChild(MODEL_NAME)
	if existing ~= nil then
		existing:Destroy()
	end

	-- R15 is RightHand; R6 is "Right Arm". Support both so a rig change does not
	-- silently drop the weapon.
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if hand == nil or not hand:IsA("BasePart") then
		return nil
	end

	local spec = CombatConfig.weapons[weaponId]
	local model = WeaponBuilder.build(weaponId)
	local grip = model.PrimaryPart
	if grip == nil then
		model:Destroy()
		return nil
	end

	grip.CFrame = hand.CFrame * spec.gripOffset

	local weld = Instance.new("Weld")
	weld.Name = WELD_NAME
	weld.Part0 = hand
	weld.Part1 = grip
	weld.C0 = spec.gripOffset
	weld.Parent = grip

	model.Parent = character
	return model
end

return WeaponBuilder
