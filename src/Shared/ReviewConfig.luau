--!strict
-- The post-run review: what we ask TypeSafe about a finished run, and the rules for
-- believing the answer.
--
-- This is the ONLY place the project talks to an external model, and it is
-- deliberately the safest possible place for it:
--
--   * It runs AFTER a run ends, so nothing waits on it. Measured round trip is ~615ms,
--     six times the documented figure, which would be unacceptable anywhere near the
--     Heartbeat path and is irrelevant here.
--   * It never touches seeded state. Verified empirically: identical payloads return
--     drifting numbers (0.83/0.82/0.80 on a Choice, 3.08/3.07/3.04 on a Score). The
--     winning option and the Score LEVEL are stable; the underlying floats are not.
--     So we round to levels and gate on confidence, and we never let any of it reach
--     generation, loot or combat — the reproducibility guarantee stays intact.
--   * If the service is unreachable the run record simply has no verdict.

local ReviewConfig = {}

ReviewConfig.enabled = true

ReviewConfig.endpoint = "https://api.typesafe.ai/v1/systemone"
ReviewConfig.model = "jev-latest"

-- The key is read from Roblox's secret store, never from a synced script.
-- Configure it in Creator Hub under this name.
ReviewConfig.secretKey = "TYPESAFE_API_KEY"

-- Answers below the relevant floor are recorded as unclassified rather than believed.
-- Not a single global number: the live TypeSafe docs argue against a uniform floor,
-- because different wrong answers cost different amounts. Both of these currently
-- feed only human-read QA output, never gameplay, but the two mistakes are not
-- equally cheap:
--   * A wrong frustrationLevel is a soft miss -- "grindy" read as "a fair challenge"
--     costs nothing but a slightly noisy line in a log.
--   * A wrong rootCause actively misleads: it sends a QA session chasing a pattern
--     ("boss_wall is common!") that was never real. That deserves a harder floor.
-- 0.7 for frustration is the same number the original experiments picked (every
-- answer at 0.88+ was correct, both wrong answers were 0.26/0.42, so 0.7 sits with
-- daylight on both sides). 0.85 for rootCause is deliberately tighter for the reason
-- above; there is no equivalent measurement for it yet, so treat it as a starting
-- point to adjust once enough real verdicts accumulate to check it against.
ReviewConfig.frustrationConfidenceFloor = 0.7
ReviewConfig.rootCauseConfidenceFloor = 0.85

ReviewConfig.request = {
	timeoutSeconds = 10,
	maxAttempts = 3,
	-- 429 and 529 are the documented retryable statuses.
	retryableStatuses = { [429] = true, [529] = true },
	backoffBaseSeconds = 1.5,
}

-- Score levels are ordered and their INDEX is what we keep. The raw float drifts
-- between identical calls, so rounding to a level is what makes the verdict stable
-- enough to compare across runs.
ReviewConfig.frustrationLevels = {
	"smooth and satisfying",
	"a fair challenge",
	"grindy but tolerable",
	"frustrating",
	"likely to make the player quit",
}

ReviewConfig.causes = {
	survived = "The player did not die at all; deathFloor is null. Choose this whenever the run was not ended by a death.",
	under_geared = "The player died with notably few weapon upgrades or relics for the depth they reached.",
	boss_wall = "The player died on a boss floor, which is every tenth floor.",
	attrition = "The player died worn down gradually over many floors, with little healing found.",
	one_bad_room = "The player died abruptly on a single floor while otherwise healthy and early in the run.",
	overwhelmed = "The player died on a floor carrying an unusually large encounter for its depth.",
}

-- All three go in ONE request. They are independent, they run in parallel server-side,
-- and batching them costs one round trip instead of three.
function ReviewConfig.buildQuestions(): { [string]: any }
	return {
		frustration = {
			type = "score",
			instructions = "Rate how frustrating this run was likely to feel for the player, judging the whole shape of the session rather than any single number.",
			criteria = ReviewConfig.frustrationLevels,
		},
		difficultySpike = {
			type = "noul",
			instructions = "Did this run contain a difficulty spike, meaning one floor was far harder than the floors around it?",
			criteria = {
				["true"] = "One floor clearly stands out as disproportionately punishing",
				["false"] = "Difficulty rose smoothly or stayed flat",
			},
		},
		-- The `survived` option is load-bearing. Without a no-match outcome this
		-- question confidently answered "attrition" for runs where nobody died.
		rootCause = {
			type = "choice",
			instructions = "This run has ended. Pick the single best explanation for how it ended. The run state includes deathFloor, which is null if the player did not die.",
			criteria = ReviewConfig.causes,
		},
	}
end

return ReviewConfig
