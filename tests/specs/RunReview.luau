--!strict
-- The post-run review path: telemetry in, a verdict out.
--
-- Not a roadmap phase, so it is not named for one. It is an observer bolted onto the
-- side of a finished run, and the point of this spec is that the bolt holds without a
-- network and without an API key: TypeSafeClient takes an injectable transport, so the
-- whole path -- payload shape, retries, decode failures, confidence gating -- runs
-- offline and deterministically.
--
-- What this spec deliberately does NOT assert is what the model answers. That is not a
-- property of this code, it drifts between identical calls (0.83/0.82/0.80 measured on
-- one Choice), and a spec that pinned it would fail for reasons nobody could fix. What
-- IS asserted is how we treat an answer once it arrives.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Spec = require(script.Parent.Spec)

local ReviewConfig = require(ReplicatedStorage.Shared.ReviewConfig)
local FloorService = require(ServerScriptService.Services.FloorService)
local PlayerService = require(ServerScriptService.Services.PlayerService)
local RunReviewService = require(ServerScriptService.Services.RunReviewService)
local TypeSafeClient = require(ServerScriptService.Net.TypeSafeClient)

local SEED = 771122

-- A finished run that died on a boss floor, worn down and short on healing. Used as
-- the input everywhere a payload or a verdict has to be built from something.
local function sampleTelemetry(): any
	return {
		seed = SEED,
		path = { 1, 2, 1, 1 },
		startedAt = 0,
		floorsCleared = 9,
		deathFloor = 10,
		lastDamageSource = "bonecrusher:slam",
		killedBy = "bonecrusher:slam",
		runDurationSec = 742.5,
		damageTaken = 613.25,
		healingFound = 1,
		itemsFound = 6,
		weaponsFound = 1,
		enemiesKilled = 38,
		bossesDefeated = 0,
		goldEarned = 410,
		avgFloorTimeSec = 74.25,
		lastFloorTimeSec = 131.0,
		largestEncounter = 7,
	}
end

