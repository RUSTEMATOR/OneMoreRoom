--!strict
-- Owns floor generation and the Generated/Static split. Everything this service builds
-- goes under Workspace/Generated and is cleared at the start of every run; anything
-- hand-authored lives under Workspace/Static and is never touched here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rng = require(ReplicatedStorage.Shared.Rng)

local FloorService = {}

local generated: Folder
local static: Folder

local function ensureFolder(name: string): Folder
	local existing = workspace:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = workspace
	return folder
end

function FloorService.Init()
	generated = ensureFolder("Generated")
	static = ensureFolder("Static")
end

function FloorService.clear()
	generated:ClearAllChildren()
end

function FloorService.generatedFolder(): Folder
	return generated
end

function FloorService.staticFolder(): Folder
	return static
end

-- Phase 4 fills this in. The signature is fixed now because the seeded-layout golden
-- hash spec is written against it.
function FloorService.buildFloor(seed: number, depth: number): Rng.Rng
	FloorService.clear()
	return Rng.new(seed, "floor", depth)
end

return FloorService
