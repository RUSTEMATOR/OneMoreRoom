--!strict
-- The sole CombatFeedback consumer. Everything here is cosmetic and must never gate
-- server logic — if a sound asset is missing or a flash fails, combat still works.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AssetIds = require(ReplicatedStorage.Shared.Assets.AssetIds)
local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local CombatTypes = require(ReplicatedStorage.Shared.CombatTypes)
local Net = require(ReplicatedStorage.Shared.Net)
local SwingPose = require(script.Parent.Parent.Combat.SwingPose)

local FeedbackController = {}

local MAX_HIGHLIGHTS = 24

local feedbackRemote: RemoteEvent
local activeHighlights = 0

-- An empty asset id means "play nothing". A missing sound must degrade silently
-- rather than error a purely cosmetic path, which the QA loop would score as a
-- phase failure.
local function playSound(assetId: string, at: Instance?)
	if assetId == "" or at == nil then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = assetId
	sound.RollOffMaxDistance = CombatConfig.feedback.soundMaxDistance
	sound.Parent = at
	sound:Play()
	Debris:AddItem(sound, 5)
end

local function soundAnchorFor(model: Model?): BasePart?
	if model == nil then
		return nil
	end
	local primary = model.PrimaryPart
	if primary ~= nil then
		return primary
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

-- A Highlight rather than caching and restoring BasePart.Color: it works on any Model,
-- self-cleans, and two overlapping hits cannot corrupt each other's saved colors.
local function flash(target: Model?)
	if target == nil or target.Parent == nil or activeHighlights >= MAX_HIGHLIGHTS then
		return
	end
	activeHighlights += 1

	local highlight = Instance.new("Highlight")
	highlight.FillColor = CombatConfig.feedback.flashColor
	highlight.FillTransparency = 0.4
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = target
	highlight.Parent = target

	-- Released exactly once, by whichever comes first. If the target is destroyed
	-- mid-tween, Completed may never fire, and a counter that only ever goes up would
	-- silently disable flashing for the rest of the session once it hit the cap.
	local released = false
	local function release()
		if released then
			return
		end
		released = true
		activeHighlights -= 1
		highlight:Destroy()
	end

	local tween = TweenService:Create(
		highlight,
		TweenInfo.new(CombatConfig.feedback.flashTime),
		{ FillTransparency = 1 }
	)
	tween.Completed:Connect(release)
	task.delay(CombatConfig.feedback.flashTime + 0.5, release)
	tween:Play()
end

local function onFeedback(payload: CombatTypes.Feedback)
	if typeof(payload) ~= "table" then
		return
	end

	if payload.kind == "SwingStarted" then
		local character = payload.actor.Character
		SwingPose.play(character, {
			windup = payload.windup,
			active = payload.active,
			recovery = payload.recovery,
		})
		playSound(AssetIds.sounds.swordSwing, soundAnchorFor(character))
	elseif payload.kind == "Hit" then
		if payload.actor == Players.LocalPlayer then
			SwingPose.hold(Players.LocalPlayer.Character, CombatConfig.feedback.hitstop)
		end
		flash(payload.target)
		playSound(AssetIds.sounds.swordImpact, soundAnchorFor(payload.target))
	elseif payload.kind == "Dodged" then
		playSound(AssetIds.sounds.swordSwing, soundAnchorFor(payload.actor.Character))
	elseif payload.kind == "Died" then
		SwingPose.stop(payload.actor)
		playSound(AssetIds.sounds.playerDeath, soundAnchorFor(payload.actor))
	elseif payload.kind == "RangedShot" then
		-- "RangedShot"/"RangedImpact" are the wire names; the sentry's bolt is what a
		-- player sees and hears.
		playSound(AssetIds.sounds.sentryBoltFire, soundAnchorFor(payload.actor))
	elseif payload.kind == "RangedImpact" then
		-- The same reaction a sword hit gets on the receiving end: a flash and a
		-- hitstop when it is the local player who was struck. A bolt should not feel
		-- like a lesser hit than a sword just because it came from further away.
		if payload.target == Players.LocalPlayer.Character then
			SwingPose.hold(Players.LocalPlayer.Character, CombatConfig.feedback.hitstop)
		end
		flash(payload.target)
		playSound(AssetIds.sounds.sentryBoltImpact, soundAnchorFor(payload.target))
	elseif payload.kind == "Detonation" then
		-- No per-victim flash here: unlike RangedImpact this payload names no
		-- target, because a blast can catch several players or none. The boom
		-- itself is the signal, audible whether or not it actually hit.
		playSound(AssetIds.sounds.cultistDetonation, soundAnchorFor(payload.actor))
	end
end

function FeedbackController.Init()
	feedbackRemote = Net.event("CombatFeedback")
end

function FeedbackController.Start()
	SwingPose.start()
	feedbackRemote.OnClientEvent:Connect(onFeedback)
end

return FeedbackController
