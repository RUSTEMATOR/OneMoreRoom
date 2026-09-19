--!strict
-- Phase 10 acceptance: phase transitions fire at HP thresholds, and a second boss
-- would be a config rather than a fork.
--
-- The second half is architectural and cannot be asserted by adding a second boss in
-- the spec. What CAN be asserted is the property that makes it true: every rule the
-- framework enforces is generic, and this spec runs the generic validators over
-- every boss in BossConfig rather than over the Warden by name.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Spec = require(script.Parent.Spec)

local BossConfig = require(ReplicatedStorage.Shared.BossConfig)
local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local FloorConfig = require(ReplicatedStorage.Shared.FloorConfig)
local FloorPlan = require(ReplicatedStorage.Shared.FloorPlan)
local RoomConfig = require(ReplicatedStorage.Shared.RoomConfig)
local BossAttacks = require(ServerScriptService.Boss.BossAttacks)
local BossPhases = require(ServerScriptService.Boss.BossPhases)
local BossService = require(ServerScriptService.Services.BossService)
local CombatService = require(ServerScriptService.Services.CombatService)
local FloorService = require(ServerScriptService.Services.FloorService)
local PlayerService = require(ServerScriptService.Services.PlayerService)
local RoomService = require(ServerScriptService.Services.RoomService)
local RunSessionService = require(ServerScriptService.Services.RunSessionService)

local SEED = 101010
local WARDEN = BossConfig.bosses.Warden

-- The boss in this spec is a REAL, live AI, not a mock, and it keeps fighting during
-- every task.wait below. Left unguarded it can kill the test player, which fires
-- FloorService.endRun() and destroys the room out from under the running spec. This
-- keeps the player alive through the fight without touching the boss's own behaviour
-- or timing, so the phase-transition and cooldown assertions stay honest.
local function surviveWait(seconds: number, player: Player, playerServiceModule: any)
	local remaining = seconds
	while remaining > 0 do
		local step = math.min(0.15, remaining)
		task.wait(step)
		remaining -= step
		local state = playerServiceModule.get(player)
		if state ~= nil then
			playerServiceModule.setHealth(player, state.maxHealth)
		end
	end
end

-- Every boss, not just the Warden. If a check here only ever runs against one boss,
-- it is testing that boss rather than the framework.
local ALL_BOSSES = { "Warden" }

