--!strict
-- Server-authoritative combat. Clients send intent via RequestAttack / RequestDodge --
-- both argument-free, so there is nothing to validate and nothing to spoof. Damage,
-- targets, timing, stamina, i-frames and death are all derived here.
--
-- Everything is driven by ONE Heartbeat connection. That is not an optimization: it
-- means os.clock() is read once per frame in one place, so phase transitions, dodge
-- expiry, stamina regen and the death backstop cannot disagree about "now". It also
-- means this service contains zero task.delay calls, which removes the entire
-- stale-timer class from the combat path.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local CombatTypes = require(ReplicatedStorage.Shared.CombatTypes)
local Net = require(ReplicatedStorage.Shared.Net)
local WeaponStats = require(ReplicatedStorage.Shared.WeaponStats)
local InventoryService = require(script.Parent.InventoryService)
local PlayerService = require(script.Parent.PlayerService)
local WeaponBuilder = require(script.Parent.Parent.Combat.WeaponBuilder)

local CombatService = {}

export type AttackPhase = "Idle" | "Windup" | "Active" | "Recovery"

export type CombatState = {
	phase: AttackPhase,
	phaseEndsAt: number,
	attackReadyAt: number,
	weapon: string,

	swingId: number,
	swingGeneration: number,
	swingHits: { [Instance]: boolean },
	-- Resolved at the moment the swing starts and used for its whole duration, so
	-- picking up a new weapon mid-swing cannot retune the swing already in flight.
	swingStats: WeaponStats.Resolved,

	iframeUntil: number,
	dodgeReadyAt: number,
	dodgeEndsAt: number,
	dodgeConstraint: LinearVelocity?,
	cachedWalkSpeed: number,
	cachedAutoRotate: boolean,

	staminaReadyAt: number,
	lastAttackRequestAt: number,
	lastDodgeRequestAt: number,
}

-- Anything that can take a swing. The registry is the seam Phase 2 needs: queryArc
-- never branches on target type.
export type Damageable = {
	model: Model,
	kind: string,
	getHealth: () -> (number, number),
	applyDamage: (amount: number, info: CombatTypes.DamageInfo) -> (number, string?),
}

local combats: { [Player]: CombatState } = {}
local damageables: { [Model]: Damageable } = {}

local feedbackRemote: RemoteEvent
local requestAttack: RemoteEvent
local requestDodge: RemoteEvent

local function newCombat(): CombatState
	return {
		phase = "Idle",
		phaseEndsAt = 0,
		attackReadyAt = 0,
		weapon = CombatConfig.defaultWeapon,
		swingId = 0,
		swingGeneration = -1,
		swingHits = {},
		swingStats = WeaponStats.resolve(CombatConfig.defaultWeapon, {}),
		iframeUntil = 0,
		dodgeReadyAt = 0,
		dodgeEndsAt = 0,
		dodgeConstraint = nil,
		cachedWalkSpeed = CombatConfig.player.walkSpeed,
		cachedAutoRotate = true,
		staminaReadyAt = 0,
		lastAttackRequestAt = 0,
		lastDodgeRequestAt = 0,
	}
end

local function broadcast(payload: CombatTypes.Feedback)
	if feedbackRemote ~= nil then
		-- FireAllClients: everyone should see everyone swing, co-op from day one.
		-- Distance culling is a Phase 14 concern.
		feedbackRemote:FireAllClients(payload)
	end
end

CombatService.broadcast = broadcast

-- ---------------------------------------------------------------- damageables

function CombatService.registerDamageable(entry: Damageable)
	damageables[entry.model] = entry
end

function CombatService.unregisterDamageable(model: Model)
	damageables[model] = nil
end

-- Walks up at most 4 ancestors: a hit part is a limb or a child mesh, not the root.
function CombatService.damageableFor(instance: Instance): Damageable?
	local node: Instance? = instance
	for _ = 1, 4 do
		if node == nil then
			return nil
		end
		if node:IsA("Model") then
			local found = damageables[node]
			if found ~= nil then
				return found
			end
		end
		node = node.Parent
	end
	return nil
