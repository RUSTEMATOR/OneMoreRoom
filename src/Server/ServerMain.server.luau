--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BuildStamp = require(ReplicatedStorage.Shared.BuildStamp)
local Net = require(ReplicatedStorage.Shared.Net)

-- Explicit and ordered, deliberately not :GetChildren(). Boot order is part of the
-- contract: it shows up in diffs, a typo fails loudly at require time, and it is
-- reproducible run to run.
local ORDER = {
	"PlayerService",
	"SaveService",
	"FloorService",
	"CombatService",
	"TrainingDummyService",
	"RunSessionService",
	"EnemyService",
	"RoomService",
}

type Service = {
	Init: (() -> ())?,
	Start: (() -> ())?,
}

local folder = ServerScriptService:WaitForChild("Services")
local services: { [string]: Service } = {}

Net.buildRemotes()

for _, name in ORDER do
	services[name] = require(folder[name]) :: Service
end

for _, name in ORDER do
	local init = services[name].Init
	if init then
		init()
	end
end

for _, name in ORDER do
	local start = services[name].Start
	if start then
		start()
	end
end

-- The QA loop cannot just require the spec suite from outside: the Studio MCP's
-- execute_luau runs in its own Lua VM with its own module cache, so a spec required
-- from there gets fresh, un-booted copies of every service — PlayerService.all() comes
-- back empty while the real one has players. This BindableFunction's callback is
-- created HERE, in the boot context, so invoking it from anywhere runs the suite
-- against the services that are actually running.
--
-- It returns a JSON string rather than a table, so the result survives crossing a VM
-- boundary regardless of how the caller reached us.
local specRunner = Instance.new("BindableFunction")
specRunner.Name = "OMF_RunSpecs"
specRunner.OnInvoke = function()
	local HttpService = game:GetService("HttpService")
	local ServerStorage = game:GetService("ServerStorage")
	local ok, result = pcall(function()
		return require(ServerStorage.Specs.RunAll)()
	end)
	if not ok then
		return HttpService:JSONEncode({ allPassed = false, harnessError = tostring(result) })
	end
	return HttpService:JSONEncode(result)
end
specRunner.Parent = game:GetService("ServerStorage")

-- Machine-readable boot signal for the QA loop. The print below is for humans only and
-- is never asserted on: a stray log line could fake it, an attribute cannot.
game:SetAttribute("OMF_ServerReady", true)
print(`[OMF] server boot ok — {#ORDER} services, build {BuildStamp.id}`)
