--!strict
-- Watches a run happen, then asks TypeSafe what it was like.
--
-- This service is a pure OBSERVER. It subscribes to events the other services already
-- fire and adds no edge back into them, which is why it can sit at the very end of the
-- boot order and why nothing else has to know it exists. Deleting it would change
-- nothing about how the game plays.
--
-- The review itself runs in a task.spawn AFTER the run is already over, so the ~615ms
-- round trip is never on anything's critical path. If the call fails, times out, or
-- HTTP is simply disabled for the place, the run just ends up without a verdict.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FloorConfig = require(ReplicatedStorage.Shared.FloorConfig)
local ReviewConfig = require(ReplicatedStorage.Shared.ReviewConfig)
local BossService = require(script.Parent.BossService)
local EnemyService = require(script.Parent.EnemyService)
local FloorService = require(script.Parent.FloorService)
local InventoryService = require(script.Parent.InventoryService)
local PlayerService = require(script.Parent.PlayerService)
local RoomService = require(script.Parent.RoomService)
local RunSessionService = require(script.Parent.RunSessionService)
local TypeSafeClient = require(script.Parent.Parent.Net.TypeSafeClient)

local RunReviewService = {}

export type Telemetry = {
	seed: number,
	path: { number },
	startedAt: number,
	floorsCleared: number,
	deathFloor: number?,
	-- The weapon field of the last damage that landed: an enemy kind, or `boss:attack`.
	-- Promoted to killedBy only when the run actually ended in a death, because a
	-- killedBy on a survived run is a lie and the rootCause question reads it.
	lastDamageSource: string?,
	killedBy: string?,
	runDurationSec: number,
	damageTaken: number,
	healingFound: number,
	itemsFound: number,
	weaponsFound: number,
	enemiesKilled: number,
	bossesDefeated: number,
	goldEarned: number,
	avgFloorTimeSec: number,
	lastFloorTimeSec: number,
	largestEncounter: number,
}

export type Verdict = {
	telemetry: Telemetry,
	-- Index into ReviewConfig.frustrationLevels, or nil when unclassified. The index
	-- rather than the float: the float drifts between identical calls, the level
	-- does not.
	frustrationLevel: number?,
	frustrationLabel: string?,
	difficultySpike: boolean?,
	spikeProbability: number?,
	rootCause: string?,
	rootCauseConfidence: number?,
	unclassified: { string },
	failure: string?,
	elapsed: number?,
}

local current: Telemetry? = nil
local lastFloorAt = 0
local floorTimes: { number } = {}
local history: { Verdict } = {}
local enabled = ReviewConfig.enabled

RunReviewService.onReviewed = Instance.new("BindableEvent")

-- The spec suite runs against a live world where runs start and end, and a run ending
-- fires a network request. That is exactly the kind of self-acting behaviour RunAll
-- quiesces, alongside the practice skeleton. Telemetry keeps accumulating either way;
-- only the outbound call is suppressed.
function RunReviewService.setEnabled(value: boolean)
	enabled = value
end

function RunReviewService.isEnabled(): boolean
	return enabled
end

-- ------------------------------------------------------------------ gather

local function blankTelemetry(seed: number): Telemetry
	return {
		seed = seed,
		path = {},
		startedAt = os.clock(),
		floorsCleared = 0,
		deathFloor = nil,
		lastDamageSource = nil,
		killedBy = nil,
		runDurationSec = 0,
		damageTaken = 0,
		healingFound = 0,
		itemsFound = 0,
		weaponsFound = 0,
		enemiesKilled = 0,
		bossesDefeated = 0,
		goldEarned = 0,
		avgFloorTimeSec = 0,
		lastFloorTimeSec = 0,
		largestEncounter = 0,
	}
end

function RunReviewService.currentTelemetry(): Telemetry?
	return current
end

function RunReviewService.history(): { Verdict }
	return history
end