end

-- ------------------------------------------------------------------ geometry

-- Yaw-only, so a tilted or mid-ragdoll root cannot swing the box into the floor.
local function swingOrigin(rootCFrame: CFrame): CFrame
	local look = rootCFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-4 then
		flat = Vector3.new(0, 0, -1)
	else
		flat = flat.Unit
	end
	return CFrame.lookAt(rootCFrame.Position, rootCFrame.Position + flat)
end

-- Takes either an archetype id or an already-resolved weapon, so pure geometry
-- checks stay callable without building an inventory.
local function statsFor(weapon: string | WeaponStats.Resolved): WeaponStats.Resolved
	if typeof(weapon) == "string" then
		return WeaponStats.resolve(weapon, {})
	end
	return weapon
end

function CombatService.swingVolume(
	rootCFrame: CFrame,
	weapon: string | WeaponStats.Resolved
): (CFrame, Vector3)
	local stats = statsFor(weapon)
	local origin = swingOrigin(rootCFrame)
	return origin * CFrame.new(0, 0, -stats.arcForwardOffset), stats.arcSize
end

-- GetPartBoundsInBox returns a box; this trims the corners to a frontal cone. Without
-- it you can hit things beside you.
function CombatService.isInArc(
	rootCFrame: CFrame,
	point: Vector3,
	weapon: string | WeaponStats.Resolved
): boolean
	local stats = statsFor(weapon)
	local origin = swingOrigin(rootCFrame)
	local delta = point - origin.Position

	local flatDelta = Vector3.new(delta.X, 0, delta.Z)
	if flatDelta.Magnitude > stats.reach then
		return false
	end
	if math.abs(delta.Y) > stats.arcSize.Y / 2 then
		return false
	end
	if flatDelta.Magnitude < 1e-4 then
		return true
	end
	return flatDelta.Unit:Dot(origin.LookVector) >= stats.arcHalfAngleCos
end

-- ------------------------------------------------------------------- damage

-- I-frames are checked HERE, at application time, never at swing time.
function CombatService.applyDamageToPlayer(
	player: Player,
	amount: number,
	info: CombatTypes.DamageInfo
): (number, string?)
	local combat = combats[player]
	if combat == nil then
		return 0, "nocombat"
	end
	if os.clock() < combat.iframeUntil then
		return 0, "iframes"
	end
	-- Armour is applied here, at the one place damage reaches a player, so enemies
	-- and the environment both go through it.
	local incoming = math.max(0, amount * InventoryService.incomingDamageMultiplier(player))
	return PlayerService.applyDamage(player, incoming, info)
end

-- ------------------------------------------------------------------- swings

local function queryArc(player: Player, combat: CombatState)
	local state = PlayerService.get(player)
	if state == nil then
		return
	end
	local rootPart = state.rootPart
	local character = state.character
	if rootPart == nil or character == nil or character.Parent == nil then
		return
	end

	local weapon = combat.swingStats
	local volumeCFrame, volumeSize = CombatService.swingVolume(rootPart.CFrame, weapon)

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	-- A part cap, not a target cap: one R15 character is ~15 parts. maxTargets is
	-- applied below, after resolving parts to damageables.
	params.MaxParts = 32
	params.RespectCanCollide = false

	local parts = workspace:GetPartBoundsInBox(volumeCFrame, volumeSize, params)
	local hitCount = 0

	for _, part in parts do
		if hitCount >= weapon.maxTargets then
			break
		end
		local target = CombatService.damageableFor(part)
		if target == nil then
			continue
		end
		-- Dedupe by resolved model, not by part: a character contributes many parts.
		if combat.swingHits[target.model] then
			continue
		end
		if not CombatService.isInArc(rootPart.CFrame, part.Position, weapon) then
			continue
		end

		combat.swingHits[target.model] = true
		hitCount += 1

		-- Relics are applied here, at the one place a player's swing becomes damage,
		-- rather than baked into the weapon: Blood Charm is conditional on current
		-- health and would be wrong the moment it was cached.
		local outgoing =
			math.max(0, weapon.damage * InventoryService.outgoingDamageMultiplier(player))

		local dealt, reason = target.applyDamage(outgoing, {
			source = player,
			weapon = combat.swingStats.archetype,
			position = part.Position,
		})
		if dealt > 0 and reason == nil then
			local remaining = target.getHealth()
			broadcast({
				kind = "Hit",
				actor = player,
				target = target.model,
				amount = dealt,
				remaining = remaining,
				hitPosition = part.Position,
				lethal = remaining <= 0,
			})
		end
	end
