--!strict
-- Builds a room's geometry from its template. Not a service: no lifecycle, no state.
--
-- The room is laid out around its own origin (the centre of the floor), so the caller
-- positions it with a single PivotTo and nothing here needs to know where it sits.
-- Entrance is +Z, exit is -Z.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoomConfig = require(ReplicatedStorage.Shared.RoomConfig)

local RoomBuilder = {}

export type RoomParts = {
	model: Model,
	floor: BasePart,
	entranceDoor: BasePart,
	exitDoor: BasePart,
	interiorCentre: Vector3,
}

local function makePart(
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	material: Enum.Material
): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- One of the two Z-facing walls, with a centred gap: two piers plus a lintel. Cheaper
-- to reason about than CSG, and it stays diffable.
local function buildWallWithDoorway(parent: Model, prefix: string, spec: any, zOffset: number)
	local interior = spec.interior
	local thickness = spec.wallThickness
	local width = spec.doorway.width
	local height = spec.doorway.height
	local pierWidth = (interior.X + thickness * 2 - width) / 2
	local pierOffset = width / 2 + pierWidth / 2

	local function place(name: string, size: Vector3, centre: Vector3)
		local part = makePart(name, size, centre, spec.wallColor, spec.material)
		part.Parent = parent
	end

	place(
		`{prefix}PierA`,
		Vector3.new(pierWidth, interior.Y, thickness),
		Vector3.new(-pierOffset, interior.Y / 2, zOffset)
	)
	place(
		`{prefix}PierB`,
		Vector3.new(pierWidth, interior.Y, thickness),
		Vector3.new(pierOffset, interior.Y / 2, zOffset)
	)
	place(
		`{prefix}Lintel`,
		Vector3.new(width, interior.Y - height, thickness),
		Vector3.new(0, height + (interior.Y - height) / 2, zOffset)
	)
end

function RoomBuilder.build(templateId: string): RoomParts?
	local spec = RoomConfig.templates[templateId]
	if spec == nil then
		return nil
	end

	local interior = spec.interior
	local thickness = spec.wallThickness

	local model = Instance.new("Model")
	model.Name = `Room_{spec.id}`

	local floor = makePart(
		"Floor",
		Vector3.new(interior.X + thickness * 2, spec.floorThickness, interior.Z + thickness * 2),
		Vector3.new(0, -spec.floorThickness / 2, 0),
		spec.floorColor,
		spec.material
	)
	floor.Parent = model
	model.PrimaryPart = floor

	-- Solid side walls, doorways front and back.
	local sideSize = Vector3.new(thickness, interior.Y, interior.Z + thickness * 2)
	local left = makePart(
		"WallLeft",
		sideSize,
		Vector3.new(-(interior.X / 2 + thickness / 2), interior.Y / 2, 0),
		spec.wallColor,
		spec.material
	)
	left.Parent = model
	local right = makePart(
		"WallRight",
		sideSize,
		Vector3.new(interior.X / 2 + thickness / 2, interior.Y / 2, 0),
		spec.wallColor,
		spec.material
	)
	right.Parent = model

	buildWallWithDoorway(model, "Entrance", spec, interior.Z / 2 + thickness / 2)
	buildWallWithDoorway(model, "Exit", spec, -(interior.Z / 2 + thickness / 2))

	local doorSize = Vector3.new(spec.doorway.width, spec.doorway.height, thickness)

	-- Doors slide vertically: sunk into the floor is open, raised is closed. The room
	-- starts enterable but not exitable, so the entrance begins sunk and the exit
	-- begins raised.
	local openY = spec.doorway.height / 2 - spec.doorTravel
	local closedY = spec.doorway.height / 2

	local entranceDoor = makePart(
		"EntranceDoor",
		doorSize,
		Vector3.new(0, openY, interior.Z / 2 + thickness / 2),
		spec.doorColor,
		spec.doorMaterial
	)
	entranceDoor.Parent = model

	local exitDoor = makePart(
		"ExitDoor",
		doorSize,
		Vector3.new(0, closedY, -(interior.Z / 2 + thickness / 2)),
		spec.doorColor,
		spec.doorMaterial
	)
	exitDoor.Parent = model

	-- A lit strip over the exit, so which way is forward reads at a glance.
	local trim = makePart(
		"ExitTrim",
		Vector3.new(spec.doorway.width, 0.6, 0.6),
		Vector3.new(0, spec.doorway.height + 0.6, -(interior.Z / 2 + thickness / 2)),
		spec.trimColor,
		Enum.Material.Neon
	)
	trim.Parent = model

	return {
		model = model,
		floor = floor,
		entranceDoor = entranceDoor,
		exitDoor = exitDoor,
		interiorCentre = Vector3.new(0, interior.Y / 2, 0),
	}
end

return RoomBuilder
