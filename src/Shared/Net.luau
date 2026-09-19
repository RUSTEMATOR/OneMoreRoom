--!strict
-- Sole source of truth for remote names. The server materializes these during boot;
-- the client resolves them by WaitForChild. A name appears in this file and nowhere else.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

Net.Events = {
	"RequestAttack",
	"RequestDodge",
	"CombatFeedback",
	"RunStateChanged",
}

Net.Functions = {
	"RequestRunState",
}

function Net.buildRemotes()
	local folder = ReplicatedStorage:WaitForChild("Remotes")

	for _, name in Net.Events do
		if folder:FindFirstChild(name) == nil then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end

	for _, name in Net.Functions do
		if folder:FindFirstChild(name) == nil then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Net.event(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	return folder:WaitForChild(name) :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	return folder:WaitForChild(name) :: RemoteFunction
end

return Net
