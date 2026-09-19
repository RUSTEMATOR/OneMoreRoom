--!strict
-- The balance digest: aggregate questions over a BATCH of run reviews, not a single
-- run. Where ReviewConfig asks "how did this one run feel", this asks "what pattern
-- shows up across the runs we have so far" -- the composite-scoring / feature-
-- discovery shape from the TypeSafe docs, applied to this project's own telemetry.
--
-- This is a QA-facing report, not a gameplay system: nothing it returns ever reaches
-- generation, loot, combat, or difficulty. It reads RunReviewService.history(), which
-- is in-memory and per server session -- there is no Phase 13 save system yet, so a
-- digest only ever covers the runs played since the last boot. That is a real
-- limitation, not a bug: state it rather than pretend otherwise.

local BalanceDigestConfig = {}

-- Below this many completed reviews, an aggregate judgment is a coin flip dressed up
-- as a finding. Refusing to ask is a code decision, not a model one, and it costs
-- nothing -- the whole point of gating before the request is to not spend the call.
BalanceDigestConfig.minSampleSize = 3

-- Both Choice questions here share rootCause's tier, not frustration's: a wrong
-- "roomTypeStandout" or "curveShape" is the same shape of mistake as a wrong
-- rootCause -- it actively points a QA session at a pattern that was never real,
-- rather than just mislabeling one run's vibe. See ReviewConfig's comment on why the
-- two floors differ.
BalanceDigestConfig.choiceConfidenceFloor = 0.85

-- `pool` is FloorConfig.pool, passed in rather than required directly: this module
-- describes QUESTIONS, not floor structure, and a caller already holding the pool
-- (RunReviewService already requires FloorConfig for other reasons) keeps the
-- dependency one-directional.
function BalanceDigestConfig.buildQuestions(pool: { string }): { [string]: any }
	local roomOptions: { [string]: string } = {}
	for _, id in pool do
		roomOptions[id] = `The {id} room type`
	end
	roomOptions["Boss"] = "The boss floor"
	-- Load-bearing, the same way `survived` is load-bearing on ReviewConfig's
	-- rootCause: without a no-match outcome, a Choice will pick the least-wrong
	-- option even when nothing actually stands out.
	roomOptions["none"] =
		"No single room type stands out -- frustration and deaths are spread evenly across room types, or the batch is too small or too uniform to tell."

	return {
		roomTypeStandout = {
			type = "choice",
			instructions = "Across this batch of runs, which room type most often coincides with a run being rated frustrating or ending in death? Each run lists the room types it visited in order, alongside how it went.",
			criteria = roomOptions,
		},
		curveShape = {
			type = "choice",
			instructions = "Looking at how frustration and death floor relate to how far each run got, does the difficulty curve across this batch read as front-loaded, even, back-loaded, or is there not enough distinct depth in this batch to say?",
			criteria = {
				frontLoaded = "Runs struggle disproportionately on early floors relative to how far they ultimately got",
				even = "Difficulty feels roughly proportional to the depth reached",
				backLoaded = "Early floors are consistently easy; difficulty only shows up on later floors",
				insufficientData = "The runs in this batch do not cover enough different depths to say",
			},
		},
		consistent = {
			type = "noul",
			instructions = "Do runs that reach a similar depth report a similar frustration level, rather than wildly different ones? Answer false if similar-depth runs feel inconsistent with each other.",
			criteria = {
				["true"] = "Similar-depth runs report similar frustration",
				["false"] = "Similar-depth runs report widely different frustration from each other",
			},
		},
	}
end

return BalanceDigestConfig
