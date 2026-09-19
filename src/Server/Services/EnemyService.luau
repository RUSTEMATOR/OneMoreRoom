--!strict
-- Enemies and their state machine: IDLE -> NOTICE -> CHASE -> ATTACK -> COOLDOWN.
--
-- Same tick discipline as CombatService: one Heartbeat for every enemy, so os.clock()
-- is read once per frame in one place and no two timers can disagree about "now".
-- The only task.delay here is the despawn, and it is generation-guarded.
--
-- Enemies deal damage through CombatService.applyDamageToPlayer, so player i-frames
-- apply to them for free, and they take damage by registering as Damageables, so the
-- sword arc never branches on target type.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CombatTypes = require(ReplicatedStorage.Shared.CombatTypes)
local EnemyConfig = require(ReplicatedStorage.Shared.EnemyConfig)
local CombatService = require(script.Parent.CombatService)
local EnemyBuilder = require(script.Parent.Parent.Combat.EnemyBuilder)
local FloorService = require(script.Parent.FloorService)
local PlayerService = require(script.Parent.PlayerService)
local RunSessionService = require(script.Parent.RunSessionService)

local EnemyService = {}

export type EnemyPhase = "Idle" | "Notice" | "Chase" | "Attack" | "Cooldown" | "Dead"

export type Enemy = {
	id: number,
	kind: string,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	rootJoint: Motor6D?,

	health: number,
	maxHealth: number,

	phase: EnemyPhase,
	phaseEndsAt: number,
	target: Player?,
	homePosition: Vector3,
	staggerUntil: number,
	attackReadyAt: number,
	attackLanded: boolean,
	generation: number,
}

local enemies: { [number]: Enemy } = {}
local nextId = 0
local practiceGeneration = 0

local function spec(kind: string)
	return EnemyConfig.kinds[kind]
end

-- ------------------------------------------------------------------ helpers

local function nearestPlayerWithin(position: Vector3, range: number): (Player?, number)
	local best: Player? = nil
	local bestDistance = math.huge
	for _, state in PlayerService.all() do
		if not state.alive then
			continue
		end
		local root = state.rootPart
		if root == nil or root.Parent == nil then
			continue
		end
		local distance = (root.Position - position).Magnitude
		if distance <= range and distance < bestDistance then
			best = state.player
			bestDistance = distance
		end
	end
	return best, bestDistance
end

local function distanceToPlayer(enemy: Enemy, player: Player): number
	local state = PlayerService.get(player)
	local root = if state ~= nil then state.rootPart else nil
	if root == nil or root.Parent == nil then
		return math.huge
	end
	return (root.Position - enemy.root.Position).Magnitude
end

local function lunge(enemy: Enemy, degrees: number, seconds: number)
	local joint = enemy.rootJoint
	if joint == nil then
		return
	end
	local goal = CFrame.Angles(math.rad(degrees), 0, 0)
	TweenService:Create(joint, TweenInfo.new(seconds, Enum.EasingStyle.Quad), { C0 = goal }):Play()
end

-- ------------------------------------------------------------------- damage

local function despawn(enemy: Enemy)
	enemies[enemy.id] = nil
	CombatService.unregisterDamageable(enemy.model)
	if enemy.model.Parent ~= nil then
		enemy.model:Destroy()
	end
end

local function die(enemy: Enemy, killer: Player?)
	if enemy.phase == "Dead" then
		return
	end
	enemy.phase = "Dead"
	enemy.generation += 1
	enemy.health = 0

	local enemySpec = spec(enemy.kind)
	enemy.humanoid.Health = 0
	enemy.humanoid.WalkSpeed = 0
	lunge(enemy, 80, 0.25)

	local awarded = RunSessionService.addGold(enemySpec.goldReward)
	CombatService.broadcast({
		kind = "Died",
		actor = enemy.model,
		respawnIn = nil,
	})
	-- The id leads, so listeners can tell WHICH enemy died. Without it a listener
	-- cannot distinguish its own enemy from any other, which is exactly the bug the
	-- practice respawn below used to have.
	EnemyService.onKilled:Fire(enemy.id, enemy.kind, killer, awarded)

	local gen = enemy.generation
	task.delay(enemySpec.despawnDelay, function()
		-- Stale-timer guard: the enemy may already have been despawned by a floor
		-- teardown between the kill and this firing.
		local current = enemies[enemy.id]
		if current ~= nil and current.generation ~= gen then
			return
		end
		despawn(enemy)
	end)
end