-- Builds a transport that replays a scripted list of (ok, status, body) triples, one
-- per attempt, and records what it was handed.
local function scriptedTransport(steps: { { any } })
	local log = { calls = 0, urls = {}, bodies = {}, headers = {} :: { any } }
	local transport = function(url: string, headers: any, body: string)
		log.calls += 1
		table.insert(log.urls, url)
		table.insert(log.bodies, body)
		table.insert(log.headers, headers)
		local step = steps[math.min(log.calls, #steps)]
		return step[1], step[2], step[3]
	end
	return transport, log
end

local function okBody(answers: any): string
	return HttpService:JSONEncode({ answers = answers })
end

return function()
	local spec = Spec.new("RunReview")

	-- --------------------------------------------------- A. question design

	spec:check(
		"there are frustration levels to score against",
		#ReviewConfig.frustrationLevels >= 3
	)
	spec:check(
		"the frustration confidence floor is an actual threshold",
		ReviewConfig.frustrationConfidenceFloor > 0 and ReviewConfig.frustrationConfidenceFloor < 1,
		ReviewConfig.frustrationConfidenceFloor
	)
	spec:check(
		"the rootCause confidence floor is an actual threshold",
		ReviewConfig.rootCauseConfidenceFloor > 0 and ReviewConfig.rootCauseConfidenceFloor < 1,
		ReviewConfig.rootCauseConfidenceFloor
	)
	-- Per the live docs' own guidance against a single uniform floor: a wrong
	-- rootCause actively misleads a QA session, a wrong frustration level is a soft
	-- miss, so rootCause earns the harder bar.
	spec:check(
		"rootCause is held to a stricter bar than frustration",
		ReviewConfig.rootCauseConfidenceFloor > ReviewConfig.frustrationConfidenceFloor,
		`{ReviewConfig.rootCauseConfidenceFloor} vs {ReviewConfig.frustrationConfidenceFloor}`
	)
	spec:check("the endpoint is https", ReviewConfig.endpoint:sub(1, 8) == "https://")
	spec:check(
		"the key is read from the secret store, not a literal",
		not ReviewConfig.secretKey:find("apikey"),
		ReviewConfig.secretKey
	)

	local questions = ReviewConfig.buildQuestions()
	local count = 0
	for _, _question in questions do
		count += 1
	end
	-- Batched deliberately: three independent judgments over one state cost one round
	-- trip instead of three, and they cannot see each other's answers anyway.
	spec:equals("all three questions go in one request", count, 3)
	spec:equals("frustration is a score", questions.frustration.type, "score")
	spec:equals("difficultySpike is a noul", questions.difficultySpike.type, "noul")
	spec:equals("rootCause is a choice", questions.rootCause.type, "choice")
	for id, question in questions do
		spec:check(
			`{id} carries instructions a model could act on`,
			typeof(question.instructions) == "string" and #question.instructions > 20
		)
		spec:truthy(`{id} defines its criteria`, question.criteria)
	end

	-- This is the bug the experiments actually found. Without a no-match outcome the
	-- rootCause question confidently answered "attrition" for a run nobody died in,
	-- because every option it was offered presumed a death.
	spec:truthy("rootCause offers an outcome for runs with no death", ReviewConfig.causes.survived)

	-- --------------------------------------------------- B. the payload

	local telemetry = sampleTelemetry()
	local state = RunReviewService.buildState(telemetry)

	spec:equals("the payload carries the death floor", state.deathFloor, 10)
	spec:equals(
		"the payload carries what landed the killing blow",
		state.killedBy,
		"bonecrusher:slam"
	)
	spec:equals("the payload carries floors cleared", state.floorsCleared, 9)
	spec:equals("the payload carries the largest encounter", state.largestEncounterSize, 7)
	-- The model has no idea a boss lives on every tenth floor unless it is told, and
	-- boss_wall is unanswerable without it.
	spec:truthy("the payload explains where bosses are", state.bossFloorInterval)
	-- Floats are quantized: a duration of 742.5 seconds carries no information the
	-- model can use that 742 does not, and the noise invites spurious precision.
	spec:equals("durations are whole seconds", state.runDurationSec, 742)
	spec:equals("damage is a whole number", state.damageTakenTotal, 613)
	-- The seed identifies the run to US. It means nothing to the model and would only
	-- invite it to read patterns into a number that has none.
	spec:equals("the seed is not sent", state.seed, nil)
	spec:equals("the path is not sent", state.path, nil)
	spec:check(
		"the payload survives encoding",
		pcall(function()
			HttpService:JSONEncode(state)
		end)
	)

	-- --------------------------------------------------- C. reading answers

	local function verdictFrom(answers: any): any
		local verdict = { telemetry = telemetry, unclassified = {} }
		RunReviewService.interpret(verdict, answers)
		return verdict
	end

	local confident = verdictFrom({
		frustration = { score = 3.08, confidence = 0.91 },
		difficultySpike = { noul = 0.94 },
		rootCause = { choice = "boss_wall", confidence = 0.9 },
	})
	spec:equals("a confident score becomes a level", confident.frustrationLevel, 4)
	spec:equals(
		"the level carries its label",
		confident.frustrationLabel,
		ReviewConfig.frustrationLevels[4]
	)
	spec:equals("a high noul reads as yes", confident.difficultySpike, true)
	spec:equals("a confident choice is taken", confident.rootCause, "boss_wall")
	spec:equals("nothing is left unclassified", #confident.unclassified, 0)

	-- The drift measured between identical calls was ~0.04. Both of these must land on
	-- the same level, or the verdict is unusable for comparing runs to each other.
	local drifted = verdictFrom({
		frustration = { score = 3.04, confidence = 0.9 },
		difficultySpike = { noul = 0.94 },
		rootCause = { choice = "boss_wall", confidence = 0.9 },
	})
	spec:equals(
		"drift within a level does not change the verdict",
		drifted.frustrationLevel,
		confident.frustrationLevel
	)

	local unsure = verdictFrom({
		frustration = { score = 2.0, confidence = 0.26 },
		difficultySpike = { noul = 0.5 },
		rootCause = { choice = "attrition", confidence = 0.42 },
	})
	spec:equals("a score below the floor is not believed", unsure.frustrationLevel, nil)
	-- A Noul near 0.5 means "as likely as not", not "medium intensity". Rounding it
	-- would invent an answer the model did not give.
	spec:equals("a noul in the middle is not rounded", unsure.difficultySpike, nil)
	spec:equals("a choice below the floor is not taken", unsure.rootCause, nil)
	spec:equals("everything unsure is recorded as such", #unsure.unclassified, 3)
	-- The probability is kept even when the verdict is not, because it is the thing a
	-- human would want to look at when deciding whether the floor is set right.
	spec:equals("the raw probability is still recorded", unsure.spikeProbability, 0.5)

	local low = verdictFrom({
		frustration = { score = 0.1, confidence = 0.95 },
		difficultySpike = { noul = 0.04 },
		rootCause = { choice = "survived", confidence = 0.99 },
	})
	spec:equals("the lowest score clamps to the first level", low.frustrationLevel, 1)
	spec:equals("a low noul reads as no", low.difficultySpike, false)

	local high = verdictFrom({ frustration = { score = 99, confidence = 0.95 } })
	spec:equals(
		"an out-of-range score clamps rather than indexing off the end",
		high.frustrationLevel,
		#ReviewConfig.frustrationLevels
	)

	local empty = verdictFrom({})
	spec:equals("a reply missing every answer classifies nothing", #empty.unclassified, 3)

	-- A malformed answer must be ignored, not arithmetic'd into a crash inside the
	-- task.spawn where nobody would see the traceback.
	local malformed = verdictFrom({
		frustration = { score = "very", confidence = 0.99 },
		difficultySpike = { noul = "yes" },
	})
	spec:equals("a non-numeric score is refused", malformed.frustrationLevel, nil)
	spec:equals("a non-numeric noul is refused", malformed.difficultySpike, nil)

	-- --------------------------------------------------- D. the transport

	-- Deliberately NOT enabling outbound reviews here. This section calls review()
	-- directly, so it does not need them -- and with them on, a run ending elsewhere
	-- in the live world landed a third request on the retry transport during its
	-- backoff, failing an attempt count for a reason that had nothing to do with retries.
	local restoreEnabled = RunReviewService.isEnabled()

	local transportOk, transportErr = pcall(function()
		local happyAnswers = {
			frustration = { score = 3.0, confidence = 0.9 },
			difficultySpike = { noul = 0.8 },
			rootCause = { choice = "boss_wall", confidence = 0.88 },
		}

		local transport, log = scriptedTransport({ { true, 200, okBody(happyAnswers) } })
		TypeSafeClient.setTransport(transport)

		local verdict = RunReviewService.review(telemetry)
		spec:equals("one request is sent", log.calls, 1)
		spec:equals("it goes to the configured endpoint", log.urls[1], ReviewConfig.endpoint)
		spec:equals("no failure is recorded", verdict.failure, nil)
		spec:equals("the verdict carries the cause", verdict.rootCause, "boss_wall")
		spec:equals("the verdict carries the spike", verdict.difficultySpike, true)
		spec:truthy("the round trip is timed", verdict.elapsed)

		local sent = HttpService:JSONDecode(log.bodies[1])
		spec:equals("the request names the model", sent.model, ReviewConfig.model)
		spec:truthy("the request carries state", sent.state)
		spec:truthy("the request carries questions", sent.questions)
		spec:equals("the state sent is the state built", sent.state.deathFloor, 10)
		-- The one thing that must never appear in an outbound body.
		spec:check(
			"no key material is in the body",
			log.bodies[1]:find("apikey_") == nil,
			"body carries a literal key"
		)

		-- 429 and 529 are the documented retryable statuses. Anything else is a real
		-- answer and retrying it just burns the budget.
		local retryTransport, retryLog = scriptedTransport({
			{ true, 429, "" },
			{ true, 200, okBody(happyAnswers) },
		})
		TypeSafeClient.setTransport(retryTransport)
		local retried = TypeSafeClient.ask({}, {})
		spec:truthy("a 429 is retried to success", retried.ok)
		spec:equals("it took two attempts", retryLog.calls, 2)

		local hardTransport, hardLog = scriptedTransport({ { true, 400, "bad request" } })
		TypeSafeClient.setTransport(hardTransport)
		local hard = TypeSafeClient.ask({}, {})
		spec:equals("a 400 is not retried", hardLog.calls, 1)
		spec:equals("a 400 reports badstatus", hard.failure, "badstatus")
		spec:equals("the status is kept for diagnosis", hard.statusCode, 400)

		local giveUpTransport, giveUpLog = scriptedTransport({ { true, 529, "" } })
		TypeSafeClient.setTransport(giveUpTransport)
		local gaveUp = TypeSafeClient.ask({}, {})
		spec:equals("retries are bounded", giveUpLog.calls, ReviewConfig.request.maxAttempts)
		spec:equals("exhausted retries report badstatus", gaveUp.failure, "badstatus")

		TypeSafeClient.setTransport(scriptedTransport({ { true, 200, "not json at all" } }))
		spec:equals(
			"an undecodable body reports decode",
			TypeSafeClient.ask({}, {}).failure,
			"decode"
		)

		TypeSafeClient.setTransport(scriptedTransport({ { true, 200, okBody(nil) } }))
		spec:equals(
			"a 200 with no answers reports decode",
			TypeSafeClient.ask({}, {}).failure,
			"decode"
		)

		-- HTTP being disabled for the place is the state this project is in right now,
		-- and it must degrade to a missing verdict rather than an error.
		TypeSafeClient.setTransport(scriptedTransport({
			{ false, 0, "Http requests are not enabled" },
		}))
		local offline = RunReviewService.review(telemetry)
		spec:equals("an unreachable service reports transport", offline.failure, "transport")
		spec:equals("and produces no verdict", offline.rootCause, nil)
		spec:truthy("but still carries the telemetry it gathered", offline.telemetry)
	end)

	if not transportOk then
		spec:check("transport checks completed without error", false, transportErr)
	end

	-- --------------------------------------------------- E. a live run

	local player = Players:GetPlayers()[1]
	if player == nil or not PlayerService.isActionable(player) then
		TypeSafeClient.setTransport(nil)
		RunReviewService.setEnabled(restoreEnabled)
		spec:check("a live player is present", false, "run in Play mode")
		return spec:finish()
	end

	local liveOk, liveErr = pcall(function()
		local liveAnswers = {
			frustration = { score = 2.0, confidence = 0.92 },
			difficultySpike = { noul = 0.12 },
			rootCause = { choice = "survived", confidence = 0.97 },
		}
		local liveTransport, liveLog = scriptedTransport({ { true, 200, okBody(liveAnswers) } })
		TypeSafeClient.setTransport(liveTransport)
		RunReviewService.setEnabled(true)

		local before = #RunReviewService.history()

		local room = FloorService.beginRun(SEED)
		spec:truthy("a run begins", room)

		-- This place runs Deferred signals, so onFloorLoaded listeners have not run
		-- when beginRun returns. Every observer in this project is one resumption
		-- point behind the thing it observes.
		task.wait()
		local gathering = RunReviewService.currentTelemetry()
		spec:truthy("the observer notices the run starting", gathering)
		if gathering ~= nil then
			spec:equals("it records the run's seed", gathering.seed, SEED)
		end

		-- Damage goes through the real choke point, not by poking the accumulator:
		-- the thing worth proving is that the observer is wired to the event the
		-- game actually fires. Measured as a delta, because the floor's own enemies
		-- are alive and a stray hit would otherwise fail this for the wrong reason.
		local baseline = if gathering ~= nil then gathering.damageTaken else 0
		PlayerService.applyDamage(player, 7, { source = nil, weapon = "skeleton" })
		task.wait(0.1)
		gathering = RunReviewService.currentTelemetry()
		local observed = 0
		if gathering ~= nil then
			observed = gathering.damageTaken - baseline
			spec:check("damage taken accumulates", observed >= 7, observed)
			spec:equals("the damage source is remembered", gathering.lastDamageSource, "skeleton")
		end

		FloorService.endRun()

		-- The review runs in a task.spawn after the run is over, so it is not there
		-- the instant endRun returns -- which is the whole point.
		local deadline = os.clock() + 3
		while #RunReviewService.history() == before and os.clock() < deadline do
			task.wait(0.05)
		end

		spec:equals(
			"the finished run produced exactly one verdict",
			#RunReviewService.history(),
			before + 1
		)
		spec:check("the review sent its request", liveLog.calls >= 1, liveLog.calls)

		local verdict = RunReviewService.lastVerdict()
		spec:truthy("the verdict is recorded", verdict)
		if verdict ~= nil then
			spec:equals("it is the verdict for this run", verdict.telemetry.seed, SEED)
			spec:check("it carries the damage observed", verdict.telemetry.damageTaken >= 7)
			spec:equals("it read the model's answer", verdict.rootCause, "survived")
			-- Surviving is the honest reading here: the run was ended, not lost.
			spec:equals("a run that was ended is not a death", verdict.telemetry.deathFloor, nil)
			spec:equals("and so carries no killedBy", verdict.telemetry.killedBy, nil)
			spec:check("the last floor was timed", verdict.telemetry.lastFloorTimeSec > 0)
		end

		spec:equals("the observer stops gathering", RunReviewService.currentTelemetry(), nil)

		-- Dying is the other way a run ends, and it must be recorded as a death even
		-- though FloorService listens to onDied too and listener order is undefined.
		local deathTransport, deathLog = scriptedTransport({ { true, 200, okBody(liveAnswers) } })
		TypeSafeClient.setTransport(deathTransport)

		local secondBefore = #RunReviewService.history()
		FloorService.beginRun(SEED)
		task.wait(0.2)
		PlayerService.setHealth(player, 1)
		PlayerService.handleDeath(player, PlayerService.generation(player))

		deadline = os.clock() + 3
		while #RunReviewService.history() == secondBefore and os.clock() < deadline do
			task.wait(0.05)
		end

		spec:equals("dying also produces a verdict", #RunReviewService.history(), secondBefore + 1)
		spec:check("the death review was sent", deathLog.calls >= 1, deathLog.calls)
		local death = RunReviewService.lastVerdict()
		if death ~= nil then
			spec:truthy("the death floor is recorded", death.telemetry.deathFloor)
		end
	end)

	if not liveOk then
		spec:check("live review checks completed without error", false, liveErr)
	end

	-- --------------------------------------------------------- F. teardown

	TypeSafeClient.setTransport(nil)
	RunReviewService.setEnabled(restoreEnabled)
	FloorService.endRun()
	task.wait(0.2)
	spec:truthy("the run is over", not FloorService.isRunActive())
	spec:equals("nothing is still being gathered", RunReviewService.currentTelemetry(), nil)

	return spec:finish()
end
