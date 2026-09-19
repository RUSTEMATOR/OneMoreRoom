--!strict
-- Run-scoped equipment, the modifiers it confers, and the permanent currency a run
-- pays out when it ends.
--
-- Nothing else knows how an effect is applied. Items declare plain named fields in
-- LootConfig; this service aggregates them, and combat asks for an aggregate. Adding
-- a relic is a data entry, and adding a new KIND of effect is one accessor here plus
-- one read at the point it matters.
--
-- Conditional effects (Blood Charm's "while below 30% health") are evaluated at the
-- moment they are asked for, not folded in at pickup time — a condition baked into a
-- cached total would simply be wrong the instant health changed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local LootConfig = require(ReplicatedStorage.Shared.LootConfig)
local PlayerService = require(script.Parent.PlayerService)
local RunSessionService = require(script.Parent.RunSessionService)
local SaveService = require(script.Parent.SaveService)

local InventoryService = {}

export type Pickup = {
	id: number,
	part: BasePart,
	item: string,
	gold: number,
	taken: boolean,
}

local held: { [Player]: { string } } = {}
local pickups: { [number]: Pickup } = {}
local nextPickupId = 0

InventoryService.onPickedUp = Instance.new("BindableEvent")
InventoryService.onShardsAwarded = Instance.new("BindableEvent")

-- ------------------------------------------------------------------ holdings

function InventoryService.items(player: Player): { string }
	return held[player] or {}
end

function InventoryService.count(player: Player, itemId: string): number
	local n = 0
	for _, id in InventoryService.items(player) do
		if id == itemId then
			n += 1
		end
	end
	return n
end

function InventoryService.has(player: Player, itemId: string): boolean
	return InventoryService.count(player, itemId) > 0
end

-- ----------------------------------------------------------------- modifiers

-- Walks the holdings and folds in every effect whose condition holds right now.
local function fold(
	player: Player,
	field: string,
	identity: number,
	combine: (number, number) -> number
): number
	local total = identity
	local state = PlayerService.get(player)

	for _, itemId in InventoryService.items(player) do
		local item = LootConfig.items[itemId]
		if item == nil then
			continue
		end
		local value = (item.effects :: any)[field]
		if value == nil then
			continue
		end

		local threshold = item.effects.belowHealthFraction
		if threshold ~= nil then
			if state == nil or state.maxHealth <= 0 then
				continue
			end
			if state.health / state.maxHealth >= threshold then
				continue
			end
		end

		total = combine(total, value)
	end

	return total
end

local function multiply(a: number, b: number): number
	return a * b
end

local function add(a: number, b: number): number
	return a + b
end

function InventoryService.outgoingDamageMultiplier(player: Player): number
	return fold(player, "damageMultiplier", 1, multiply)
end

function InventoryService.incomingDamageMultiplier(player: Player): number
	return fold(player, "damageTakenMultiplier", 1, multiply)
end

function InventoryService.staminaRegenMultiplier(player: Player): number
	return fold(player, "staminaRegenMultiplier", 1, multiply)
end

function InventoryService.maxHealthBonus(player: Player): number
	return fold(player, "maxHealthBonus", 0, add)
end

function InventoryService.lootChanceBonus(player: Player): number
	return fold(player, "lootChanceBonus", 0, add)
end

-- The best bonus among everyone present, so in co-op one player's Lucky Coin helps
-- the party rather than only whoever lands the killing blow.
function InventoryService.partyLootChanceBonus(): number
	local best = 0
	for _, state in PlayerService.all() do
		best = math.max(best, InventoryService.lootChanceBonus(state.player))
	end
	return best
end

-- ------------------------------------------------------------------ granting

local function applyMaxHealth(player: Player)
	local bonus = InventoryService.maxHealthBonus(player)
	PlayerService.setMaxHealth(player, CombatConfig.player.maxHealth + bonus)
end

function InventoryService.grant(player: Player, itemId: string): boolean
	if LootConfig.items[itemId] == nil then
		return false
	end
	local list = held[player]
	if list == nil then
		list = {}
		held[player] = list
	end
	table.insert(list, itemId)

	-- Max health is a stored number rather than a derived one, so a bonus has to be
	-- pushed into PlayerService the moment it changes.
	applyMaxHealth(player)
	return true
end

-- Run-scoped: equipment is lost on death, which is the whole point of the split
-- between the run economy and the meta economy.
function InventoryService.clearRun()
	for player in held do
		held[player] = nil
		if player.Parent ~= nil then
			applyMaxHealth(player)
		end
	end
	table.clear(held)
end

-- ------------------------------------------------------------------- pickups

function InventoryService.spawnPickup(
	itemId: string,
	gold: number,
	cframe: CFrame,
	parent: Instance
)
	local item = LootConfig.items[itemId]
	if item == nil then
		return
	end

	local spec = LootConfig.pickup
	local part = Instance.new("Part")
	part.Name = `Loot_{itemId}`
	part.Size = spec.size
	part.Color = LootConfig.colorFor(item.category)
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CFrame = cframe * CFrame.new(0, spec.height, 0)
	part.Parent = parent

	local label = Instance.new("BillboardGui")
	label.Size = UDim2.fromScale(7, 1.2)
	label.StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0)
	label.AlwaysOnTop = true
	label.Parent = part

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = part.Color
	text.TextStrokeTransparency = 0.4
	text.Text = item.displayName
	text.Parent = label

	nextPickupId += 1
	pickups[nextPickupId] = {
		id = nextPickupId,
		part = part,
		item = itemId,
		gold = gold,
		taken = false,
	}
