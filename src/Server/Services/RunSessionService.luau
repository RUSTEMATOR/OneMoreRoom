--!strict
-- Owns the current tower run. Named RunSessionService, not RunService: a module sharing
-- a name with game:GetService("RunService") shadows the real one wherever both are
-- needed, and the resulting bug reads as correct code.

local RunSessionService = {}

export type RunState = {
	seed: number,
	floor: number,
	gold: number,
	active: boolean,
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
	}
	current = state
	return state
end

function RunSessionService.get(): RunState?
	return current
end

function RunSessionService.finish()
	if current then
		current.active = false
	end
end

return RunSessionService
