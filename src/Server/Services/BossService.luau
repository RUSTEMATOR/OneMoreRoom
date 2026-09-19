--!strict
-- Runs a boss fight by composing the pure controllers: BossPhases decides which act
-- we are in, BossAttacks decides what happens next, and this service owns the rig,
-- the clock and the world.
--
-- A boss is deliberately NOT a special case of enemy: it registers as the same
-- `Damageable` the sword already knows how to hit, it ticks on the same Heartbeat
-- discipline, and its arena is an ordinary room template. What is special is only
-- the phase structure, which is the part that is actually different.
--
-- Adding a second boss means adding a BossConfig entry and, if it needs a mechanic
-- no attack kind covers, one new kind here. It does not mean touching the Warden.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BossConfig = require(ReplicatedStorage.Shared.BossConfig)
local CombatTypes = require(ReplicatedStorage.Shared.CombatTypes)
local BossAttacks = require(script.Parent.Parent.Boss.BossAttacks)
local BossPhases = require(script.Parent.Parent.Boss.BossPhases)
local CombatService = require(script.Parent.CombatService)
local EnemyBuilder = require(script.Parent.Parent.Combat.EnemyBuilder)
local EnemyService = require(script.Parent.EnemyService)
local PlayerService = require(script.Parent.PlayerService)
local RunSessionService = require(script.Parent.RunSessionService)

local BossService = {}

export type BossPhaseName = "Idle" | "Windup" | "Recovery" | "Transition" | "Dead"

export type Boss = {
	id: number,
	bossId: string,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	rootJoint: Motor6D?,

	health: number,
	maxHealth: number,

	phaseIndex: number,
	state: BossPhaseName,
	stateEndsAt: number,
	cooldowns: BossAttacks.Cooldowns,
	pendingAttack: BossConfig.Attack?,
	telegraph: BasePart?,

	nextSummonAt: number,
	summonIds: { number },

	target: Player?,
	generation: number,
}

local bosses: { [number]: Boss } = {}
local nextId = 0

BossService.onSpawned = Instance.new("BindableEvent")
BossService.onPhaseChanged = Instance.new("BindableEvent")
BossService.onDefeated = Instance.new("BindableEvent")

-- ------------------------------------------------------------------ helpers

local function spec(bossId: string): BossConfig.Boss?
	return BossConfig.bosses[bossId]
end

function BossService.healthFraction(boss: Boss): number
	if boss.maxHealth <= 0 then
		return 0
	end
	return boss.health / boss.maxHealth
end

function BossService.currentPhase(boss: Boss): BossConfig.Phase?
	return BossPhases.at(boss.bossId, boss.phaseIndex)
end

local function lunge(boss: Boss, degrees: number, seconds: number)
	local joint = boss.rootJoint
	if joint == nil then
		return
	end
	TweenService:Create(joint, TweenInfo.new(seconds, Enum.EasingStyle.Quad), {
		C0 = CFrame.Angles(math.rad(degrees), 0, 0),
	}):Play()
end

local function nearestPlayer(position: Vector3): (Player?, number)
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
		if distance < bestDistance then
			best = state.player
			bestDistance = distance
		end
	end
	return best, bestDistance
end

-- --------------------------------------------------------------- telegraph