end

function InventoryService.activePickupCount(): number
	local n = 0
	for _, pickup in pickups do
		if not pickup.taken and pickup.part.Parent ~= nil then
			n += 1
		end
	end
	return n
end

function InventoryService.clearPickups()
	for id, pickup in pickups do
		if pickup.part.Parent ~= nil then
			pickup.part:Destroy()
		end
		pickups[id] = nil
	end
	table.clear(pickups)
end

-- Walked into, not pressed: there is no interaction UI until Phase 12, and proximity
-- needs none. Same pattern as the room prize.
local function stepPickups(dt: number)
	local spec = LootConfig.pickup
	for id, pickup in pickups do
		if pickup.taken or pickup.part.Parent == nil then
			pickups[id] = nil
			continue
		end

		pickup.part.CFrame = pickup.part.CFrame * CFrame.Angles(0, spec.spinPerSecond * dt, 0)

		for _, state in PlayerService.all() do
			if not state.alive then
				continue
			end
			local root = state.rootPart
			if root == nil or root.Parent == nil then
				continue
			end
			if (root.Position - pickup.part.Position).Magnitude > spec.radius then
				continue
			end

			pickup.taken = true
			InventoryService.grant(state.player, pickup.item)
			RunSessionService.addGold(pickup.gold)
			InventoryService.onPickedUp:Fire(state.player, pickup.item, pickup.gold)
			pickup.part:Destroy()
			pickups[id] = nil
			break
		end
	end
end

-- -------------------------------------------------------------- soul shards

-- Permanent currency, the half of the economy that survives death. Scaled by depth
-- so a deep failed run still pays for something.
function InventoryService.awardRunEnd(floorsCleared: number): number
	local amount = math.max(0, floorsCleared) * LootConfig.soulShards.perFloorCleared
	if amount <= 0 then
		return 0
	end

	for _, state in PlayerService.all() do
		local data = SaveService.load(state.player)
		data.soulShards += amount
		data.statistics.runsStarted += 0
		if floorsCleared > data.statistics.deepestFloor then
			data.statistics.deepestFloor = floorsCleared
		end
		SaveService.save(state.player)
	end

	InventoryService.onShardsAwarded:Fire(amount, floorsCleared)
	return amount
end

-- ---------------------------------------------------------------- lifecycle

function InventoryService.Init()
	table.clear(held)
	table.clear(pickups)
	nextPickupId = 0
end

function InventoryService.Start()
	RunService.Heartbeat:Connect(stepPickups)

	Players.PlayerRemoving:Connect(function(player)
		held[player] = nil
	end)

	-- Equipment is run-scoped, so a fresh character starts clean.
	PlayerService.onSpawned.Event:Connect(function(player)
		applyMaxHealth(player)
	end)
end

return InventoryService