function RunReviewService.lastVerdict(): Verdict?
	return history[#history]
end

-- ------------------------------------------------------------------ verdict

-- Reads one answer, applying the confidence floor. Anything the model is unsure about
-- is recorded as unclassified rather than believed: measurement showed every answer
-- at or above 0.88 was correct and both wrong answers self-reported below 0.45.
local function accept(answer: any, verdict: Verdict, label: string): boolean
	if answer == nil then
		table.insert(verdict.unclassified, label)
		return false
	end
	local confidence = answer.confidence
	if typeof(confidence) == "number" and confidence < ReviewConfig.confidenceFloor then
		table.insert(verdict.unclassified, label)
		return false
	end
	return true
end

local function interpret(verdict: Verdict, answers: { [string]: any })
	local frustration = answers.frustration
	if typeof(frustration) == "table" and typeof(frustration.score) ~= "number" then
		frustration = nil
	end
	if accept(frustration, verdict, "frustration") then
		-- Round the drifting float to a stable level index.
		local level =
			math.clamp(math.floor(frustration.score + 0.5) + 1, 1, #ReviewConfig.frustrationLevels)
		verdict.frustrationLevel = level
		verdict.frustrationLabel = ReviewConfig.frustrationLevels[level]
	end

	-- A Noul has no confidence field; it IS a probability, so the honest reading is
	-- to treat the middle as "do not know" rather than to round it.
	local spike = answers.difficultySpike
	if spike ~= nil and typeof(spike.noul) == "number" then
		verdict.spikeProbability = spike.noul
		if spike.noul >= 0.7 then
			verdict.difficultySpike = true
		elseif spike.noul <= 0.3 then
			verdict.difficultySpike = false
		else
			table.insert(verdict.unclassified, "difficultySpike")
		end
	else
		table.insert(verdict.unclassified, "difficultySpike")
	end

	local cause = answers.rootCause
	if accept(cause, verdict, "rootCause") then
		verdict.rootCause = cause.choice
		verdict.rootCauseConfidence = cause.confidence
	end
end

RunReviewService.interpret = interpret

-- Shaped for the model, not for us: only fields that help answer the three questions.
local function buildState(telemetry: Telemetry): { [string]: any }
	return {
		deathFloor = telemetry.deathFloor,
		killedBy = telemetry.killedBy,
		floorsCleared = telemetry.floorsCleared,
		runDurationSec = math.floor(telemetry.runDurationSec),
		damageTakenTotal = math.floor(telemetry.damageTaken),
		healingFound = telemetry.healingFound,
		itemsFound = telemetry.itemsFound,
		weaponUpgradesFound = telemetry.weaponsFound,
		enemiesKilled = telemetry.enemiesKilled,
		bossesDefeated = telemetry.bossesDefeated,
		goldEarned = telemetry.goldEarned,
		avgFloorTimeSec = math.floor(telemetry.avgFloorTimeSec),
		lastFloorTimeSec = math.floor(telemetry.lastFloorTimeSec),
		largestEncounterSize = telemetry.largestEncounter,
		bossFloorInterval = FloorConfig.bossEvery,
	}
end

RunReviewService.buildState = buildState

function RunReviewService.review(telemetry: Telemetry): Verdict
	local verdict: Verdict = {
		telemetry = telemetry,
		unclassified = {},
	}

	local response = TypeSafeClient.ask(buildState(telemetry), ReviewConfig.buildQuestions())
	verdict.elapsed = response.elapsed

	if not response.ok or response.answers == nil then
		verdict.failure = response.failure
		return verdict
	end

	interpret(verdict, response.answers)
	return verdict
end

-- ------------------------------------------------------------------ hooks

local function beginRun()
	local run = RunSessionService.get()
	if run == nil then
		return
	end
	current = blankTelemetry(run.seed)
	table.clear(floorTimes)
	lastFloorAt = os.clock()
end

local function endRun()
	local telemetry = current
	current = nil
	if telemetry == nil then
		return
	end

	local run = RunSessionService.get()
	if run ~= nil then
		telemetry.goldEarned = run.gold
		telemetry.floorsCleared = math.max(0, run.floor - 1)
		telemetry.path = table.clone(run.path)

		-- Whether the run ended in death is read from player state rather than from
		-- event ordering: FloorService also listens to onDied, and two listeners on
		-- one event have no guaranteed order.
		for _, state in PlayerService.all() do
			if not state.alive then
				telemetry.deathFloor = run.floor
			end
		end
	end

	telemetry.runDurationSec = os.clock() - telemetry.startedAt

	if telemetry.deathFloor ~= nil then
		telemetry.killedBy = telemetry.lastDamageSource
	end

	-- The floor being stood on when the run ended has not been pushed yet: floorTimes
	-- gains an entry when the NEXT floor loads, and there is no next floor.
	table.insert(floorTimes, os.clock() - lastFloorAt)

	local total = 0
	for _, seconds in floorTimes do
		total += seconds
	end
	if #floorTimes > 0 then
		telemetry.avgFloorTimeSec = total / #floorTimes
		telemetry.lastFloorTimeSec = floorTimes[#floorTimes]
	end

	if not enabled then
		return
	end

	-- The whole point: off the tick, after the fact, nothing waiting on it.
	task.spawn(function()
		local verdict = RunReviewService.review(telemetry)
		table.insert(history, verdict)
		RunReviewService.onReviewed:Fire(verdict)

		if verdict.failure ~= nil then
			print(`[OMF] run review unavailable ({verdict.failure}) — seed:{telemetry.seed}`)
			return
		end
		print(
			`[OMF] run review — seed:{telemetry.seed} `
				.. `frustration:{verdict.frustrationLabel or "?"} `
				.. `spike:{tostring(verdict.difficultySpike)} `
				.. `cause:{verdict.rootCause or "unclassified"}`
		)
	end)
end

function RunReviewService.Init()
	enabled = ReviewConfig.enabled
	current = nil
	table.clear(floorTimes)
	table.clear(history)
end

function RunReviewService.Start()
	FloorService.onFloorLoaded.Event:Connect(function(_depth: number, room: any)
		if current == nil then
			-- Floor 1 loads as part of starting a run, so this is where one is noticed.
			beginRun()
			if current == nil then
				return
			end
		else
			-- Close out the floor just left. The floor being entered is timed when the
			-- one after it loads, or by endRun if there is no one after it.
			local now = os.clock()
			table.insert(floorTimes, now - lastFloorAt)
			lastFloorAt = now
		end

		if room ~= nil then
			local size = RoomService.expectedEnemyCount(room)
			if size > current.largestEncounter then
				current.largestEncounter = size
			end
		end
	end)

	FloorService.onRunEnded.Event:Connect(endRun)

	PlayerService.onDamaged.Event:Connect(function(_player: Player, dealt: number, source: string?)
		if current == nil then
			return
		end
		current.damageTaken += dealt
		if source ~= nil then
			current.lastDamageSource = source
		end
	end)

	EnemyService.onKilled.Event:Connect(function()
		if current ~= nil then
			current.enemiesKilled += 1
		end
	end)

	BossService.onDefeated.Event:Connect(function()
		if current ~= nil then
			current.bossesDefeated += 1
		end
	end)

	InventoryService.onPickedUp.Event:Connect(
		function(_player: Player, _item: string, _gold: number, kind: string?)
			if current == nil then
				return
			end
			current.itemsFound += 1
			if kind == "weapon" then
				current.weaponsFound += 1
			end
		end
	)

	RoomService.onPrizeTaken.Event:Connect(function(_room: any, _player: Player, kind: string)
		if current ~= nil and kind == "heal" then
			current.healingFound += 1
		end
	end)
end

return RunReviewService
