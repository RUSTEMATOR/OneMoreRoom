--!strict
-- Procedural swing animation. No uploaded assets: AnimationTrack requires an uploaded
-- AnimationId, and AnimationClipProvider is Studio-only. Timing is what feel comes
-- from, and this keeps all of it in diffable Lua.
--
-- Drives Motor6D.Transform, never C0/C1 — Transform is what the animator writes, so
-- using it means we override the default Animate script rather than fight it.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SwingPose = {}

type Pose = { [string]: CFrame }

type PoseState = {
	character: Model,
	elapsed: number,
	windup: number,
	active: number,
	recovery: number,
	holdUntil: number,
	joints: { [string]: Motor6D },
}

-- Joint name -> the part that owns it. R15.
local JOINT_OWNERS = {
	RightShoulder = "RightUpperArm",
	RightElbow = "RightLowerArm",
	Waist = "UpperTorso",
}

local WINDUP_POSE: Pose = {
	RightShoulder = CFrame.Angles(math.rad(-150), 0, math.rad(35)),
	RightElbow = CFrame.Angles(math.rad(-25), 0, 0),
	Waist = CFrame.Angles(0, math.rad(-35), 0),
}

local SLASH_POSE: Pose = {
	RightShoulder = CFrame.Angles(math.rad(20), 0, math.rad(-50)),
	RightElbow = CFrame.Angles(math.rad(-15), 0, 0),
	Waist = CFrame.Angles(0, math.rad(40), 0),
}

local poses: { [Model]: PoseState } = {}
local bound = false

local function collectJoints(character: Model): { [string]: Motor6D }
	local found: { [string]: Motor6D } = {}
	for jointName, ownerName in JOINT_OWNERS do
		local owner = character:FindFirstChild(ownerName)
		if owner ~= nil then
			local joint = owner:FindFirstChild(jointName)
			if joint ~= nil and joint:IsA("Motor6D") then
				found[jointName] = joint
			end
		end
	end
	return found
end

local function writePose(state: PoseState, from: Pose, to: Pose, alpha: number)
	for jointName, joint in state.joints do
		local a = from[jointName] or CFrame.identity
		local b = to[jointName] or CFrame.identity
		joint.Transform = a:Lerp(b, alpha)
	end
end

local function clearPose(state: PoseState)
	for _, joint in state.joints do
		joint.Transform = CFrame.identity
	end
end

local function step(dt: number)
	local now = os.clock()
	for character, state in poses do
		if character.Parent == nil then
			poses[character] = nil
			continue
		end

		-- Hitstop: freeze the pose clock so the arm stops dead mid-swing and then
		-- resumes. That is what hitstop actually is — frozen animation frames, not a
		-- frozen camera, which would fight the player's own mouse-look.
		if now < state.holdUntil then
			continue
		end

		state.elapsed += dt
		local t = state.elapsed

		if t < state.windup then
			local alpha = TweenService:GetValue(
				t / state.windup,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			)
			writePose(state, {}, WINDUP_POSE, alpha)
		elseif t < state.windup + state.active then
			local alpha = TweenService:GetValue(
				(t - state.windup) / state.active,
				Enum.EasingStyle.Quart,
				Enum.EasingDirection.In
			)
			writePose(state, WINDUP_POSE, SLASH_POSE, alpha)
		elseif t < state.windup + state.active + state.recovery then
			local alpha = TweenService:GetValue(
				(t - state.windup - state.active) / state.recovery,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.Out
			)
			writePose(state, SLASH_POSE, {}, alpha)
		else
			clearPose(state)
			poses[character] = nil
		end
	end
end

export type SwingTiming = { windup: number, active: number, recovery: number }

function SwingPose.play(character: Model?, timing: SwingTiming)
	if character == nil or character.Parent == nil then
		return
	end
	local joints = collectJoints(character)
	if next(joints) == nil then
		return
	end
	poses[character] = {
		character = character,
		elapsed = 0,
		windup = timing.windup,
		active = timing.active,
		recovery = timing.recovery,
		holdUntil = 0,
		joints = joints,
	}
end

function SwingPose.hold(character: Model?, seconds: number)
	if character == nil then
		return
	end
	local state = poses[character]
	if state ~= nil then
		state.holdUntil = os.clock() + seconds
	end
end

function SwingPose.stop(character: Model?)
	if character == nil then
		return
	end
	local state = poses[character]
	if state ~= nil then
		clearPose(state)
		poses[character] = nil
	end
end

function SwingPose.start()
	if bound then
		return
	end
	bound = true
	-- Character + 1 is load-bearing: it runs after the Animator writes Transform, so
	-- our write lands last.
	RunService:BindToRenderStep("OMF_SwingPose", Enum.RenderPriority.Character.Value + 1, step)
end

return SwingPose
