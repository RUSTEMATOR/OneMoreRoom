--!strict
-- The meta half of the economy: Soul Shards spent on permanent upgrades that survive
-- death, and the lobby shrines you spend them at.
--
-- This is the service that closes the loop the MVP gate is defined by — die, return
-- to the lobby, buy something, start again stronger.
--
-- Purchases are server-authoritative in the strongest sense available: there is no
-- remote at all. You walk into a shrine, and the server decides. A client cannot even
-- ask for a specific upgrade, let alone a specific price.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)
local PlayerService = require(script.Parent.PlayerService)
local SaveService = require(script.Parent.SaveService)
local WorldFolders = require(script.Parent.Parent.World.WorldFolders)

local ProgressionService = {}

type Shrine = {
	upgradeId: string,
	part: BasePart,
	label: TextLabel,
}

local shrines: { Shrine } = {}
local lastPurchaseAt: { [Player]: number } = {}

ProgressionService.onPurchased = Instance.new("BindableEvent")

-- ------------------------------------------------------------------- levels

function ProgressionService.levelOf(player: Player, upgradeId: string): number
	local data = SaveService.load(player)
	return data.permanentUpgrades[upgradeId] or 0
end

function ProgressionService.nextCost(player: Player, upgradeId: string): number
	return UpgradeConfig.costFor(upgradeId, ProgressionService.levelOf(player, upgradeId))
end

function ProgressionService.isMaxed(player: Player, upgradeId: string): boolean
	local upgrade = UpgradeConfig.upgrades[upgradeId]
	if upgrade == nil then
		return true
	end
	return ProgressionService.levelOf(player, upgradeId) >= upgrade.maxLevel
end

-- ---------------------------------------------------------------- modifiers

-- Folded from levels the same way relics are folded from holdings, so the two
-- economies compose without either knowing about the other.
local function fold(player: Player, field: string): number
	local total = 0
	local data = SaveService.load(player)
	for _, id in UpgradeConfig.pool do
		local upgrade = UpgradeConfig.upgrades[id]
		local perLevel = (upgrade :: any)[field]
		if perLevel == nil then
			continue
		end
		total += perLevel * (data.permanentUpgrades[id] or 0)
	end
	return total
end

function ProgressionService.maxHealthMultiplier(player: Player): number
	return 1 + fold(player, "healthPercentPerLevel")
end

function ProgressionService.damageMultiplier(player: Player): number
	return 1 + fold(player, "damagePercentPerLevel")
end

function ProgressionService.goldMultiplier(player: Player): number
	return 1 + fold(player, "goldPercentPerLevel")
end

function ProgressionService.startingRelicCount(player: Player): number
	return math.floor(fold(player, "startingRelicsPerLevel") + 0.5)
end

-- The best multiplier present, so in co-op a party is not held back to its least
-- upgraded member on shared values like gold.
function ProgressionService.partyGoldMultiplier(): number
	local best = 1
	for _, state in PlayerService.all() do
		best = math.max(best, ProgressionService.goldMultiplier(state.player))
	end
	return best
end

-- ---------------------------------------------------------------- purchase

-- Returns ok, reason. The reasons are the whole testability story, exactly as
-- CombatService's are.
function ProgressionService.purchase(player: Player, upgradeId: string): (boolean, string?)
	local upgrade = UpgradeConfig.upgrades[upgradeId]
	if upgrade == nil then
		return false, "unknown"
	end

	local data = SaveService.load(player)
	local level = data.permanentUpgrades[upgradeId] or 0
	if level >= upgrade.maxLevel then
		return false, "maxed"
	end

	local cost = UpgradeConfig.costFor(upgradeId, level)
	if data.soulShards < cost then
		return false, "shards"
	end

	data.soulShards -= cost
	data.permanentUpgrades[upgradeId] = level + 1
	SaveService.save(player)

	ProgressionService.onPurchased:Fire(player, upgradeId, level + 1, cost)
	return true, nil
end

-- ------------------------------------------------------------------ shrines

local function shrineLabelText(player: Player?, upgradeId: string): string
	local upgrade = UpgradeConfig.upgrades[upgradeId]
	if player == nil then
		return `{upgrade.displayName}\n{upgrade.description}`
	end
	local level = ProgressionService.levelOf(player, upgradeId)
	if level >= upgrade.maxLevel then
		return `{upgrade.displayName}  MAX\n{upgrade.description}`
	end
	local cost = UpgradeConfig.costFor(upgradeId, level)
	local shards = SaveService.load(player).soulShards
	return `{upgrade.displayName}  Lv {level}/{upgrade.maxLevel}\n{upgrade.description}\n{cost} shards  (you have {shards})`
