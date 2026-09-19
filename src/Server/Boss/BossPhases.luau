--!strict
-- The PhaseController, as a pure function. Given a boss and a health fraction it
-- returns which phase is active — no state, no world, so "phase transitions fire at
-- HP thresholds" is testable as arithmetic.
--
-- Keeping this pure is what makes a second boss a config: the rule "phases are
-- ordered by descending health threshold" belongs to the framework, and the
-- thresholds themselves belong to the data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Shared.BossConfig)

local BossPhases = {}

function BossPhases.count(bossId: string): number
	local boss = BossConfig.bosses[bossId]
	return if boss ~= nil then #boss.phases else 0
end

-- Returns the index of the phase active at this health fraction. Phases are listed
-- descending by threshold, so the last one whose threshold we are still at or below
-- wins. Clamped, so a fraction outside 0..1 cannot fall off either end.
function BossPhases.indexFor(bossId: string, healthFraction: number): number
	local boss = BossConfig.bosses[bossId]
	if boss == nil or #boss.phases == 0 then
		return 1
	end

	local fraction = math.clamp(healthFraction, 0, 1)
	local active = 1
	for index, phase in boss.phases do
		if fraction <= phase.fromHealthFraction then
			active = index
		end
	end
	return active
end

function BossPhases.at(bossId: string, index: number): BossConfig.Phase?
	local boss = BossConfig.bosses[bossId]
	if boss == nil then
		return nil
	end
	return boss.phases[math.clamp(index, 1, #boss.phases)]
end

function BossPhases.forFraction(bossId: string, healthFraction: number): BossConfig.Phase?
	return BossPhases.at(bossId, BossPhases.indexFor(bossId, healthFraction))
end

-- True when damage that moves health from `before` to `after` crosses a threshold.
-- The caller uses this to fire the transition once, rather than every frame the
-- fraction happens to sit below a line.
function BossPhases.crosses(bossId: string, before: number, after: number): boolean
	return BossPhases.indexFor(bossId, after) > BossPhases.indexFor(bossId, before)
end

-- Validates a boss's phase list. Called by the spec rather than at runtime: a
-- malformed boss should fail the build, not limp along in production.
function BossPhases.validate(bossId: string): (boolean, string?)
	local boss = BossConfig.bosses[bossId]
	if boss == nil then
		return false, "unknown boss"
	end
	if #boss.phases == 0 then
		return false, "no phases"
	end
	if boss.phases[1].fromHealthFraction < 1 then
		return false, "first phase must start at full health"
	end

	local previous = math.huge
	for _, phase in boss.phases do
		if phase.fromHealthFraction >= previous then
			return false, `phase {phase.id} is not below the one before it`
		end
		if phase.fromHealthFraction < 0 or phase.fromHealthFraction > 1 then
			return false, `phase {phase.id} threshold is not a fraction`
		end
		if #phase.attacks == 0 then
			return false, `phase {phase.id} has no attacks`
		end
		for _, attackId in phase.attacks do
			if boss.attacks[attackId] == nil then
				return false, `phase {phase.id} uses unknown attack {attackId}`
			end
		end
		previous = phase.fromHealthFraction
	end

	return true, nil
end

return BossPhases
