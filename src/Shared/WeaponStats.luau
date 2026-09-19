--!strict
-- Resolves an archetype plus a list of modifiers into the numbers combat actually
-- uses. Pure: no services, no world, no state — so the "a modifier applied to any
-- archetype produces correct final stats" acceptance criterion is arithmetic.
--
-- This is the module that makes three weapons into dozens. Nothing downstream knows
-- a modifier exists; CombatService reads a resolved table and cannot tell whether it
-- came from a plain Sword or a Rusted Reaching Greatsword.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)

local WeaponStats = {}

export type Resolved = {
	archetype: string,
	modifiers: { string },
	displayName: string,

	damage: number,
	windup: number,
	active: number,
	recovery: number,
	staminaCost: number,

	arcSize: Vector3,
	arcForwardOffset: number,
	arcHalfAngleCos: number,
	maxTargets: number,

	-- Derived, so callers never recompute it inconsistently.
	reach: number,
	cycle: number,
}

-- A swing's whole cycle scales together. Scaling only the windup would make "attack
-- speed" mean something different on each archetype, and would let a fast weapon
-- have a slow recovery, which is the opposite of what the word implies.
local MIN_PHASE = 0.02

function WeaponStats.isArchetype(id: string): boolean
	return CombatConfig.weapons[id] ~= nil
end

function WeaponStats.isModifier(id: string): boolean
	return CombatConfig.modifiers[id] ~= nil
end

function WeaponStats.resolve(archetype: string, modifiers: { string }?): Resolved
	local base = CombatConfig.weapons[archetype] or CombatConfig.weapons[CombatConfig.defaultWeapon]
	local applied: { string } = {}

	local damageScale = 1
	local speedScale = 1
	local reachBonus = 0

	for _, id in modifiers or {} do
		local modifier = CombatConfig.modifiers[id]
		if modifier == nil then
			continue
		end
		table.insert(applied, id)
		damageScale *= modifier.damage or 1
		speedScale *= modifier.speed or 1
		reachBonus += modifier.reach or 0
	end

	-- Faster means shorter, so speed divides the durations.
	local function phase(value: number): number
		return math.max(MIN_PHASE, value / speedScale)
	end

	local arcSize = base.arcSize + Vector3.new(0, 0, reachBonus)
	local forwardOffset = base.arcForwardOffset + reachBonus / 2

	local windup = phase(base.windup)
	local active = phase(base.active)
	local recovery = phase(base.recovery)

	return {
		archetype = base.id,
		modifiers = applied,
		displayName = WeaponStats.displayName(base.id, applied),

		damage = base.damage * damageScale,
		windup = windup,
		active = active,
		recovery = recovery,
		staminaCost = base.staminaCost,

		arcSize = arcSize,
		arcForwardOffset = forwardOffset,
		arcHalfAngleCos = base.arcHalfAngleCos,
		maxTargets = base.maxTargets,

		reach = forwardOffset + arcSize.Z / 2,
		cycle = windup + active + recovery,
	}
end

-- "Rusted Greatsword", "Keen Swift Daggers". Prefixes in the order they were applied,
-- so a weapon's name is a faithful description of its data.
function WeaponStats.displayName(archetype: string, modifiers: { string }?): string
	local base = CombatConfig.weapons[archetype]
	if base == nil then
		return archetype
	end

	local parts: { string } = {}
	for _, id in modifiers or {} do
		local modifier = CombatConfig.modifiers[id]
		if modifier ~= nil then
			table.insert(parts, modifier.prefix)
		end
	end
	table.insert(parts, base.displayName)
	return table.concat(parts, " ")
end

-- Sustained damage, for comparing archetypes honestly. A weapon that hits harder but
-- commits you for longer is not automatically better, and this is the number that
-- says so.
function WeaponStats.damagePerSecond(resolved: Resolved): number
	if resolved.cycle <= 0 then
		return 0
	end
	return resolved.damage / resolved.cycle
end

return WeaponStats
