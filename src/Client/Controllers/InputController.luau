--!strict
-- Sends intent, nothing else. Both remotes are argument-free: there is no target list,
-- no direction and no timing to spoof.
--
-- No client-side gating on cooldown, stamina or death. Rejection is the server's job,
-- and a client that predicts a rejection and gets it wrong produces a desync with no
-- upside.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local InputController = {}

-- Default Roblox scripts bind at priority 2000.
local PRIORITY = 2500

local requestAttack: RemoteEvent
local requestDodge: RemoteEvent

local function hasLiveCharacter(): boolean
	local character = Players.LocalPlayer.Character
	if character == nil or character.Parent == nil then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Two disciplines make the right-click binding safe:
--   1. Return Pass from EVERY branch. A bare `return` (nil) sinks the input, and the
--      default camera would stop panning.
--   2. Act only on Begin. Firing on End too would queue a second dodge at the end of
--      a right-click-drag camera pan.
-- The default camera reads right-mouse through UserInputService, not CAS, so it is
-- doubly insulated from us.
local function onAttack(
	_action: string,
	inputState: Enum.UserInputState,
	_input: InputObject
): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin and hasLiveCharacter() then
		requestAttack:FireServer()
	end
	return Enum.ContextActionResult.Pass
end

local function onDodge(
	_action: string,
	inputState: Enum.UserInputState,
	_input: InputObject
): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin and hasLiveCharacter() then
		requestDodge:FireServer()
	end
	return Enum.ContextActionResult.Pass
end

function InputController.Init()
	requestAttack = Net.event("RequestAttack")
	requestDodge = Net.event("RequestDodge")
end

function InputController.Start()
	-- createTouchButton is false on both: Phase 12 owns mobile.
	ContextActionService:BindActionAtPriority(
		"OMF_Attack",
		onAttack,
		false,
		PRIORITY,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonR2
	)
	ContextActionService:BindActionAtPriority(
		"OMF_Dodge",
		onDodge,
		false,
		PRIORITY,
		Enum.UserInputType.MouseButton2,
		Enum.KeyCode.ButtonB
	)
end

return InputController