-- A flat disc or wedge on the floor during the windup. Purely a read, but the fight
-- is unfair without it: the Slam covers the whole arena, so the only correct answer
-- is to dodge through it, and you cannot time a dodge you cannot see coming.
local function showTelegraph(boss: Boss, attack: BossConfig.Attack)
	local existing = boss.telegraph
	if existing ~= nil then
		existing:Destroy()
	end

	local reach = BossAttacks.effectiveRange(attack)
	local part = Instance.new("Part")
	part.Name = "BossTelegraph"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Material = Enum.Material.Neon
	part.Color = attack.telegraphColor
	part.Transparency = BossConfig.telegraph.transparency
	part.Size = Vector3.new(reach * 2, BossConfig.telegraph.height, reach * 2)
	part.Shape = Enum.PartType.Cylinder
	-- A cylinder's length runs along X, so stand it up to lie flat on the floor.
	part.CFrame = CFrame.new(boss.root.Position.X, boss.root.Position.Y - 2.6, boss.root.Position.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	part.Size = Vector3.new(BossConfig.telegraph.height, reach * 2, reach * 2)
	part.Parent = boss.model

	boss.telegraph = part
	TweenService:Create(part, TweenInfo.new(attack.windup), { Transparency = 0.15 }):Play()
end

local function clearTelegraph(boss: Boss)
	local part = boss.telegraph
	if part ~= nil then
		part:Destroy()
		boss.telegraph = nil
	end
end

-- ------------------------------------------------------------------ damage

local function despawnSummons(boss: Boss)
	for _, id in boss.summonIds do
		local enemy = EnemyService.get(id)
		if enemy ~= nil then
			enemy.model:Destroy()
		end
	end
	table.clear(boss.summonIds)
end

function BossService.liveSummonCount(boss: Boss): number
	local alive = 0
	for _, id in boss.summonIds do
		local enemy = EnemyService.get(id)
		if enemy ~= nil and enemy.phase ~= "Dead" then
			alive += 1
		end
	end
	return alive
end

local function die(boss: Boss, killer: Player?)
	if boss.state == "Dead" then
		return
	end
	boss.state = "Dead"
	boss.generation += 1
	boss.health = 0
	boss.humanoid.Health = 0
	boss.humanoid.WalkSpeed = 0
	clearTelegraph(boss)
	despawnSummons(boss)
	lunge(boss, 85, 0.5)

	local bossSpec = spec(boss.bossId)
	local gold = if bossSpec ~= nil then BossConfig.rewards.goldPerBoss else 0
	RunSessionService.addGold(gold)

	CombatService.broadcast({ kind = "Died", actor = boss.model, respawnIn = nil })
	BossService.onDefeated:Fire(boss.bossId, killer, gold)
end

local function applyDamage(
	boss: Boss,
	amount: number,
	info: CombatTypes.DamageInfo
): (number, string?)
	if boss.state == "Dead" then
		return 0, "dead"
	end
	-- Invulnerable through a transition, so a burst cannot skip an act.
	if boss.state == "Transition" then
		return 0, "transition"
	end

	local before = boss.health
	boss.health = math.clamp(boss.health - amount, 0, boss.maxHealth)
	local dealt = before - boss.health
	boss.humanoid.Health = boss.health

	if boss.health <= 0 then
		die(boss, info.source)
		return dealt, nil
	end

	-- Fire the transition exactly once, on the frame the threshold is crossed,
	-- rather than every frame the fraction happens to sit below a line.
	if BossPhases.crosses(boss.bossId, before / boss.maxHealth, boss.health / boss.maxHealth) then
		local bossSpec = spec(boss.bossId)
		boss.phaseIndex = BossPhases.indexFor(boss.bossId, boss.health / boss.maxHealth)
		boss.state = "Transition"
		boss.stateEndsAt = os.clock() + (if bossSpec ~= nil then bossSpec.transitionTime else 1)
		boss.pendingAttack = nil
		clearTelegraph(boss)
		lunge(boss, -30, 0.4)

		local phase = BossService.currentPhase(boss)
		BossService.onPhaseChanged:Fire(boss.bossId, boss.phaseIndex, phase)
		if phase ~= nil then
			print(`[OMF] {boss.bossId} phase {boss.phaseIndex}: {phase.displayName}`)
		end
	end

	return dealt, nil
end

-- ------------------------------------------------------------------- spawn

function BossService.spawn(bossId: string, cframe: CFrame, parent: Instance): Boss?
	local bossSpec = spec(bossId)
	if bossSpec == nil then
		return nil
	end

	-- The same rig builder the Skeleton uses. A boss is a bigger enemy, not a
	-- different kind of object.
	local model = EnemyBuilder.buildFromRig(bossId, bossSpec.rig, bossSpec.maxHealth, 12)
	local root = model.PrimaryPart
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if root == nil or humanoid == nil then
		model:Destroy()
		return nil
	end

	nextId += 1
	local boss: Boss = {
		id = nextId,
		bossId = bossId,
		model = model,
		humanoid = humanoid,
		root = root,
		rootJoint = root:FindFirstChild("RootJoint") :: Motor6D?,
		health = bossSpec.maxHealth,
		maxHealth = bossSpec.maxHealth,
		phaseIndex = 1,
		state = "Idle",
		stateEndsAt = 0,
		cooldowns = {},
		pendingAttack = nil,
		telegraph = nil,
		nextSummonAt = 0,
		summonIds = {},
		target = nil,
		generation = 0,
	}

	model.Parent = parent
	model:PivotTo(cframe)
	bosses[boss.id] = boss

	CombatService.registerDamageable({
		model = model,
		kind = "Boss",
		getHealth = function(): (number, number)
			return boss.health, boss.maxHealth
		end,
		applyDamage = function(amount: number, info: CombatTypes.DamageInfo): (number, string?)
			return applyDamage(boss, amount, info)
		end,
	})

	BossService.onSpawned:Fire(bossId, boss)
	print(
		`[OMF] {bossSpec.displayName} awakens — {bossSpec.maxHealth} HP, {#bossSpec.phases} phases`
	)
	return boss
end

function BossService.despawn(boss: Boss)
	despawnSummons(boss)
	clearTelegraph(boss)
	CombatService.unregisterDamageable(boss.model)
	bosses[boss.id] = nil
	if boss.model.Parent ~= nil then
		boss.model:Destroy()
	end
end

function BossService.despawnAll()
	for _, boss in bosses do
		BossService.despawn(boss)
	end
	table.clear(bosses)
end

function BossService.get(id: number): Boss?
	return bosses[id]
end

function BossService.count(): number
	local n = 0
	for _ in bosses do
		n += 1
	end
	return n
end

function BossService.isDefeated(boss: Boss): boolean
	return boss.state == "Dead"
end

-- --------------------------------------------------------------------- tick

local function landAttack(boss: Boss, attack: BossConfig.Attack)
	local look = boss.root.CFrame.LookVector
	for _, state in PlayerService.all() do
		if not state.alive then
			continue
		end
		local root = state.rootPart
		if root == nil or root.Parent == nil then
			continue
		end
		-- Reach is re-checked at the moment the blow lands, exactly as it is for
		-- ordinary enemies, so dodging out of a telegraph works.
		if BossAttacks.reaches(attack, boss.root.Position, look, root.Position) then
			CombatService.applyDamageToPlayer(state.player, attack.damage, {
				source = nil,
				weapon = `{boss.bossId}:{attack.id}`,
				position = boss.root.Position,
			})
		end
	end
end

local function stepSummons(boss: Boss, phase: BossConfig.Phase, now: number)
	if phase.summonKind == nil or phase.summonInterval == nil then
		return
	end
	if now < boss.nextSummonAt then
		return
	end
	boss.nextSummonAt = now + phase.summonInterval

	local cap = phase.maxSummons or 99
	if BossService.liveSummonCount(boss) >= cap then
		return
	end

	local count = phase.summonCount or 1
	for index = 1, count do
		local angle = (index / count) * math.pi * 2
		local offset = Vector3.new(math.cos(angle) * 10, 0, math.sin(angle) * 10)
		local enemy = EnemyService.spawn(
			phase.summonKind,
			CFrame.new(boss.root.Position + offset + Vector3.new(0, 1, 0)),
			boss.model.Parent or workspace
		)
		if enemy ~= nil then
			table.insert(boss.summonIds, enemy.id)
		end
	end
end

local function stepBoss(boss: Boss, now: number)
	if boss.state == "Dead" then
		return
	end
	if boss.model.Parent == nil then
		bosses[boss.id] = nil
		return
	end

	if boss.state == "Transition" then
		if now >= boss.stateEndsAt then
			boss.state = "Idle"
			lunge(boss, 0, 0.3)
			-- Every attack comes off cooldown, so a new act opens immediately.
			table.clear(boss.cooldowns)
		end
		return
	end

	local phase = BossService.currentPhase(boss)
	if phase == nil then
		return
	end
	boss.humanoid.WalkSpeed = phase.walkSpeed

	if boss.state == "Windup" then
		if now >= boss.stateEndsAt then
			local attack = boss.pendingAttack
			clearTelegraph(boss)
			if attack ~= nil then
				landAttack(boss, attack)
				lunge(boss, 28, 0.12)
				boss.state = "Recovery"
				boss.stateEndsAt = now + attack.recovery
				boss.cooldowns[attack.id] = now + attack.cooldown
			else
				boss.state = "Idle"
			end
			boss.pendingAttack = nil
		end
		return
	end

	if boss.state == "Recovery" then
		if now >= boss.stateEndsAt then
			boss.state = "Idle"
			lunge(boss, 0, 0.2)
		end
		return
	end

	-- Idle: chase, summon, and look for something to throw.
	stepSummons(boss, phase, now)

	local target, distance = nearestPlayer(boss.root.Position)
	boss.target = target
	if target == nil then
		return
	end

	local attack = BossAttacks.choose(boss.bossId, phase, boss.cooldowns, distance, now)
	if attack ~= nil then
		boss.state = "Windup"
		boss.stateEndsAt = now + attack.windup
		boss.pendingAttack = attack
		boss.humanoid:MoveTo(boss.root.Position)
		lunge(boss, -26, attack.windup * 0.8)
		showTelegraph(boss, attack)
		return
	end

	local state = PlayerService.get(target)
	local root = if state ~= nil then state.rootPart else nil
	if root ~= nil then
		boss.humanoid:MoveTo(root.Position)
	end
end

local function step()
	local now = os.clock()
	for _, boss in bosses do
		stepBoss(boss, now)
	end
end

-- ---------------------------------------------------------------- lifecycle

function BossService.Init()
	table.clear(bosses)
	nextId = 0
end

function BossService.Start()
	RunService.Heartbeat:Connect(step)
end

return BossService
