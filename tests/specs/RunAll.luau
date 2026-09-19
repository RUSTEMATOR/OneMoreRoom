--!strict
-- The regression entry point. Every phase appends its spec here, so each later phase
-- re-runs all earlier specs for free. One execute_luau call runs the whole suite.

local Spec = require(script.Parent.Spec)

local SPECS = {
	"Phase00_Boot",
	"Phase01_Combat",
	"Phase02_Skeleton",
	"Phase03_Room",
	"Phase04_Floor",
	"Phase05_RoomTypes",
	"Phase06_Generation",
	"Phase07_Loot",
	"Phase08_Weapons",
	"Phase09_Progression",
	"Phase10_Boss",
}

-- The suite runs against the live world, and the practice skeleton actively hunts the
-- player. Left running it corrupts unrelated assertions — it hit the player for 14
-- during the Phase 1 i-frame check, which reads as a product bug rather than
-- interference. Quiesce around the suite, and restore even if a spec throws.
--
-- pcall-wrapped so the harness never dies because a service was renamed or moved.
local function setPracticeEnabled(enabled: boolean)
	pcall(function()
		local services = game:GetService("ServerScriptService"):FindFirstChild("Services")
		local enemyService = services and services:FindFirstChild("EnemyService")
		if enemyService ~= nil then
			(require(enemyService) :: any).setPracticeEnabled(enabled)
		end
	end)
end

return function()
	local results: { Spec.Result } = {}
	local passed = 0
	local failed = 0

	setPracticeEnabled(false)
	task.wait(0.2)

	for _, name in SPECS do
		local module = script.Parent:FindFirstChild(name)
		if module == nil then
			table.insert(results, {
				name = name,
				passed = false,
				checks = { { desc = "spec module present", ok = false, detail = "not found" } },
			})
			failed += 1
			continue
		end

		-- xpcall so one throwing spec reports as a failure instead of aborting the suite.
		local ok, result = xpcall(function()
			return (require(module) :: any)()
		end, debug.traceback)

		if ok then
			table.insert(results, result)
			if result.passed then
				passed += 1
			else
				failed += 1
			end
		else
			table.insert(results, {
				name = name,
				passed = false,
				checks = { { desc = "spec threw", ok = false, detail = tostring(result) } },
			})
			failed += 1
		end
	end

	setPracticeEnabled(true)

	return {
		allPassed = failed == 0,
		passed = passed,
		failed = failed,
		results = results,
	}
end
