--!strict
-- The cyborg reskin: every enemy kind, plus the boss, wraps a Creator Store texture
-- over its rig's material and colour.
--
-- Not a roadmap phase, same footing as Archer/Cultist.luau. Deliberately pure: nothing
-- here needs a live player or a world. `EnemyBuilder.build` returns an unparented
-- Model, so the whole thing is buildable and inspectable offline, the same reasoning
-- that makes FloorPlan's golden-hash test arithmetic rather than a playthrough.
--
-- What this asserts is the WIRING -- every kind that has a textureId actually gets a
-- Decal, on all four side faces, carrying exactly the id AssetIds names for it. It
-- does not and cannot assert that the texture looks good; that is a manual call.
--
-- Also covers the fix for the report that prompted this file's rewrite: "they don't
-- wear anything" -- a torso decal on a single box still reads as a textured crate,
-- not a body. EnemyBuilder now gives every kind four limbs; this asserts they exist,
-- are jointed to the torso, and are not the sole physical collider.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Spec = require(script.Parent.Spec)

local AssetIds = require(ReplicatedStorage.Shared.Assets.AssetIds)
local BossConfig = require(ReplicatedStorage.Shared.BossConfig)
local EnemyConfig = require(ReplicatedStorage.Shared.EnemyConfig)
local EnemyBuilder = require(ServerScriptService.Combat.EnemyBuilder)

local FACES = { "Front", "Back", "Left", "Right" }

-- Shared by every kind checked below, including the boss, which does not go through
-- EnemyBuilder.build(kind) -- it calls buildFromRig directly with BossConfig's own
-- maxHealth/walkSpeed, so the model is supplied rather than built from a kind string.
local function checkSkin(spec: any, label: string, model: Model, expectedTexture: string)
	local torso = model:FindFirstChild("Torso")
	spec:truthy(`{label} builds a Torso`, torso)
	if torso == nil or not torso:IsA("BasePart") then
		return
	end

	local skins: { Decal } = {}
	for _, child in torso:GetChildren() do
		if child:IsA("Decal") then
			table.insert(skins, child)
		end
	end
	spec:equals(`{label} wraps exactly four side faces`, #skins, 4)

	local seenFaces: { [string]: boolean } = {}
	for _, skin in skins do
		spec:equals(`{label} skin carries the configured texture id`, skin.Texture, expectedTexture)
		seenFaces[skin.Face.Name] = true
	end
	for _, faceName in FACES do
		spec:truthy(`{label} covers the {faceName} face`, seenFaces[faceName])
	end

	-- The signal that actually reads at a glance across a room is the base colour,
	-- not the texture -- a texture failing to load must never leave the part looking
	-- like nothing was configured for it at all.
	spec:check(
		`{label} keeps its base colour independent of the texture`,
		torso.Color ~= Color3.fromRGB(255, 255, 255),
		tostring(torso.Color)
	)

	-- A body, not a crate: four limbs, each jointed to the torso and none of them
	-- fighting it for collision.
	local limbJoints = { "LeftShoulder", "RightShoulder", "LeftHip", "RightHip" }
	local limbNames = { "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
	for _, limbName in limbNames do
		local limb = model:FindFirstChild(limbName)
		spec:truthy(`{label} has a {limbName}`, limb)
		if limb ~= nil and limb:IsA("BasePart") then
			spec:check(`{label}'s {limbName} does not collide`, limb.CanCollide == false)
		end
	end
	for _, jointName in limbJoints do
		local joint = torso:FindFirstChild(jointName)
		spec:truthy(`{label} has a {jointName} joint`, joint)
		if joint ~= nil and joint:IsA("Motor6D") then
			spec:equals(`{label}'s {jointName} is welded to the torso`, joint.Part0, torso)
		end
	end
end

return function()
	local spec = Spec.new("EnemySkins")

	local kinds = {
		{ key = "Skeleton", label = "Rust Husk", textureKey = "rustHusk" },
		{ key = "Archer", label = "Signal Sentry", textureKey = "signalSentry" },
		{ key = "Cultist", label = "Signal Cultist", textureKey = "signalCultist" },
		{ key = "SkeletonElite", label = "Chrome Husk", textureKey = "chromeHusk" },
	}

	for _, entry in kinds do
		spec:truthy(
			`{entry.label}'s config carries a textureId`,
			EnemyConfig.kinds[entry.key].rig.textureId
		)
		spec:equals(
			`{entry.label}'s textureId matches AssetIds.textures.{entry.textureKey}`,
			EnemyConfig.kinds[entry.key].rig.textureId,
			AssetIds.textures[entry.textureKey]
		)

		local ok, model = pcall(EnemyBuilder.build, entry.key)
		if ok and model ~= nil then
			checkSkin(spec, entry.label, model, AssetIds.textures[entry.textureKey])
			model:Destroy()
		else
			spec:check(`{entry.label} builds without error`, false, model)
		end
	end

	-- ----------------------------------------------------- the boss

	local warden = BossConfig.bosses.Warden
	spec:truthy("the Warden's config carries a textureId", warden.rig.textureId)
	spec:equals(
		"the Warden's textureId matches AssetIds.textures.theWarden",
		warden.rig.textureId,
		AssetIds.textures.theWarden
	)

	local ok, bossModel =
		pcall(EnemyBuilder.buildFromRig, "Warden", warden.rig, warden.maxHealth, 12)
	if ok and bossModel ~= nil then
		checkSkin(spec, "The Warden", bossModel, AssetIds.textures.theWarden)
		bossModel:Destroy()
	else
		spec:check("the Warden builds without error", false, bossModel)
	end

	return spec:finish()
end
