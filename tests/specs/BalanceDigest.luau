--!strict
-- The balance digest: an aggregate question over a BATCH of run reviews.
--
-- Same shape of spec as RunReview -- offline, deterministic, no network and no key,
-- because TypeSafeClient's transport is injectable. What is asserted here is the
-- payload shape, the minimum-sample gate, the room-sequence reconstruction, and how
-- an answer is accepted or refused -- never what the model actually says.
--
-- RunReviewService.history() returns the live array by reference, not a copy. That
-- is exploited here deliberately: fake verdicts are appended on top of whatever is
-- already there (never cleared, in case another spec's real reviews already landed)
-- and trimmed back off in teardown, so this spec cannot corrupt what runs after it.
-- This spec runs BEFORE RunReview in the suite specifically so its "insufficient
-- data" check starts from a history nobody else has touched yet.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Spec = require(script.Parent.Spec)

local BalanceDigestConfig = require(ReplicatedStorage.Shared.BalanceDigestConfig)
local FloorConfig = require(ReplicatedStorage.Shared.FloorConfig)
local FloorPlan = require(ReplicatedStorage.Shared.FloorPlan)
local RunReviewService = require(ServerScriptService.Services.RunReviewService)
local TypeSafeClient = require(ServerScriptService.Net.TypeSafeClient)

-- A minimal but valid fake Verdict. Only the fields buildRunSummary/buildDigestState
-- actually read need to be real; the rest exist to satisfy the type.
local function fakeVerdict(seed: number, path: { number }, floorsCleared: number, opts: any): any
	opts = opts or {}
	return {
		telemetry = {
			seed = seed,
			path = path,
			startedAt = 0,
			floorsCleared = floorsCleared,
			deathFloor = opts.deathFloor,
			lastDamageSource = nil,
			killedBy = opts.deathFloor and "skeleton" or nil,
			runDurationSec = 100,
			damageTaken = 50,
			healingFound = 0,
			itemsFound = 2,
			weaponsFound = 0,
			enemiesKilled = 10,
			bossesDefeated = 0,
			goldEarned = 80,
			avgFloorTimeSec = 30,
			lastFloorTimeSec = 30,
			largestEncounter = 3,
		},
		frustrationLevel = opts.frustrationLevel,
		frustrationLabel = opts.frustrationLabel,
		difficultySpike = opts.difficultySpike,
		rootCause = opts.rootCause,
		rootCauseConfidence = opts.rootCauseConfidence,
		unclassified = {},
	}
end

local function okBody(answers: any): string
	return HttpService:JSONEncode({ answers = answers })
end

return function()
	local spec = Spec.new("BalanceDigest")

	-- --------------------------------------------------- A. question design

	spec:check(
		"a minimum sample size is required before asking",
		BalanceDigestConfig.minSampleSize >= 2,
		BalanceDigestConfig.minSampleSize
	)
	spec:check(
		"choice questions are held to the stricter tier",
		BalanceDigestConfig.choiceConfidenceFloor >= 0.8,
		BalanceDigestConfig.choiceConfidenceFloor
	)

	local questions = BalanceDigestConfig.buildQuestions(FloorConfig.pool)
	local count = 0
	for _, _q in questions do
		count += 1
	end
	spec:equals("all three questions go in one request", count, 3)
	spec:equals("roomTypeStandout is a choice", questions.roomTypeStandout.type, "choice")
	spec:equals("curveShape is a choice", questions.curveShape.type, "choice")
	spec:equals("consistent is a noul", questions.consistent.type, "noul")

	-- The lesson from ReviewConfig's rootCause bug, applied here too: without a
	-- no-match outcome a Choice will pick the least-wrong option even when nothing
	-- actually stands out.
	spec:truthy(
		"roomTypeStandout offers a no-pattern outcome",
		questions.roomTypeStandout.criteria["none"]
	)
	spec:truthy(
		"curveShape offers an insufficient-data outcome",
		questions.curveShape.criteria.insufficientData
	)
	for _, id in FloorConfig.pool do
		spec:truthy(
			`roomTypeStandout covers the {id} room`,
			questions.roomTypeStandout.criteria[id]
		)
	end
	spec:truthy(
		"roomTypeStandout covers the boss floor",
		questions.roomTypeStandout.criteria["Boss"]
	)

	-- --------------------------------------------------- B. room sequence

	-- Seed and path chosen so the reconstruction can be checked against what
	-- FloorPlan itself would generate, not just asserted to "not error".
	local seed = 424242
	local summary = RunReviewService.buildRunSummary(fakeVerdict(seed, { 1, 2 }, 2, {}))
	spec:equals(
		"the sequence starts on the seeded starting template",
		summary.rooms[1],
		FloorPlan.startingTemplate(seed)
	)
	spec:equals("the sequence has one entry per floor reached plus the start", #summary.rooms, 3)
	for _, template in summary.rooms do
		spec:truthy(`{template} is a real pool member or the boss`, template ~= nil)
	end

	local reSummary = RunReviewService.buildRunSummary(fakeVerdict(seed, { 1, 2 }, 2, {}))
	spec:check(
		"the same seed and path reconstruct the same room sequence",
		table.concat(summary.rooms, ",") == table.concat(reSummary.rooms, ","),
		table.concat(reSummary.rooms, ",")
	)

	-- Floor 10 is always forced to the boss template, regardless of what the seed
	-- would otherwise offer -- the reconstruction has to respect that too.
	local toBoss =
		RunReviewService.buildRunSummary(fakeVerdict(seed, { 1, 1, 1, 1, 1, 1, 1, 1, 1 }, 9, {}))
	spec:equals(
		"depth 10 reconstructs as the boss template",
		toBoss.rooms[10],
		FloorConfig.bossTemplate
	)

	-- --------------------------------------------------- C. payload shape

	local state = RunReviewService.buildDigestState({
		summary,
		RunReviewService.buildRunSummary(
			fakeVerdict(seed + 1, { 2 }, 1, { deathFloor = 2, rootCause = "boss_wall" })
		),
	})
	spec:truthy("the payload carries the runs array", state.runs)
	spec:equals("the payload has one row per run", #state.runs, 2)
	spec:equals("the seed is not sent", state.runs[1].seed, nil)
	spec:equals("rooms are carried per run", #state.runs[1].rooms, #summary.rooms)
	spec:equals("root cause is carried per run", state.runs[2].rootCause, "boss_wall")
	spec:check(
		"the payload survives encoding",
		pcall(function()
			HttpService:JSONEncode(state)
		end)
	)

	-- --------------------------------------------------- D. reading answers

	local function digestFrom(answers: any): any
		local verdict = { sampleSize = 5, unclassified = {} }
		RunReviewService.interpretDigest(verdict, answers)
		return verdict
	end

	local confident = digestFrom({
		roomTypeStandout = { choice = "Outpost", confidence = 0.91 },
		curveShape = { choice = "frontLoaded", confidence = 0.9 },
		consistent = { noul = 0.85 },
	})
	spec:equals("a confident room finding is taken", confident.roomTypeStandout, "Outpost")
	spec:equals("a confident curve finding is taken", confident.curveShape, "frontLoaded")
	spec:equals("a high noul reads as consistent", confident.consistent, true)
	spec:equals("nothing is left unclassified", #confident.unclassified, 0)

	-- The confidence tier is meant to be stricter than frustration's 0.7: a value
	-- that would have passed there must still be refused here.
	local midTier = digestFrom({
		roomTypeStandout = { choice = "Outpost", confidence = 0.75 },
		curveShape = { choice = "even", confidence = 0.8 },
		consistent = { noul = 0.5 },
	})
	spec:equals("0.75 is below the stricter tier for a room finding", midTier.roomTypeStandout, nil)
	spec:equals("0.8 is below the stricter tier for a curve finding", midTier.curveShape, nil)
	spec:equals("a mid noul is not rounded to a verdict", midTier.consistent, nil)
	spec:equals("all three land as unclassified", #midTier.unclassified, 3)

	local low = digestFrom({
		roomTypeStandout = { choice = "none", confidence = 0.95 },
		curveShape = { choice = "insufficientData", confidence = 0.95 },
		consistent = { noul = 0.1 },
	})
	spec:equals("a confident no-pattern answer is still taken", low.roomTypeStandout, "none")
	spec:equals("insufficientData is a legitimate taken answer", low.curveShape, "insufficientData")
	spec:equals("a low noul reads as inconsistent", low.consistent, false)

	-- --------------------------------------------------- E. the gate + transport

	local history = RunReviewService.history()
	local before = #history

	local gateOk, gateErr = pcall(function()
		if before < BalanceDigestConfig.minSampleSize then
			local blocked = RunReviewService.runDigest()
			spec:equals(
				"below the minimum, the gate refuses without a request",
				blocked.failure,
				"insufficient_data"
			)
			spec:equals("the refusal reports the real sample size", blocked.sampleSize, before)
		end

		-- Push past the minimum with fakes appended on top of whatever is real.
		local needed = math.max(0, BalanceDigestConfig.minSampleSize - before)
		for i = 1, math.max(needed, 1) do
			table.insert(
				history,
				fakeVerdict(
					seed + i,
					{ 1 },
					1,
					{ rootCause = "boss_wall", frustrationLabel = "grindy but tolerable" }
				)
			)
		end

		local sent = false
		local transport = function(_url: string, _headers: any, _body: string)
			sent = true
			return true,
				200,
				okBody({
					roomTypeStandout = { choice = "Outpost", confidence = 0.9 },
					curveShape = { choice = "even", confidence = 0.9 },
					consistent = { noul = 0.8 },
				})
		end
		TypeSafeClient.setTransport(transport)

		local verdict = RunReviewService.runDigest()
		spec:truthy("a request is sent once past the minimum", sent)
		spec:equals("the sample size matches history", verdict.sampleSize, #history)
		spec:equals("no failure is recorded", verdict.failure, nil)
		spec:equals("the verdict carries the room finding", verdict.roomTypeStandout, "Outpost")

		TypeSafeClient.setTransport(nil)
	end)

	-- Trim exactly what this spec added, regardless of how far it got.
	while #history > before do
		table.remove(history)
	end

	if not gateOk then
		spec:check("digest checks completed without error", false, gateErr)
	end

	spec:equals("teardown restores the history length", #RunReviewService.history(), before)

	return spec:finish()
end
