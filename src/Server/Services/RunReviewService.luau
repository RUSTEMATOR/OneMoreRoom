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

local BalanceDigestConfig = require(ReplicatedStorage.Shared.BalanceDigestConfig)
local FloorConfig = require(ReplicatedStorage.Shared.FloorConfig)
local FloorPlan = require(ReplicatedStorage.Shared.FloorPlan)
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

-- Reads one answer against a per-question floor, not a single global one -- see the
-- comment on ReviewConfig's two floors for why frustration and rootCause differ.
-- Anything below its floor is recorded as unclassified rather than believed.
local function accept(answer: any, verdict: Verdict, label: string, floor: number): boolean
	if answer == nil then
		table.insert(verdict.unclassified, label)
		return false
	end
	local confidence = answer.confidence
	if typeof(confidence) == "number" and confidence < floor then
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
	if accept(frustration, verdict, "frustration", ReviewConfig.frustrationConfidenceFloor) then
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
	if accept(cause, verdict, "rootCause", ReviewConfig.rootCauseConfidenceFloor) then
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

-- -------------------------------------------------------------------- digest

-- One completed run, boiled down to what an aggregate question needs. Deliberately
-- does not carry the seed into the outbound state: it identifies the run to US, and
-- means nothing to the model beyond inviting it to read a pattern into a number that
-- has none -- the same reasoning buildState above already applies per-run.
export type RunSummary = {
	seed: number,
	floorsCleared: number,
	deathFloor: number?,
	rootCause: string?,
	frustrationLevel: number?,
	frustrationLabel: string?,
	difficultySpike: boolean?,
	rooms: { string },
}

export type DigestVerdict = {
	sampleSize: number,
	roomTypeStandout: string?,
	roomTypeConfidence: number?,
	curveShape: string?,
	curveConfidence: number?,
	consistent: boolean?,
	consistencyProbability: number?,
	unclassified: { string },
	failure: string?,
	elapsed: number?,
}

-- Replays the branch a run actually walked, from its seed and path, to recover the
-- room type visited at every depth. This is possible only because generation is a
-- pure function of (seed, depth, template) -- the same property that makes the
-- golden-hash regression test arithmetic rather than a playthrough. Telemetry never
-- had to track room types as it went; they are always re-derivable after the fact.
local function deriveRoomSequence(seed: number, path: { number }): { string }
	local sequence: { string } = {}
	local template = FloorPlan.forcedTemplate(1) or FloorPlan.startingTemplate(seed)
	table.insert(sequence, template)

	for depth, choice in path do
		local forced = FloorPlan.forcedTemplate(depth + 1)
		if forced ~= nil then
			template = forced
		else
			local options = FloorPlan.exitOptions(seed, depth, template)
			template = options[choice] or options[1]
		end
		table.insert(sequence, template)
	end

	return sequence
end

local function buildRunSummary(verdict: Verdict): RunSummary
	local telemetry = verdict.telemetry
	return {
		seed = telemetry.seed,
		floorsCleared = telemetry.floorsCleared,
		deathFloor = telemetry.deathFloor,
		rootCause = verdict.rootCause,
		frustrationLevel = verdict.frustrationLevel,
		frustrationLabel = verdict.frustrationLabel,
		difficultySpike = verdict.difficultySpike,
		rooms = deriveRoomSequence(telemetry.seed, telemetry.path),
	}
end

RunReviewService.buildRunSummary = buildRunSummary

-- Shaped for the model: the label rather than the raw level index (a language judge
-- reads "grindy but tolerable" more reliably than a bare 3), and no seed, for the
-- same reason a single run's state carries none.
local function buildDigestState(summaries: { RunSummary }): { [string]: any }
	local rows = {}
	for _, s in summaries do
		table.insert(rows, {
			floorsCleared = s.floorsCleared,
			deathFloor = s.deathFloor,
			rootCause = s.rootCause,
			frustration = s.frustrationLabel,
			difficultySpike = s.difficultySpike,
			rooms = s.rooms,
		})
	end
	return { runs = rows }
end

RunReviewService.buildDigestState = buildDigestState

local function interpretDigest(verdict: DigestVerdict, answers: { [string]: any })
	local room = answers.roomTypeStandout
	if
		room ~= nil
		and typeof(room.confidence) == "number"
		and room.confidence >= BalanceDigestConfig.choiceConfidenceFloor
	then
		verdict.roomTypeStandout = room.choice
		verdict.roomTypeConfidence = room.confidence
	else
		table.insert(verdict.unclassified, "roomTypeStandout")
	end

	local curve = answers.curveShape
	if
		curve ~= nil
		and typeof(curve.confidence) == "number"
		and curve.confidence >= BalanceDigestConfig.choiceConfidenceFloor
	then
		verdict.curveShape = curve.choice
		verdict.curveConfidence = curve.confidence
	else
		table.insert(verdict.unclassified, "curveShape")
	end

	-- Same treatment as difficultySpike above: a Noul IS a probability, so the
	-- middle band is "do not know", not a value to round.
	local consistent = answers.consistent
	if consistent ~= nil and typeof(consistent.noul) == "number" then
		verdict.consistencyProbability = consistent.noul
		if consistent.noul >= 0.7 then
			verdict.consistent = true
		elseif consistent.noul <= 0.3 then
			verdict.consistent = false
		else
			table.insert(verdict.unclassified, "consistent")
		end
	else
		table.insert(verdict.unclassified, "consistent")
	end
end

RunReviewService.interpretDigest = interpretDigest

function RunReviewService.digestSampleSize(): number
	return #history
end

-- Aggregate report over every review this session has recorded. YIELDS exactly like
-- TypeSafeClient.ask does -- an on-demand admin tool, never called from a tick or a
-- lifecycle method, so that is fine, but a caller reaching this through execute_luau
-- should task.spawn it and poll rather than block on it, the same as OMF_RunSpecs.
function RunReviewService.runDigest(): DigestVerdict
	local sampleSize = #history
	if sampleSize < BalanceDigestConfig.minSampleSize then
		return {
			sampleSize = sampleSize,
			unclassified = {},
			failure = "insufficient_data",
		}
	end

	local summaries: { RunSummary } = {}
	for _, verdict in history do
		table.insert(summaries, buildRunSummary(verdict))
	end

	local verdict: DigestVerdict = { sampleSize = sampleSize, unclassified = {} }
	local response = TypeSafeClient.ask(
		buildDigestState(summaries),
		BalanceDigestConfig.buildQuestions(FloorConfig.pool)
	)
	verdict.elapsed = response.elapsed

	if not response.ok or response.answers == nil then
		verdict.failure = response.failure
		return verdict
	end

	interpretDigest(verdict, response.answers)
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
