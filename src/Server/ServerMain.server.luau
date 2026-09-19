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
	"RunSessionService",
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

-- Machine-readable boot signal for the QA loop. The print below is for humans only and
-- is never asserted on: a stray log line could fake it, an attribute cannot.
game:SetAttribute("OMF_ServerReady", true)
print(`[OMF] server boot ok — {#ORDER} services, build {BuildStamp.id}`)