end

local function buildShrines()
	if not UpgradeConfig.shrine.enabled then
		return
	end
	local static = WorldFolders.static()
	local stale = static:FindFirstChild("Shrines")
	if stale ~= nil then
		stale:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "Shrines"
	folder.Parent = static

	local spec = UpgradeConfig.shrine
	table.clear(shrines)

	for index, upgradeId in UpgradeConfig.pool do
		local part = Instance.new("Part")
		part.Name = `Shrine_{upgradeId}`
		part.Size = spec.size
		part.Anchored = true
		part.CanCollide = true
		part.Material = Enum.Material.Slate
		part.Color = spec.baseColor
		part.Position = spec.origin + Vector3.new(0, spec.size.Y / 2, -(index - 1) * spec.spacing)
		part.Parent = folder

		local crystal = Instance.new("Part")
		crystal.Name = "Crystal"
		crystal.Size = Vector3.new(1.4, 1.4, 1.4)
		crystal.Anchored = true
		crystal.CanCollide = false
		crystal.CanQuery = false
		crystal.Material = Enum.Material.Neon
		crystal.Color = spec.litColor
		crystal.CFrame = CFrame.new(part.Position + Vector3.new(0, spec.size.Y / 2 + 1.2, 0))
		crystal.Parent = part

		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromScale(11, 3.4)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, spec.size.Y / 2 + 3.4, 0)
		billboard.AlwaysOnTop = true
		billboard.Parent = part

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamMedium
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(236, 232, 244)
		label.TextStrokeTransparency = 0.4
		label.Text = shrineLabelText(nil, upgradeId)
		label.Parent = billboard

		table.insert(shrines, { upgradeId = upgradeId, part = part, label = label })
	end
end

function ProgressionService.shrineCount(): number
	return #shrines
end

function ProgressionService.refreshShrines()
	local viewer = PlayerService.all()[1]
	local player = if viewer ~= nil then viewer.player else nil
	for _, shrine in shrines do
		shrine.label.Text = shrineLabelText(player, shrine.upgradeId)
		local crystal = shrine.part:FindFirstChild("Crystal")
		if crystal ~= nil and crystal:IsA("BasePart") and player ~= nil then
			local affordable = not ProgressionService.isMaxed(player, shrine.upgradeId)
				and SaveService.load(player).soulShards
					>= ProgressionService.nextCost(player, shrine.upgradeId)
			crystal.Color = if affordable
				then UpgradeConfig.shrine.litColor
				else UpgradeConfig.shrine.spentColor
		end
	end
end

-- Polled, like every other proximity interaction here, and never .Touched — that is
-- tied to network ownership and a client can fire it, which for a SHOP would be an
-- exploit rather than a curiosity.
local function stepShrines()
	if #shrines == 0 then
		return
	end
	local now = os.clock()
	local spec = UpgradeConfig.shrine

	for _, state in PlayerService.all() do
		local root = state.rootPart
		if root == nil or root.Parent == nil or not state.alive then
			continue
		end
		if now - (lastPurchaseAt[state.player] or -math.huge) < spec.purchaseCooldown then
			continue
		end

		for _, shrine in shrines do
			if (root.Position - shrine.part.Position).Magnitude > spec.radius then
				continue
			end
			local ok = ProgressionService.purchase(state.player, shrine.upgradeId)
			-- Stamp the cooldown either way. Standing on a shrine you cannot afford
			-- should not re-test it every frame for the rest of the session.
			lastPurchaseAt[state.player] = now
			if ok then
				ProgressionService.refreshShrines()
			end
			break
		end
	end
end

-- ---------------------------------------------------------------- lifecycle

function ProgressionService.Init()
	table.clear(shrines)
	table.clear(lastPurchaseAt)
end

function ProgressionService.Start()
	RunService.Heartbeat:Connect(stepShrines)

	Players.PlayerRemoving:Connect(function(player)
		lastPurchaseAt[player] = nil
	end)

	-- Deferred: Start must not yield, and the shrines want a settled world before
	-- their anchored parts are placed.
	task.spawn(function()
		task.wait(0.7)
		buildShrines()
		ProgressionService.refreshShrines()
	end)
end

return ProgressionService
