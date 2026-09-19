--!strict
-- Owns per-player vitals and the character lifecycle. Keyed by player and plural from
-- day one so Phase 14 co-op tunes scaling rather than rearchitecting.
--
-- This service requires no other service, ever. ServerMain requires everything at top
-- level, so a top-level cycle is a hard boot error — PlayerService sits at the root of
-- the dependency DAG and stays there. Services that need to react to the character
-- lifecycle connect their own CharacterAdded/CharacterRemoving and compare `generation`.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local CombatTypes = require(ReplicatedStorage.Shared.CombatTypes)

local PlayerService = {}

export type PlayerState = {
	player: Player,
	health: number,
	maxHealth: number,
	stamina: number,
	maxStamina: number,

	-- Incremented on every character bind AND unbind. Every deferred callback captures
	-- it and re-checks before acting; that single counter is what makes task.delay safe.
	generation: number,
	character: Model?,
	humanoid: Humanoid?,
	rootPart: BasePart?,
	alive: boolean,
	deathHandled: boolean,
}

local states: { [Player]: PlayerState } = {}

-- Replicated read-only to clients. The HUD reads these instead of a remote: stamina
-- regen over a remote would be ~60 fires/sec/player, versus ~4 as a thresholded
-- attribute. Prefix matches the existing OMF_ServerReady convention.
local function mirror(state: PlayerState)
	local player = state.player
	player:SetAttribute("OMF_Health", state.health)
	player:SetAttribute("OMF_MaxHealth", state.maxHealth)
	player:SetAttribute("OMF_Stamina", state.stamina)
	player:SetAttribute("OMF_MaxStamina", state.maxStamina)
	player:SetAttribute("OMF_Alive", state.alive)

	local humanoid = state.humanoid
	if humanoid ~= nil and humanoid.Parent ~= nil then
		humanoid.Health = state.health
	end
end

local function newState(player: Player): PlayerState
	return {
		player = player,
		health = CombatConfig.player.maxHealth,
		maxHealth = CombatConfig.player.maxHealth,
		stamina = CombatConfig.stamina.max,
		maxStamina = CombatConfig.stamina.max,
		generation = 0,
		character = nil,
		humanoid = nil,
		rootPart = nil,
		alive = false,
		deathHandled = false,
	}
end

local spawnCharacter: (player: Player) -> ()

local function bindCharacter(player: Player, character: Model, gen: number)
	local state = states[player]
	if state == nil or state.generation ~= gen then
		return
	end

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid == nil or state.generation ~= gen then
		return
	end

	-- CharacterAdded fires BEFORE the character is parented to Workspace, and
	-- Humanoid.Died only fires once the Humanoid is a Workspace descendant. Wait for
	-- parenting before connecting anything, re-checking the generation after each yield.
	while character.Parent == nil do
		character.AncestryChanged:Wait()
		if state.generation ~= gen then
			return
		end
	end

	local rootPart = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if rootPart == nil or state.generation ~= gen then
		return
	end

	-- A ForceField silently blocks Humanoid:TakeDamage. We write Health directly so it
	-- would not bite us, but a spawn bubble is wrong for this game and Phase 2 reuses
	-- this path.
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("ForceField") then
			descendant:Destroy()
		end
	end

	-- Backstop in case the StarterCharacterScripts.Health node regresses out of
	-- default.project.json: default regen would creep Humanoid.Health between our
	-- mirror writes and drift the overhead bar off the authoritative number.
	local defaultRegen = character:FindFirstChild("Health")
	if defaultRegen ~= nil and defaultRegen:IsA("Script") then
		defaultRegen:Destroy()
	end

	state.character = character
	state.humanoid = humanoid
	state.rootPart = rootPart
	state.alive = true
	state.deathHandled = false
	state.health = state.maxHealth
	state.stamina = state.maxStamina

	humanoid.MaxHealth = state.maxHealth
	humanoid.WalkSpeed = CombatConfig.player.walkSpeed
	mirror(state)

	humanoid.Died:Connect(function()
		PlayerService.handleDeath(player, gen)
	end)
end

function PlayerService.get(player: Player): PlayerState?
	return states[player]
end

function PlayerService.all(): { PlayerState }
	local list = {}
	for _, state in states do
		table.insert(list, state)
	end
	return list
end

function PlayerService.generation(player: Player): number
	local state = states[player]
	return if state ~= nil then state.generation else -1
end

-- True only when there is a live, parented character to act on.
function PlayerService.isActionable(player: Player): boolean
	local state = states[player]
	if state == nil or not state.alive then
		return false
	end
	local character = state.character
	return character ~= nil and character.Parent ~= nil and state.humanoid ~= nil
