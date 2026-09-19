--!strict
-- The regression entry point. Every phase appends its spec here, so each later phase
-- re-runs all earlier specs for free. One execute_luau call runs the whole suite.

local Spec = require(script.Parent.Spec)

local SPECS = {
	"Phase00_Boot",
	"Phase01_Combat",
}

return function()
	local results: { Spec.Result } = {}
	local passed = 0
	local failed = 0

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

	return {
		allPassed = failed == 0,
		passed = passed,
		failed = failed,
		results = results,
	}
end
