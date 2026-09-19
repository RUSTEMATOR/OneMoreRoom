--!strict
-- Phase 0 acceptance: the tree is wired, boot completed, remotes exist, the
-- Generated/Static split is in place, and the RNG is actually deterministic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Spec = require(script.Parent.Spec)

local Rng = require(ReplicatedStorage.Shared.Rng)

return function()
	local spec = Spec.new("Phase00_Boot")

	spec:equals("server reported ready", game:GetAttribute("OMF_ServerReady"), true)

	spec:truthy("Shared folder synced", ReplicatedStorage:FindFirstChild("Shared"))
	spec:truthy("Services folder synced", ServerScriptService:FindFirstChild("Services"))

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	spec:truthy("Remotes folder exists", remotes)
	if remotes then
		local Net = require(ReplicatedStorage.Shared.Net)
		for _, name in Net.Events do
			spec:truthy(`RemoteEvent {name} built`, remotes:FindFirstChild(name))
		end
		for _, name in Net.Functions do
			spec:truthy(`RemoteFunction {name} built`, remotes:FindFirstChild(name))
		end
	end

	spec:truthy("Workspace/Generated exists", workspace:FindFirstChild("Generated"))
	spec:truthy("Workspace/Static exists", workspace:FindFirstChild("Static"))

	local generated = workspace:FindFirstChild("Generated")
	if generated then
		spec:equals("Generated is empty before a run", #generated:GetChildren(), 0)
	end

	-- Determinism: same seed and key must replay the same sequence, and a different
	-- key must not. This is the guarantee every later seeded-layout test rests on.
	local a = Rng.new(839271, "floor", 3)
	local b = Rng.new(839271, "floor", 3)
	local c = Rng.new(839271, "loot", 3)

	local seqA, seqB, seqC = {}, {}, {}
	for i = 1, 8 do
		seqA[i] = a:int(1, 1000)
		seqB[i] = b:int(1, 1000)
		seqC[i] = c:int(1, 1000)
	end

	spec:equals(
		"same seed and key replays identically",
		table.concat(seqA, ","),
		table.concat(seqB, ",")
	)
	spec:check(
		"different key yields a different stream",
		table.concat(seqA, ",") ~= table.concat(seqC, ","),
		table.concat(seqC, ",")
	)

	return spec:finish()
end
