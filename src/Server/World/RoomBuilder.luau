--!strict
-- Builds a room's geometry from its template. Not a service: no lifecycle, no state.
--
-- The room is laid out around its own origin (the centre of the floor), so the caller
-- positions it with a single PivotTo and nothing here needs to know where it sits.
-- Entrance is +Z (always one door); exits are -Z and there may be more than one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoomConfig = require(ReplicatedStorage.Shared.RoomConfig)

local RoomBuilder = {}

export type RoomParts = {
	model: Model,
	floor: BasePart,
	entranceDoor: BasePart,
	exitDoors: { BasePart },
	-- Local X centre of each exit door, which is what the exit trigger volumes need.
	exitOffsetsX: { number },
	prize: BasePart?,
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

-- One of the two Z-facing walls, with `doorCount` evenly spaced gaps: n+1 piers and n
-- lintels. Cheaper to reason about than CSG, and it stays diffable.
--
-- Returns the local X centre of each gap, which is what the caller needs to place the
-- doors, their trim, and the exit trigger volumes.
--
-- For doorCount == 1 this reproduces the original single-doorway geometry exactly
-- (span 44, width 10 -> one pier of 17 either side, gap centred at 0), so entrances
-- and single-exit rooms are untouched by the generalisation.
local function buildWallWithDoorways(
	parent: Model,
	prefix: string,
	spec: any,
	zOffset: number,
	doorCount: number
): { number }
	local interior = spec.interior
	local thickness = spec.wallThickness
	local width = spec.doorway.width
	local height = spec.doorway.height

	local span = interior.X + thickness * 2
	local pierWidth = (span - width * doorCount) / (doorCount + 1)

	local function place(name: string, size: Vector3, centre: Vector3)
		local part = makePart(name, size, centre, spec.wallColor, spec.material)
		part.Parent = parent
	end

	-- Walk left to right: pier, gap, pier, gap, ... pier.
	local centres: { number } = {}
	local cursor = -span / 2
	for index = 1, doorCount do
		place(
			-- Keep the original names when there is one gap, so existing assertions
			-- and any muscle memory still hold.
			if doorCount == 1 then `{prefix}PierA` else `{prefix}Pier{index}`,
			Vector3.new(pierWidth, interior.Y, thickness),
			Vector3.new(cursor + pierWidth / 2, interior.Y / 2, zOffset)
		)
		cursor += pierWidth
		table.insert(centres, cursor + width / 2)
		cursor += width
	end
	place(
		if doorCount == 1 then `{prefix}PierB` else `{prefix}Pier{doorCount + 1}`,
		Vector3.new(pierWidth, interior.Y, thickness),
		Vector3.new(cursor + pierWidth / 2, interior.Y / 2, zOffset)
	)

	for index, centre in centres do
		place(
			if doorCount == 1 then `{prefix}Lintel` else `{prefix}Lintel{index}`,
			Vector3.new(width, interior.Y - height, thickness),
			Vector3.new(centre, height + (interior.Y - height) / 2, zOffset)
		)
	end

	return centres
end

function RoomBuilder.build(templateId: string, exitCount: number?): RoomParts?
	local spec = RoomConfig.templates[templateId]
	if spec == nil then
		return nil
	end

	local exits = math.max(1, exitCount or 1)

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

	local entranceZ = interior.Z / 2 + thickness / 2
	local exitZ = -(interior.Z / 2 + thickness / 2)

	buildWallWithDoorways(model, "Entrance", spec, entranceZ, 1)
	local exitCentres = buildWallWithDoorways(model, "Exit", spec, exitZ, exits)

	local doorSize = Vector3.new(spec.doorway.width, spec.doorway.height, thickness)

	-- Doors slide vertically: sunk into the floor is open, raised is closed. The room
	-- starts enterable but not exitable, so the entrance begins sunk and the exits
	-- begin raised.
	local openY = spec.doorway.height / 2 - spec.doorTravel
	local closedY = spec.doorway.height / 2

	local entranceDoor = makePart(
		"EntranceDoor",
		doorSize,
		Vector3.new(0, openY, entranceZ),
		spec.doorColor,
		spec.doorMaterial
	)
	entranceDoor.Parent = model

	local exitDoors: { BasePart } = {}
	for index, centreX in exitCentres do
		local door = makePart(
			if exits == 1 then "ExitDoor" else `ExitDoor{index}`,
			doorSize,
			Vector3.new(centreX, closedY, exitZ),
			spec.doorColor,
			spec.doorMaterial
		)
		door.Parent = model
		table.insert(exitDoors, door)

		-- One lit strip per door, so a branching room reads as two real choices
		-- rather than one exit and a hole.
		local trim = makePart(
			if exits == 1 then "ExitTrim" else `ExitTrim{index}`,
			Vector3.new(spec.doorway.width, 0.6, 0.6),
			Vector3.new(centreX, spec.doorway.height + 0.6, exitZ),
			spec.trimColor,
			Enum.Material.Neon
		)
		trim.Parent = model
	end

	-- A prize, when the template has one. Reward rooms have no encounter, so they
	-- clear the moment they seal and this is the only thing in them.
	local prize: BasePart? = nil
	if spec.reward ~= nil then
		local prizeSpec = RoomConfig.prize
		local colour = if spec.reward.kind == "heal"
			then Color3.fromRGB(96, 214, 168)
			else Color3.fromRGB(226, 184, 74)
		local made = makePart(
			"Prize",
			prizeSpec.size,
			Vector3.new(0, prizeSpec.height, 0),
			colour,
			Enum.Material.Neon
		)
		made.CanCollide = false
		made.CanQuery = false
		made.Parent = model
		prize = made
	end

	return {
		model = model,
		floor = floor,
		entranceDoor = entranceDoor,
		exitDoors = exitDoors,
		exitOffsetsX = exitCentres,
		prize = prize,
		interiorCentre = Vector3.new(0, interior.Y / 2, 0),
	}
end

return RoomBuilder
