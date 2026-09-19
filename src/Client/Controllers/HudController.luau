--!strict
-- Run HUD: health and stamina, bottom left. Built from Lua rather than a StarterGui
-- instance — StarterGui is deliberately absent from default.project.json and should
-- stay absent, because UI iterates most and so needs diffs most.
--
-- Reads attributes on the Player, not a remote. Server-set attributes replicate
-- automatically and are read-only to clients, which is exactly the property we want,
-- and stamina regen over a remote would be ~60 fires/sec/player versus ~4 as a
-- change-thresholded attribute. Bar width interpolates for smoothing only, never
-- authority.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)

local HudController = {}

local BAR_WIDTH = 260
local BAR_HEIGHT = 18
local LERP_SPEED = 12

local player = Players.LocalPlayer

local healthFill: Frame
local staminaFill: Frame
local healthLabel: TextLabel
local floorLabel: TextLabel
local seedLabel: TextLabel
local runStateChanged: RemoteEvent

local shownHealth = 1
local shownStamina = 1

local function ratio(valueKey: string, maxKey: string): number
	local value = player:GetAttribute(valueKey)
	local maximum = player:GetAttribute(maxKey)
	if typeof(value) ~= "number" or typeof(maximum) ~= "number" or maximum <= 0 then
		return 1
	end
	return math.clamp(value / maximum, 0, 1)
end

local function makeBar(parent: Instance, y: number, color: Color3): (Frame, TextLabel)
	local track = Instance.new("Frame")
	track.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
	track.Position = UDim2.fromOffset(0, y)
	track.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
	track.BackgroundTransparency = 0.25
	track.BorderSizePixel = 0
	track.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = track

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = fill

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.5
	label.Text = ""
	label.ZIndex = 2
	label.Parent = track

	return fill, label
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "OMF_Hud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	local root = Instance.new("Frame")
	root.Name = "Vitals"
	root.AnchorPoint = Vector2.new(0, 1)
	root.Position = UDim2.new(0, 24, 1, -24)
	root.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT * 2 + 6)
	root.BackgroundTransparency = 1
	root.Parent = gui

	healthFill, healthLabel = makeBar(root, 0, Color3.fromRGB(196, 62, 52))
	staminaFill = makeBar(root, BAR_HEIGHT + 6, Color3.fromRGB(214, 160, 54))

	-- Floor and seed, top centre. These arrive over RunStateChanged rather than as
	-- attributes: they change once per floor, not per frame, and the remote was
	-- already declared in Net for exactly this.
	local runBox = Instance.new("Frame")
	runBox.Name = "RunState"
	runBox.AnchorPoint = Vector2.new(0.5, 0)
	runBox.Position = UDim2.new(0.5, 0, 0, 18)
	runBox.Size = UDim2.fromOffset(280, 44)
	runBox.BackgroundTransparency = 1
	runBox.Parent = gui

	floorLabel = Instance.new("TextLabel")
	floorLabel.Size = UDim2.new(1, 0, 0, 26)
	floorLabel.BackgroundTransparency = 1
	floorLabel.Font = Enum.Font.GothamBold
	floorLabel.TextSize = 22
	floorLabel.TextColor3 = Color3.fromRGB(240, 238, 232)
	floorLabel.TextStrokeTransparency = 0.5
	floorLabel.Text = ""
	floorLabel.Parent = runBox

	-- The seed is shown so a bug report can carry it without digging in the log.
	seedLabel = Instance.new("TextLabel")
	seedLabel.Position = UDim2.fromOffset(0, 26)
	seedLabel.Size = UDim2.new(1, 0, 0, 16)
	seedLabel.BackgroundTransparency = 1
	seedLabel.Font = Enum.Font.Code
	seedLabel.TextSize = 13
	seedLabel.TextColor3 = Color3.fromRGB(168, 172, 180)
	seedLabel.TextStrokeTransparency = 0.7
	seedLabel.Text = ""
	seedLabel.Parent = runBox
end

type RunSnapshot = {
	active: boolean,
	floor: number,
	seed: number,
	gold: number,
	template: string?,
}

local function onRunState(snapshot: RunSnapshot)
	if typeof(snapshot) ~= "table" then
		return
	end
	if not snapshot.active then
		floorLabel.Text = ""
		seedLabel.Text = ""
		return
	end
	local name = snapshot.template or ""
	floorLabel.Text = if name ~= ""
		then `FLOOR {snapshot.floor}  ·  {name}`
		else `FLOOR {snapshot.floor}`
	seedLabel.Text = `seed {snapshot.seed}  ·  {snapshot.gold} gold`
end

local function updateLabel()
	local value = player:GetAttribute("OMF_Health")
	local maximum = player:GetAttribute("OMF_MaxHealth")
	if typeof(value) == "number" and typeof(maximum) == "number" then
		healthLabel.Text = `{math.floor(value + 0.5)} / {math.floor(maximum + 0.5)}`
	end
end

local function step(dt: number)
	local alpha = math.clamp(dt * LERP_SPEED, 0, 1)
	shownHealth += (ratio("OMF_Health", "OMF_MaxHealth") - shownHealth) * alpha
	shownStamina += (ratio("OMF_Stamina", "OMF_MaxStamina") - shownStamina) * alpha
	healthFill.Size = UDim2.fromScale(shownHealth, 1)
	staminaFill.Size = UDim2.fromScale(shownStamina, 1)
end

function HudController.Init()
	runStateChanged = Net.event("RunStateChanged")
end

function HudController.Start()
	build()
	updateLabel()
	shownHealth = ratio("OMF_Health", "OMF_MaxHealth")
	shownStamina = ratio("OMF_Stamina", "OMF_MaxStamina")

	player:GetAttributeChangedSignal("OMF_Health"):Connect(updateLabel)
	player:GetAttributeChangedSignal("OMF_MaxHealth"):Connect(updateLabel)
	RunService.RenderStepped:Connect(step)
	runStateChanged.OnClientEvent:Connect(onRunState)
end

return HudController
