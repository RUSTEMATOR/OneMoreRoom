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

export type Feedback = SwingStarted | Hit | Dodged | Died | Respawned | TargetReset

return {}