local function applyDamage(
	enemy: Enemy,
	amount: number,
	info: CombatTypes.DamageInfo
): (number, string?)
	if enemy.phase == "Dead" then
		return 0, "dead"
	end
	local before = enemy.health
	enemy.health = math.clamp(enemy.health - amount, 0, enemy.maxHealth)
	local dealt = before - enemy.health
	enemy.humanoid.Health = enemy.health

	if enemy.health <= 0 then
		die(enemy, info.source)
		return dealt, nil
	end

	-- Hit reaction: a brief stagger. The client-side flash is already handled by
	-- FeedbackController's generic Hit branch, which works on any Model.
	local enemySpec = spec(enemy.kind)
	enemy.staggerUntil = os.clock() + enemySpec.staggerTime
	lunge(enemy, -14, enemySpec.staggerTime * 0.5)

	-- Getting hit by someone you had not noticed pulls aggro onto them.
	if info.source ~= nil and enemy.target == nil then
		enemy.target = info.source
		enemy.phase = "Chase"
	end

	return dealt, nil
end

-- ------------------------------------------------------------------- spawn

function EnemyService.spawn(kind: string, cframe: CFrame, parent: Instance?): Enemy?
	local enemySpec = spec(kind)
	if enemySpec == nil then
		return nil
	end

	local model = EnemyBuilder.build(kind)
	local root = model.PrimaryPart
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if root == nil or humanoid == nil then
		model:Destroy()
		return nil
	end

	nextId += 1
	local enemy: Enemy = {
		id = nextId,
		kind = kind,
		model = model,
		humanoid = humanoid,
		root = root,
		rootJoint = root:FindFirstChild("RootJoint") :: Motor6D?,
		health = enemySpec.maxHealth,
		maxHealth = enemySpec.maxHealth,
		phase = "Idle",
		phaseEndsAt = 0,
		target = nil,
		homePosition = cframe.Position,
		staggerUntil = 0,
		attackReadyAt = 0,
		attackLanded = false,
		generation = 0,
	}

	model.Parent = parent or FloorService.generatedFolder()
	model:PivotTo(cframe)
	enemies[enemy.id] = enemy

	CombatService.registerDamageable({
		model = model,
		kind = "Enemy",
		getHealth = function(): (number, number)
			return enemy.health, enemy.maxHealth
		end,
		applyDamage = function(amount: number, info: CombatTypes.DamageInfo): (number, string?)
			return applyDamage(enemy, amount, info)
		end,
	})

	return enemy
end

function EnemyService.despawnAll()
	for _, enemy in enemies do
		despawn(enemy)
	end
	table.clear(enemies)
end

function EnemyService.get(id: number): Enemy?
	return enemies[id]
end

function EnemyService.all(): { Enemy }
	local list = {}
	for _, enemy in enemies do
		table.insert(list, enemy)
	end
	return list
end

function EnemyService.count(): number
	local n = 0
	for _ in enemies do
		n += 1
	end
	return n
end

-- --------------------------------------------------------------------- tick

