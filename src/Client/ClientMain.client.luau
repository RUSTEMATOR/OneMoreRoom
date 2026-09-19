--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Remotes")

local folder = script.Parent:WaitForChild("Controllers")

local ORDER = {
	"InputController",
	"HudController",
	"FeedbackController",
	"CameraController",
}

type Controller = {
	Init: (() -> ())?,
	Start: (() -> ())?,
}

local controllers: { [string]: Controller } = {}

for _, name in ORDER do
	controllers[name] = require(folder[name]) :: Controller
end

for _, name in ORDER do
	local init = controllers[name].Init
	if init then
		init()
	end
end

for _, name in ORDER do
	local start = controllers[name].Start
	if start then
		start()
	end
end

Players.LocalPlayer:SetAttribute("OMF_ClientReady", true)
print("[OMF] client boot ok")