end

local function enterActive(player: Player, combat: CombatState, now: number)
	local weapon = combat.swingStats
	combat.phase = "Active"
	combat.phaseEndsAt = now + weapon.active
	table.clear(combat.swingHits)
	-- Query immediately, in this same frame. Waiting for the next tick would lose a
	-- third of a 0.12s window at 30fps.
	queryArc(player, combat)
end

local function enterRecovery(combat: CombatState, now: number)
	local weapon = combat.swingStats
	combat.phase = "Recovery"
	combat.phaseEndsAt = now + weapon.recovery
	combat.attackReadyAt = combat.phaseEndsAt
end

local function resetCombat(combat: CombatState)
	combat.phase = "Idle"
	combat.phaseEndsAt = 0
	combat.attackReadyAt = 0
	combat.iframeUntil = 0
	combat.dodgeEndsAt = 0
	combat.dodgeReadyAt = 0
	table.clear(combat.swingHits)
	if combat.dodgeConstraint ~= nil then
		combat.dodgeConstraint:Destroy()
		combat.dodgeConstraint = nil
	end
end

-- -------------------------------------------------------------------- dodge

local function endDodge(player: Player, combat: CombatState)
	combat.dodgeEndsAt = 0
	if combat.dodgeConstraint ~= nil then
		combat.dodgeConstraint:Destroy()
		combat.dodgeConstraint = nil
	end
	local state = PlayerService.get(player)
	local humanoid = if state ~= nil then state.humanoid else nil
	if humanoid ~= nil and humanoid.Parent ~= nil then
		humanoid.WalkSpeed = combat.cachedWalkSpeed
		humanoid.AutoRotate = combat.cachedAutoRotate
	end
end

local function startDodge(player: Player, combat: CombatState, now: number)
	local state = PlayerService.get(player)
	if state == nil then
		return
	end
	local rootPart = state.rootPart
	local humanoid = state.humanoid
	if rootPart == nil or humanoid == nil then
		return
	end

	-- Direction is derived server-side. MoveDirection already replicates from the
	-- owning client, so RequestDodge carries no payload and there is nothing to spoof.
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 1e-3 then
		local look = rootPart.CFrame.LookVector
		direction = Vector3.new(look.X, 0, look.Z)
	end
	if direction.Magnitude < 1e-3 then
		direction = Vector3.new(0, 0, -1)
	end
	direction = direction.Unit

	local attachment = rootPart:FindFirstChild("RootAttachment")
	if attachment == nil or not attachment:IsA("Attachment") then
		local made = Instance.new("Attachment")
		made.Name = "OMF_DodgeAttachment"
		made.Parent = rootPart
		attachment = made
	end

	combat.cachedWalkSpeed = humanoid.WalkSpeed
	combat.cachedAutoRotate = humanoid.AutoRotate

	-- A server-set velocity on a client-owned assembly gets overwritten by the owner's
	-- next physics step. A constraint replicates as an instance and the owning client
	-- simulates it, which is both authoritative and responsive.
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "OMF_DodgeVelocity"
	velocity.Attachment0 = attachment :: Attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	-- Y force is zero so a dodge never fights gravity or launches you off a ledge.
	velocity.MaxAxesForce = Vector3.new(CombatConfig.dodge.maxForce, 0, CombatConfig.dodge.maxForce)
	velocity.VectorVelocity = direction * CombatConfig.dodge.speed
	velocity.Parent = rootPart

	-- Zeroing WalkSpeed stops the player's own movement force fighting the constraint,
	-- which makes distance deterministic at speed * duration.
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false

	combat.dodgeConstraint = velocity
	combat.dodgeEndsAt = now + CombatConfig.dodge.duration
	combat.iframeUntil = now + CombatConfig.dodge.iframes
	combat.dodgeReadyAt = now + CombatConfig.dodge.cooldown
