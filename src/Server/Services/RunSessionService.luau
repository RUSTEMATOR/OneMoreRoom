--!strict
-- Owns the current tower run. Named RunSessionService, not RunService: a module sharing
-- a name with game:GetService("RunService") shadows the real one wherever both are
-- needed, and the resulting bug reads as correct code.

local ProgressionService = require(script.Parent.ProgressionService)

local RunSessionService = {}

export type RunState = {
	seed: number,
	floor: number,
	gold: number,
	active: boolean,
	-- Which exit index was taken on each cleared floor. Reproducing a run needs the
	-- seed AND the path: generation is deterministic, but which branch you walked is
	-- an input, not an output.
	path: { number },
}

local current: RunState? = nil

function RunSessionService.Init()
	current = nil
end

function RunSessionService.begin(seed: number): RunState
	local state: RunState = {
		seed = seed,
		floor = 1,
		gold = 0,
		active = true,
		path = {},
	}
	current = state
	return state
end

function RunSessionService.get(): RunState?
	return current
end

-- Returns the amount actually awarded, which is 0 when no run is active. Enemy kills
-- outside a run (the practice skeleton) are worth nothing rather than an error.
function RunSessionService.addGold(amount: number): number
	local state = current
	if state == nil or not state.active or amount <= 0 then
		return 0
	end
	-- Fortune is applied here, at the one place gold enters a run, so every source
	-- benefits rather than whichever ones someone remembered to multiply.
	local scaled = math.floor(amount * ProgressionService.partyGoldMultiplier() + 0.5)
	state.gold += scaled
	return scaled
end

-- Formatted the way a bug report should carry it: "seed:839271 path:1,2,1".
function RunSessionService.describe(): string
	local state = current
	if state == nil then
		return "no active run"
	end
	return `seed:{state.seed} path:{table.concat(state.path, ",")}`
end

function RunSessionService.recordChoice(exitIndex: number)
	local state = current
	if state ~= nil then
		table.insert(state.path, exitIndex)
	end
end

function RunSessionService.finish()
	if current then
		current.active = false
	end
end

return RunSessionService
