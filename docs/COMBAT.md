# Combat

## Authority

Server-authoritative from the first swing. The client sends **intent** — `RequestAttack`, `RequestDodge` — and never reports outcomes. The server owns cooldowns, stamina, range checks, damage, and death. The client predicts visuals only.

This is a Phase 1 property, not a Phase 17 fix. Phase 17 audits it.

## Player

Normal Roblox character movement, plus health, stamina, a light attack, a dodge, death, and respawn.

**Light attack** — windup → active → recovery. Damage applies during the active window only, and **recovery doubles as the attack cooldown** — there is no separate timer. Recovery is deliberately twice the active window, because that ratio is what makes a whiff cost something.

Hit detection is a `GetPartBoundsInBox` query off the HumanoidRootPart, yaw-only, trimmed to a 120° cone by a dot-product filter. Targets are deduped per swing by resolved model, so a multi-frame active window lands exactly once per target.

Every tunable lives in `src/Shared/CombatConfig.luau`. That is the file to edit when combat does not feel right.

**Dodge (right mouse button)** — costs stamina → short movement burst → invulnerability window → cooldown. The i-frame window is server-tracked and checked at damage-application time; a client claiming invulnerability is ignored.

Right-click is also Roblox's camera-pan control, so the binding goes through `ContextActionService`, acts only on `UserInputState.Begin`, and returns `ContextActionResult.Pass` so panning still works. Direction is derived server-side from `Humanoid.MoveDirection`, so `RequestDodge` carries no payload at all.

Dodge cancels windup and recovery but **not** the active window — cancelling that would be free damage with no commitment.

Stamina regenerates over time and gates dodge spam.

## Weapons

Three archetypes, then modifiers. Three weapons plus modifiers produce dozens of variants without dozens of implementations.

| | Damage | Range | Speed |
|---|---|---|---|
| Sword | medium | short | medium |
| Greatsword | high | medium | low |
| Daggers | low | very short | very high |

A modifier is a data row: *Rusted Dagger — +15% attack speed, −10% damage*. It applies to any archetype.

## Enemies

One state machine, reused: IDLE → DETECT → CHASE → ATTACK → COOLDOWN → CHASE.

The Skeleton is the first and defines the shape: health, damage, attack cooldown, death, hit reaction, basic animation. Not an elaborate AI system.

## Bosses

`BossController` composed of `PhaseController`, `AttackController`, `HealthController`, and `ArenaController`. A boss is a *configuration* of that framework plus custom mechanics, never a fork of it.

**The Warden** (Floor 10) — P1 sword attacks, P2 summons skeletons, P3 arena attacks. Phase transitions fire at HP thresholds.

## Feel

Phase 15 is where combat stops feeling like an engineering demo: hit effects, camera shake, damage numbers, enemy reactions, weapon trails, death effects. A sword hit should feel good. This matters more than another twenty mechanics.

All of it is client-side and never gates server logic.