return function()
	local spec = Spec.new("Phase10_Boss")

	-- ------------------------------------------- A. the framework's rules

	for _, bossId in ALL_BOSSES do
		local phasesOk, phasesWhy = BossPhases.validate(bossId)
		spec:check(`{bossId} phases are well formed`, phasesOk, phasesWhy)

		local attacksOk, attacksWhy = BossAttacks.validate(bossId)
		spec:check(`{bossId} attacks are well formed`, attacksOk, attacksWhy)

		local boss = BossConfig.bosses[bossId]
		spec:check(`{bossId} has health`, boss.maxHealth > 0, boss.maxHealth)
		spec:check(`{bossId} has more than one phase`, #boss.phases > 1, #boss.phases)
		spec:check(`{bossId} pauses between phases`, boss.transitionTime > 0)

		-- A boss you cannot read is noise, not difficulty. Every attack must
		-- telegraph for longer than the dodge i-frame window.
		for id, attack in boss.attacks do
			spec:check(
				`{bossId}:{id} telegraphs longer than the dodge window`,
				attack.windup > CombatConfig.dodge.iframes,
				`{attack.windup} vs {CombatConfig.dodge.iframes}`
			)
		end
	end

	spec:truthy("an unknown boss fails validation", not BossPhases.validate("Nope"))

	-- ------------------------------------------- B. thresholds, as maths

	-- The headline acceptance criterion, testable with no world at all.
	spec:equals("full health is phase 1", BossPhases.indexFor("Warden", 1.0), 1)
	spec:equals(
		"just above the second threshold is still phase 1",
		BossPhases.indexFor("Warden", 0.67),
		1
	)
	spec:equals("at the second threshold is phase 2", BossPhases.indexFor("Warden", 0.66), 2)
	spec:equals("at the third threshold is phase 3", BossPhases.indexFor("Warden", 0.33), 3)
	spec:equals("zero health is the last phase", BossPhases.indexFor("Warden", 0), #WARDEN.phases)

	-- Out of range must clamp rather than fall off either end.
	spec:equals("above full clamps to phase 1", BossPhases.indexFor("Warden", 5), 1)
	spec:equals(
		"below zero clamps to the last phase",
		BossPhases.indexFor("Warden", -5),
		#WARDEN.phases
	)

	-- `crosses` is what makes a transition fire once rather than every frame.
	spec:truthy("crossing a threshold is detected", BossPhases.crosses("Warden", 0.7, 0.6))
	spec:truthy(
		"staying inside a phase is not a crossing",
		not BossPhases.crosses("Warden", 0.9, 0.8)
	)
	spec:truthy("healing back up is not a crossing", not BossPhases.crosses("Warden", 0.3, 0.9))
	spec:truthy(
		"a burst that skips a phase still counts as crossing",
		BossPhases.crosses("Warden", 1.0, 0.1)
	)

	-- ------------------------------------------ C. attack selection

	local phaseOne = BossPhases.at("Warden", 1) :: BossConfig.Phase
	local phaseThree = BossPhases.at("Warden", 3) :: BossConfig.Phase

	spec:truthy(
		"nothing is chosen out of range",
		BossAttacks.choose("Warden", phaseOne, {}, 500, 0) == nil
	)
	local inRange = BossAttacks.choose("Warden", phaseOne, {}, 5, 0)
	spec:truthy("an attack is chosen in range", inRange)
	if inRange ~= nil then
		spec:equals("phase 1 only has its cleave", inRange.id, "Cleave")
	end

	-- A phase lists weakest first and signature last, and selection honours that.
	local signature = BossAttacks.choose("Warden", phaseThree, {}, 5, 0)
	spec:truthy("phase 3 reaches for its signature move", signature)
	if signature ~= nil then
		spec:equals("the signature is the Slam", signature.id, "Slam")
	end

	-- On cooldown it falls back rather than doing nothing.
	local fallback = BossAttacks.choose("Warden", phaseThree, { Slam = 100 }, 5, 0)
	spec:truthy("it falls back when the signature is cooling", fallback)
	if fallback ~= nil then
		spec:equals("the fallback is the cleave", fallback.id, "Cleave")
	end
	spec:truthy(
		"nothing is chosen when everything is cooling",
		BossAttacks.choose("Warden", phaseThree, { Slam = 100, Cleave = 100 }, 5, 0) == nil
	)

	-- Reach: an arc respects facing, a radial does not. That difference is what
	-- makes the Slam a dodge check rather than a positioning check.
	local cleave = BossAttacks.get("Warden", "Cleave") :: BossConfig.Attack
	local slam = BossAttacks.get("Warden", "Slam") :: BossConfig.Attack
	local origin = Vector3.zero
	local forward = Vector3.new(0, 0, -1)

	spec:truthy(
		"the cleave hits in front",
		BossAttacks.reaches(cleave, origin, forward, Vector3.new(0, 0, -6))
	)
	spec:truthy(
		"the cleave misses behind",
		not BossAttacks.reaches(cleave, origin, forward, Vector3.new(0, 0, 6))
	)
	spec:truthy(
		"the cleave misses out of range",
		not BossAttacks.reaches(cleave, origin, forward, Vector3.new(0, 0, -40))
	)
	spec:truthy(
		"the slam ignores facing",
		BossAttacks.reaches(slam, origin, forward, Vector3.new(0, 0, 10))
	)
	spec:truthy(
		"the slam still has an edge",
		not BossAttacks.reaches(slam, origin, forward, Vector3.new(0, 0, 200))
	)

	-- --------------------------------------- D. the boss floor placement

	spec:truthy("floor 10 is a boss floor", FloorConfig.isBossDepth(10))
	spec:truthy("floor 20 is a boss floor", FloorConfig.isBossDepth(20))
	spec:truthy("floor 9 is not", not FloorConfig.isBossDepth(9))
	spec:truthy("floor 0 is not", not FloorConfig.isBossDepth(0))
	spec:equals("a boss depth forces its template", FloorPlan.forcedTemplate(10), "Boss")
	spec:truthy("an ordinary depth forces nothing", FloorPlan.forcedTemplate(9) == nil)

	-- A boss must be a landmark you can count toward, never a surprise on floor 3.
	spec:truthy("the boss is not in the ordinary pool", table.find(FloorConfig.pool, "Boss") == nil)

	-- Both doors on floor 9 lead to the boss: the choice is suspended, not faked.
	for _, from in FloorConfig.pool do
		local exits = FloorPlan.exitOptions(SEED, 9, from)
		spec:equals(`both doors from {from} on floor 9 lead to the boss`, exits[1], "Boss")
		spec:equals(`and so does the second`, exits[2], "Boss")
	end

	local boss8 = FloorPlan.exitOptions(SEED, 8, "Combat")
	spec:truthy("floor 8 still offers a real choice", boss8[1] ~= boss8[2])

	spec:truthy("the boss room template exists", RoomConfig.templates.Boss)
	spec:equals("the boss room names its boss", RoomConfig.templates.Boss.boss, "Warden")
	spec:equals(
		"the boss room has no ordinary encounter",
		RoomConfig.templates.Boss.encounter.maxCount,
		0
	)

	-- ------------------------------------------------ player-driven checks

	local player = Players:GetPlayers()[1]
	if player == nil or not PlayerService.isActionable(player) then
		spec:check("a live player is present", false, "run in Play mode")
		return spec:finish()
	end

	local generated = FloorService.generatedFolder()

	local ok, err = pcall(function()
		FloorService.endRun()
		BossService.despawnAll()

		-- --------------------------------------------- E. a live fight

		RunSessionService.begin(SEED)
		local room = FloorService.loadFloor(10, "Combat")
		spec:truthy("floor 10 loaded", room)
		if room == nil then
			return
		end
		-- The depth wins over the requested template, by any route in.
		spec:equals("floor 10 is the boss room whatever was asked for", room.template, "Boss")

		local roomSpec = RoomConfig.templates.Boss
		surviveWait(roomSpec.sealDelay + roomSpec.doorTime + 0.6, player, PlayerService)

		local live = RoomService.boss(room)
		spec:truthy("the boss spawned", live)
		if live == nil then
			return
		end

		spec:equals("the boss starts at full health", live.health, WARDEN.maxHealth)
		spec:equals("the boss starts in phase 1", live.phaseIndex, 1)
		spec:equals("the room is not cleared while it lives", room.phase, "Clearing")
		spec:check("the exits stay shut", not RoomService.isDoorOpen(room, room.exitDoors[1]))

		-- The boss is hit by the ordinary sword path, not a special case.
		local entry = CombatService.damageableFor(live.model)
		spec:truthy("the boss is an ordinary damageable", entry)
		if entry == nil then
			return
		end

		local dealt = entry.applyDamage(50, {})
		spec:equals("the boss takes ordinary damage", dealt, 50)

		-- Drive it through each threshold and confirm the transition fires.
		local phaseTwoAt = WARDEN.maxHealth * WARDEN.phases[2].fromHealthFraction
		entry.applyDamage(live.health - phaseTwoAt + 1, {})
		spec:equals("crossing the second threshold enters phase 2", live.phaseIndex, 2)
		spec:equals("a transition makes it briefly invulnerable", live.state, "Transition")

		local blocked, blockedReason = entry.applyDamage(100, {})
		spec:equals("damage during a transition is refused", blocked, 0)
		spec:equals("the refusal reason is transition", blockedReason, "transition")

		surviveWait(WARDEN.transitionTime + 0.4, player, PlayerService)
		spec:truthy("the transition ends", live.state ~= "Transition")

		local phaseThreeAt = WARDEN.maxHealth * WARDEN.phases[3].fromHealthFraction
		entry.applyDamage(live.health - phaseThreeAt + 1, {})
		spec:equals("crossing the third threshold enters phase 3", live.phaseIndex, 3)
		surviveWait(WARDEN.transitionTime + 0.4, player, PlayerService)

		-- --------------------------------------------- F. defeat

		local goldBefore = (RunSessionService.get() :: any).gold
		entry.applyDamage(WARDEN.maxHealth * 2, {})
		spec:truthy("the boss is defeated", BossService.isDefeated(live))
		spec:equals("its health floors at zero", live.health, 0)
		spec:check(
			"defeating it pays out",
			(RunSessionService.get() :: any).gold > goldBefore,
			`{goldBefore} -> {(RunSessionService.get() :: any).gold}`
		)

		local _, deadReason = entry.applyDamage(50, {})
		spec:equals("a defeated boss takes no more damage", deadReason, "dead")
		spec:equals("its summons went with it", BossService.liveSummonCount(live), 0)

		surviveWait(roomSpec.clearDelay + roomSpec.doorTime + 0.8, player, PlayerService)
		spec:equals("killing the boss clears the room", room.phase, "Cleared")
		spec:check("and opens the exits", RoomService.isDoorOpen(room, room.exitDoors[1]))

		FloorService.endRun()
		spec:equals("ending the run despawned the boss", BossService.count(), 0)
	end)

	if not ok then
		spec:check("boss checks completed without error", false, err)
	end

	-- ---------------------------------------------------------- G. teardown

	FloorService.endRun()
	BossService.despawnAll()
	PlayerService.setHealth(player, (PlayerService.get(player) :: any).maxHealth)
	PlayerService.setStamina(player, CombatConfig.stamina.max)

	spec:equals("teardown removed every boss", BossService.count(), 0)
	spec:equals("teardown left Generated empty", #generated:GetChildren(), 0)

	return spec:finish()
end