end

-- ------------------------------------------------------------------- intent

function CombatService.phaseOf(player: Player): AttackPhase
	local combat = combats[player]
	return if combat ~= nil then combat.phase else "Idle"
end

function CombatService.stateOf(player: Player): CombatState?
	return combats[player]
end

function CombatService.tryAttack(player: Player): (boolean, string?)
	local combat = combats[player]
	if combat == nil then
		return false, "nocombat"
	end
	if not PlayerService.isActionable(player) then
		return false, "dead"
	end

	local now = os.clock()
	if now - combat.lastAttackRequestAt < CombatConfig.limits.minRequestInterval then
		return false, "throttled"
	end
	combat.lastAttackRequestAt = now

	if combat.phase ~= "Idle" then
		return false, "busy"
	end
	if now < combat.attackReadyAt then
		return false, "cooldown"
	end

	-- Resolve once, here, and use it for the whole swing.
	local weapon = InventoryService.weaponStats(player)
	combat.swingStats = weapon
	combat.weapon = weapon.archetype

	if weapon.staminaCost > 0 and not PlayerService.spendStamina(player, weapon.staminaCost) then
		return false, "stamina"
	end
	if weapon.staminaCost > 0 then
		combat.staminaReadyAt = now + CombatConfig.stamina.regenDelay
	end

	combat.swingId += 1
	combat.swingGeneration = PlayerService.generation(player)
	combat.phase = "Windup"
	combat.phaseEndsAt = now + weapon.windup
	table.clear(combat.swingHits)

	broadcast({
		kind = "SwingStarted",
		actor = player,
		weapon = weapon.archetype,
		windup = weapon.windup,
		active = weapon.active,
		recovery = weapon.recovery,
	})
	return true, nil
end

function CombatService.tryDodge(player: Player): (boolean, string?)
	local combat = combats[player]
	if combat == nil then
		return false, "nocombat"
	end
	if not PlayerService.isActionable(player) then
		return false, "dead"
	end

	local now = os.clock()
	if now - combat.lastDodgeRequestAt < CombatConfig.limits.minRequestInterval then
		return false, "throttled"
	end
	combat.lastDodgeRequestAt = now

	if now < combat.dodgeReadyAt then
		return false, "cooldown"
	end
	-- Windup and Recovery are cancellable; Active is not. Cancelling the active window
	-- would be free damage with no commitment.
	if combat.phase == "Active" then
		return false, "busy"
	end
	if not PlayerService.spendStamina(player, CombatConfig.dodge.staminaCost) then
		return false, "stamina"
	end

	combat.staminaReadyAt = now + CombatConfig.stamina.regenDelay
	combat.phase = "Idle"
	combat.phaseEndsAt = 0
	table.clear(combat.swingHits)

	startDodge(player, combat, now)

	broadcast({
		kind = "Dodged",
		actor = player,
		duration = CombatConfig.dodge.duration,
		iframes = CombatConfig.dodge.iframes,
	})
	return true, nil
end

-- --------------------------------------------------------------------- tick

