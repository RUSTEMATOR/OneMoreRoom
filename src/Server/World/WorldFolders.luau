--!strict
-- The two Workspace folders, owned by a module rather than a service.
--
-- This exists to break a cycle: RoomService needs somewhere to parent a room, and
-- FloorService needs RoomService to create one. Since ServerMain requires every
-- service at top level, a service-to-service cycle is a hard boot error. Folder
-- ownership is not really service behaviour anyway — it is a fact about the world.
--
--   Generated = run-scoped. FloorService.clear() empties it between runs, and
--               Phase00_Boot asserts it is empty before one starts.
--   Static    = persists across runs. The practice area lives here.

local WorldFolders = {}

local function ensure(name: string): Folder
	local existing = workspace:FindFirstChild(name)
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = workspace
	return folder
end

function WorldFolders.generated(): Folder
	return ensure("Generated")
end

function WorldFolders.static(): Folder
	return ensure("Static")
end

return WorldFolders
