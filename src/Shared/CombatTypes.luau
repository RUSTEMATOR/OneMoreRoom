--!strict
-- The CombatFeedback wire contract, as a tagged union so Luau narrows on `kind`.
-- Net.luau stays a list of names; the payload shape lives here.

export type DamageInfo = {
	source: Player?,
	weapon: string?,
	position: Vector3?,
}

export type SwingStarted = {
	kind: "SwingStarted",
	actor: Player,
	weapon: string,
	windup: number,
	active: number,
	recovery: number,
}

export type Hit = {
	kind: "Hit",
	actor: Player?,
	target: Model,
	amount: number,
	remaining: number,
	hitPosition: Vector3,
	lethal: boolean,
}

export type Dodged = {
	kind: "Dodged",
	actor: Player,
	duration: number,
	iframes: number,
}

export type Died = {
	kind: "Died",
	actor: Model?,
	respawnIn: number?,
}

export type Respawned = {
	kind: "Respawned",
	actor: Player,
}

export type TargetReset = {
	kind: "TargetReset",
	target: Model,
}

-- A ranged enemy loosing a shot. Separate from SwingStarted rather than reusing it:
-- `actor` here is the enemy Model that fired, not a Player, and the two need
-- different sounds -- a bow release is not a sword swing.
export type RangedShot = {
	kind: "RangedShot",
	actor: Model,
	weapon: string,
}

-- An arrow (or future projectile) landing on a player. Separate from `Hit`, which is
-- what a PLAYER'S swing broadcasts: `Hit.actor` is a Player and `Hit.target` is
-- whatever they struck, the reverse of this. Conflating them would mean an enemy's
-- arrow either impersonates a player's swing or the player's swing impersonates a
-- monster landing a hit, and either reading is wrong.
export type RangedImpact = {
	kind: "RangedImpact",
	weapon: string,
	target: Model,
	position: Vector3,
}

-- The Cultist's fuse ending. `actor` is the enemy Model, still alive for a moment
-- after this fires (despawn is on its usual delay) -- same reason RangedShot anchors
-- to the enemy rather than to nothing. No single "target" the way RangedImpact
-- names one: the blast can land on several players at once, or none.
export type Detonation = {
	kind: "Detonation",
	actor: Model,
}

export type Feedback =
	SwingStarted
	| Hit
	| Dodged
	| Died
	| Respawned
	| TargetReset
	| RangedShot
	| RangedImpact
	| Detonation

return {}