end

function PlayerService.setHealth(player: Player, value: number)
	local state = states[player]
	if state == nil then
		return
	end
	state.health = math.clamp(value, 0, state.maxHealth)
	mirror(state)
end

function PlayerService.setStamina(player: Player, value: number)
	local state = states[player]
	if state == nil then
		return
	end
	state.stamina = math.clamp(value, 0, state.maxStamina)
	mirror(state)
end

function PlayerService.addStamina(player: Player, amount: number)
	local state = states[player]
	if state == nil then
		return
	end
	state.stamina = math.clamp(state.stamina + amount, 0, state.maxStamina)
	mirror(state)
end

-- Atomic check-and-deduct. The only place stamina is ever subtracted, so a rejected
-- spend can never partially drain the pool.
function PlayerService.spendStamina(player: Player, amount: number): boolean
	local state = states[player]
	if state == nil or state.stamina < amount then
		return false
	end
	state.stamina -= amount
	mirror(state)
	return true
end

-- Returns dealt, rejectReason. I-frames are NOT checked here — CombatService checks
-- them at application time, because this is also the path environment damage uses.
function PlayerService.applyDamage(
	player: Player,
	amount: number,
	_info: CombatTypes.DamageInfo
): (number, string?)
	local state = states[player]
	if state == nil then
		return 0, "nostate"
	end
	if not state.alive or state.health <= 0 then
		return 0, "dead"
	end

	local before = state.health
	state.health = math.clamp(state.health - amount, 0, state.maxHealth)
	local dealt = before - state.health
	mirror(state)

	if state.health <= 0 then
		PlayerService.handleDeath(player, state.generation)
	end
	return dealt, nil
end

-- Idempotent, with three entry points into this one body: Humanoid.Died (normal), the
-- CombatService heartbeat backstop (covers Died never firing when the Dead state is
-- disabled), and applyDamage reaching zero. Multi-fire is free; no-fire is covered.
function PlayerService.handleDeath(player: Player, gen: number)
	local state = states[player]
	if state == nil or state.generation ~= gen or state.deathHandled then
		return
	end

	state.deathHandled = true
	state.alive = false
	state.health = 0
	mirror(state)

	local humanoid = state.humanoid
	if humanoid ~= nil and humanoid.Parent ~= nil and humanoid.Health > 0 then
		humanoid.Health = 0
	end

	PlayerService.onDied:Fire(player, state.character)

	task.delay(CombatConfig.player.respawnDelay, function()
		-- Stale-timer guard: a task.delay outlives a character, and the generation id
		-- is what makes it safe to let this one fire at all.
		local current = states[player]
		if current == nil or current.generation ~= gen or player.Parent == nil then
			return
		end
		spawnCharacter(player)
	end)
end

-- A BindableEvent rather than a direct call, because PlayerService must not require
-- any other service. CombatService and TrainingDummyService subscribe.
PlayerService.onDied = Instance.new("BindableEvent")
PlayerService.onSpawned = Instance.new("BindableEvent")

function spawnCharacter(player: Player)
	if player.Parent == nil then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			player:LoadCharacterAsync()
		end)
		if not ok then
			warn(`[OMF] LoadCharacterAsync failed for {player.Name}: {err}`)
			return
		end
		PlayerService.onSpawned:Fire(player)
	end)
end

local function onPlayerAdded(player: Player)
	if states[player] ~= nil then
		return
	end
	states[player] = newState(player)

	player.CharacterAdded:Connect(function(character)
		local state = states[player]
		if state == nil then
			return
		end
		state.generation += 1
		local gen = state.generation
		task.spawn(bindCharacter, player, character, gen)
	end)

	player.CharacterRemoving:Connect(function()
		local state = states[player]
		if state == nil then
			return
		end
		-- This single line invalidates every pending task.delay for this character.
		state.generation += 1
		state.alive = false
		state.character = nil
		state.humanoid = nil
		state.rootPart = nil
	end)

	-- Studio Play can parent a character before this handler exists.
	local existing = player.Character
	if existing ~= nil then
		states[player].generation += 1
		task.spawn(bindCharacter, player, existing, states[player].generation)
	else
		spawnCharacter(player)
	end
end

local function onPlayerRemoving(player: Player)
	local state = states[player]
	if state ~= nil then
		state.generation += 1
	end
	states[player] = nil
end

function PlayerService.Init()
	table.clear(states)
	-- Every spawn goes through one path we own, because Phase 13's die -> lobby -> buy
	-- -> new run loop needs the server deciding when and where you respawn.
	Players.CharacterAutoLoads = false
end

function PlayerService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return PlayerService