local function step(dt: number)
	local now = os.clock()
	for player, combat in combats do
		local state = PlayerService.get(player)
		if state == nil then
			continue
		end

		-- 1. Generation guard first: a swing must never survive a respawn.
		if combat.phase ~= "Idle" and combat.swingGeneration ~= state.generation then
			resetCombat(combat)
		end

		-- 2. Dodge expiry before phase work, so WalkSpeed is restored before anything
		--    downstream reads it this frame.
		if combat.dodgeEndsAt > 0 and now >= combat.dodgeEndsAt then
			endDodge(player, combat)
		end

		-- 3. Stamina regen.
		if now >= combat.staminaReadyAt and state.stamina < state.maxStamina then
			local rate = CombatConfig.stamina.regenPerSecond
				* InventoryService.staminaRegenMultiplier(player)
			PlayerService.addStamina(player, rate * dt)
		end

		-- 4. Attack phases.
		if combat.phase == "Windup" and now >= combat.phaseEndsAt then
			enterActive(player, combat, now)
		elseif combat.phase == "Active" then
			queryArc(player, combat)
			if now >= combat.phaseEndsAt then
				enterRecovery(combat, now)
			end
		elseif combat.phase == "Recovery" and now >= combat.phaseEndsAt then
			combat.phase = "Idle"
		end

		-- 5. Death backstop: Humanoid.Died can fail to fire if the Dead state is
		--    disabled. handleDeath is idempotent.
		local humanoid = state.humanoid
		if state.alive and humanoid ~= nil and humanoid.Parent ~= nil and humanoid.Health <= 0 then
			PlayerService.handleDeath(player, state.generation)
		end
	end
end

-- ------------------------------------------------------------- registration

local function registerPlayerDamageable(player: Player, character: Model)
	CombatService.registerDamageable({
		model = character,
		kind = "Player",
		getHealth = function(): (number, number)
			local state = PlayerService.get(player)
			if state == nil then
				return 0, 0
			end
			return state.health, state.maxHealth
		end,
		applyDamage = function(amount: number, info: CombatTypes.DamageInfo): (number, string?)
			return CombatService.applyDamageToPlayer(player, amount, info)
		end,
	})
end

local function onPlayerAdded(player: Player)
	-- Return, not just guard the table write: Start connects PlayerAdded AND loops
	-- GetPlayers(), so this can run twice for one player and would otherwise stack a
	-- second set of CharacterAdded connections.
	if combats[player] ~= nil then
		return
	end
	combats[player] = newCombat()

	-- CombatService connects its own character lifecycle, because PlayerService must
	-- not require any other service.
	player.CharacterAdded:Connect(function(character)
		local combat = combats[player]
		if combat ~= nil then
			resetCombat(combat)
		end
		task.spawn(function()
			WeaponBuilder.equip(character, InventoryService.equippedWeapon(player).archetype)
			registerPlayerDamageable(player, character)
		end)
	end)

	player.CharacterRemoving:Connect(function(character)
		local combat = combats[player]
		if combat ~= nil then
			resetCombat(combat)
		end
		CombatService.unregisterDamageable(character)
	end)

	local existing = player.Character
	if existing ~= nil then
		task.spawn(function()
			WeaponBuilder.equip(existing, InventoryService.equippedWeapon(player).archetype)
			registerPlayerDamageable(player, existing)
		end)
	end
end

function CombatService.Init()
	table.clear(combats)
	table.clear(damageables)
	requestAttack = Net.event("RequestAttack")
	requestDodge = Net.event("RequestDodge")
	feedbackRemote = Net.event("CombatFeedback")
end

function CombatService.Start()
	-- Both handlers ignore client varargs entirely: the remotes are argument-free.
	requestAttack.OnServerEvent:Connect(function(player: Player)
		CombatService.tryAttack(player)
	end)
	requestDodge.OnServerEvent:Connect(function(player: Player)
		CombatService.tryDodge(player)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		combats[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	PlayerService.onDied.Event:Connect(function(_player: Player, character: Model?)
		broadcast({
			kind = "Died",
			actor = character,
			respawnIn = CombatConfig.player.respawnDelay,
		})
	end)

	PlayerService.onSpawned.Event:Connect(function(player: Player)
		broadcast({ kind = "Respawned", actor = player })
	end)

	-- Picking up a Greatsword has to look like picking up a Greatsword.
	InventoryService.onWeaponEquipped.Event:Connect(function(player: Player, archetype: string)
		local state = PlayerService.get(player)
		local character = if state ~= nil then state.character else nil
		if character ~= nil and character.Parent ~= nil then
			WeaponBuilder.equip(character, archetype)
		end
	end)

	RunService.Heartbeat:Connect(step)
end

return CombatService