local function stepEnemy(enemy: Enemy, now: number)
	local enemySpec = spec(enemy.kind)

	if enemy.phase == "Dead" then
		return
	end

	if enemy.model.Parent == nil then
		enemies[enemy.id] = nil
		return
	end

	-- A stagger interrupts movement but never the damage the player already dealt.
	if now < enemy.staggerUntil then
		enemy.humanoid.WalkSpeed = 0
		return
	end
	enemy.humanoid.WalkSpeed = enemySpec.walkSpeed

	-- Drop a target that died, left, or ran past the leash.
	local target = enemy.target
	if target ~= nil then
		local state = PlayerService.get(target)
		if
			state == nil
			or not state.alive
			or distanceToPlayer(enemy, target) > enemySpec.leashRange
		then
			enemy.target = nil
			target = nil
			enemy.phase = "Idle"
		end
	end

	if enemy.phase == "Idle" then
		local found = nearestPlayerWithin(enemy.root.Position, enemySpec.detectRange)
		if found ~= nil then
			enemy.target = found
			enemy.phase = "Notice"
			enemy.phaseEndsAt = now + enemySpec.noticeTime
			lunge(enemy, -10, enemySpec.noticeTime * 0.6)
		else
			-- Drift home so a leashed enemy does not end the fight somewhere random.
			if (enemy.root.Position - enemy.homePosition).Magnitude > 3 then
				enemy.humanoid:MoveTo(enemy.homePosition)
			end
		end
		return
	end

	if target == nil then
		enemy.phase = "Idle"
		return
	end

	if enemy.phase == "Notice" then
		if now >= enemy.phaseEndsAt then
			enemy.phase = "Chase"
			lunge(enemy, 0, 0.15)
		end
		return
	end

	if enemy.phase == "Chase" then
		local targetState = PlayerService.get(target)
		local targetRoot = if targetState ~= nil then targetState.rootPart else nil
		if targetRoot == nil then
			enemy.phase = "Idle"
			return
		end
		local distance = distanceToPlayer(enemy, target)
		if distance <= enemySpec.attackRange and now >= enemy.attackReadyAt then
			enemy.phase = "Attack"
			enemy.phaseEndsAt = now + enemySpec.attackWindup
			enemy.attackLanded = false
			enemy.humanoid:MoveTo(enemy.root.Position)
			lunge(enemy, -20, enemySpec.attackWindup * 0.8)
		else
			enemy.humanoid:MoveTo(targetRoot.Position)
		end
		return
	end

	if enemy.phase == "Attack" then
		if not enemy.attackLanded and now >= enemy.phaseEndsAt then
			enemy.attackLanded = true
			lunge(enemy, enemySpec.rig.lungeAngle, 0.08)

			-- Re-check range at the moment the blow lands, not when it started:
			-- stepping out of a telegraphed swing has to work.
			if distanceToPlayer(enemy, target) <= enemySpec.attackRange then
				CombatService.applyDamageToPlayer(target, enemySpec.damage, {
					source = nil,
					weapon = enemy.kind,
					position = enemy.root.Position,
				})
			end
			enemy.phaseEndsAt = now + enemySpec.attackRecovery
		elseif enemy.attackLanded and now >= enemy.phaseEndsAt then
			enemy.phase = "Cooldown"
			enemy.phaseEndsAt = now + enemySpec.attackCooldown
			enemy.attackReadyAt = enemy.phaseEndsAt
			lunge(enemy, 0, 0.2)
		end
		return
	end

	if enemy.phase == "Cooldown" and now >= enemy.phaseEndsAt then
		enemy.phase = "Chase"
	end
end

local function step()
	local now = os.clock()
	for _, enemy in enemies do
		stepEnemy(enemy, now)
	end
end

-- ---------------------------------------------------------------- practice

local function spawnPractice()
	if not EnemyConfig.practice.enabled then
		return
	end
	local static = FloorService.staticFolder()
	local folder = static:FindFirstChild("Practice")
	if folder == nil then
		local made = Instance.new("Folder")
		made.Name = "Practice"
		made.Parent = static
		folder = made
	end

	local enemy = EnemyService.spawn(
		EnemyConfig.practice.kind,
		CFrame.new(EnemyConfig.practice.position),
		folder
	)
	if enemy == nil then
		return
	end

	practiceGeneration += 1
	local gen = practiceGeneration
	local practiceId = enemy.id

	-- Must filter on the id: onKilled fires for every enemy in the game, so a plain
	-- :Once here is consumed by the first unrelated death and respawns a second
	-- practice skeleton on top of the live one.
	local connection: RBXScriptConnection
	connection = EnemyService.onKilled.Event:Connect(function(killedId: number)
		if killedId ~= practiceId then
			return
		end
		connection:Disconnect()
		task.delay(EnemyConfig.practice.respawnDelay, function()
			if gen ~= practiceGeneration then
				return
			end
			spawnPractice()
		end)
	end)
end

EnemyService.onKilled = Instance.new("BindableEvent")

-- The spec suite runs against a live world, and a practice skeleton that hunts the
-- player mid-suite corrupts unrelated assertions — it cost a false failure in the
-- Phase 1 i-frame check before this existed. RunAll quiesces the world around the
-- suite and restores it afterwards.
function EnemyService.setPracticeEnabled(enabled: boolean)
	EnemyConfig.practice.enabled = enabled
	-- Invalidate any pending respawn either way.
	practiceGeneration += 1

	if enabled then
		task.spawn(spawnPractice)
		return
	end

	local static = FloorService.staticFolder()
	local folder = static:FindFirstChild("Practice")
	if folder == nil then
		return
	end
	for _, enemy in EnemyService.all() do
		if enemy.model:IsDescendantOf(folder) then
			despawn(enemy)
		end
	end
end

function EnemyService.Init()
	table.clear(enemies)
	nextId = 0
	practiceGeneration = 0
end

function EnemyService.Start()
	RunService.Heartbeat:Connect(step)

	Players.PlayerRemoving:Connect(function(player)
		for _, enemy in enemies do
			if enemy.target == player then
				enemy.target = nil
				enemy.phase = "Idle"
			end
		end
	end)

	-- Practice spawn is deferred: a Start must not yield, and PivotTo on a fresh rig
	-- is happier once the world has settled a frame.
	task.spawn(function()
		task.wait(0.5)
		spawnPractice()
	end)
end

return EnemyService
