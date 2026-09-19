--!strict
-- The AttackController. Chooses which attack to use and decides who a landed attack
-- hits. Both halves are pure functions of state passed in, so the fight's rules are
-- testable without a world.
--
-- Selection prefers the LAST usable attack in a phase's list, so a phase can be
-- written "weakest first, signature move last" and the boss reaches for its
-- signature whenever it is off cooldown.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Shared.BossConfig)

local BossAttacks = {}

export type Cooldowns = { [string]: number }

function BossAttacks.get(bossId: string, attackId: string): BossConfig.Attack?
	local boss = BossConfig.bosses[bossId]
	if boss == nil then
		return nil
	end
	return boss.attacks[attackId]
end

-- The distance at which an attack can be started at all.
function BossAttacks.effectiveRange(attack: BossConfig.Attack): number
	if attack.kind == "radial" then
		return attack.radius or 0
	end
	return attack.range or 0
end

-- Returns the attack to use, or nil if nothing is ready or in range.
function BossAttacks.choose(
	bossId: string,
	phase: BossConfig.Phase,
	cooldowns: Cooldowns,
	distance: number,
	now: number
): BossConfig.Attack?
	local chosen: BossConfig.Attack? = nil

	for _, attackId in phase.attacks do
		local attack = BossAttacks.get(bossId, attackId)
		if attack == nil then
			continue
		end
		if now < (cooldowns[attackId] or 0) then
			continue
		end
		if distance > BossAttacks.effectiveRange(attack) then
			continue
		end
		-- Later entries win, so a phase list reads weakest-to-signature.
		chosen = attack
	end

	return chosen
end

-- Whether a landed attack reaches a target at `offset` from the boss, given the
-- direction the boss is facing. Radial attacks ignore facing entirely — that is what
-- makes the Slam a dodge check rather than a positioning check.
function BossAttacks.reaches(
	attack: BossConfig.Attack,
	bossPosition: Vector3,
	bossLook: Vector3,
	targetPosition: Vector3
): boolean
	local delta = targetPosition - bossPosition
	local flat = Vector3.new(delta.X, 0, delta.Z)

	if attack.kind == "radial" then
		return flat.Magnitude <= (attack.radius or 0)
	end

	local range = attack.range or 0
	if flat.Magnitude > range then
		return false
	end
	if flat.Magnitude < 1e-4 then
		return true
	end

	local look = Vector3.new(bossLook.X, 0, bossLook.Z)
	if look.Magnitude < 1e-4 then
		return true
	end
	return flat.Unit:Dot(look.Unit) >= (attack.halfAngleCos or -1)
end

-- Validates that every attack a boss declares is coherent. Spec-time, like
-- BossPhases.validate.
function BossAttacks.validate(bossId: string): (boolean, string?)
	local boss = BossConfig.bosses[bossId]
	if boss == nil then
		return false, "unknown boss"
	end

	for id, attack in boss.attacks do
		if attack.damage <= 0 then
			return false, `{id} deals no damage`
		end
		if attack.windup <= 0 then
			return false, `{id} has no telegraph`
		end
		if attack.cooldown <= attack.windup + attack.recovery then
			return false, `{id} can be restarted before it finishes`
		end
		if attack.kind == "radial" then
			if (attack.radius or 0) <= 0 then
				return false, `{id} is radial with no radius`
			end
		elseif attack.kind == "arc" then
			if (attack.range or 0) <= 0 then
				return false, `{id} is an arc with no range`
			end
		else
			return false, `{id} has unknown kind {attack.kind}`
		end
	end

	return true, nil
end

return BossAttacks
