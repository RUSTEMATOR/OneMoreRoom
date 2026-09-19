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

| | Damage | Cycle | Reach | Arc | Sustained |
|---|---|---|---|---|---|
| Sword | 18 | 0.52 s | 5.5 | 120° | 34.6 /s |
| Greatsword | 34 | 0.92 s | 7.5 | 140° | 37.0 /s |
| Daggers | 9 | 0.28 s | 4.0 | 90° | 32.1 /s |

**None of them dominates**, and that is the point. Sustained damage sits within 15% across all three, so the choice is about commitment rather than power: the Greatsword kills a Skeleton in two swings but locks you in for nearly a second, the Daggers take seven but leave you free three times as often. The spec asserts that spread stays under 25%, because the moment one weapon wins on both axes there is no choice left.

A modifier is a data row — *Rusted Daggers: +15% attack speed, −10% damage* — and applies to any archetype. `Shared/WeaponStats.luau` folds archetype plus modifiers into resolved numbers, and nothing downstream knows a modifier exists: `CombatService` reads a resolved table and cannot tell a plain Sword from a Rusted Reaching Greatsword.

Speed scales the **whole cycle**, not just the windup. Scaling one phase would let a "fast" weapon keep a slow recovery, which is the opposite of what the word means.

**A swing snapshots its stats when it starts.** Picking up a Greatsword mid-swing cannot retune the swing already in flight.

Weapon drops are **generated, not catalogued**: a drop picks an archetype and zero to two seeded modifiers. That is why weapons are absent from `LootConfig`'s fixed pool — there is nothing to catalogue.

## Enemies

One state machine, reused: IDLE → NOTICE → CHASE → ATTACK → COOLDOWN → CHASE, plus DEAD. Ticked for every enemy on a single Heartbeat, same discipline as player combat.

The Skeleton is the first and defines the shape: health, damage, attack cooldown, death, hit reaction, a procedural lunge. Not an elaborate AI system.

It is a minimal R6 Humanoid rig built from `EnemyConfig.kinds.Skeleton.rig` — a Humanoid rather than CFrame movement, because `Humanoid:MoveTo` gives real collision, so it bumps into walls instead of walking through them. Proper `PathfindingService` navigation arrives with rooms.

Two behaviours worth knowing: **range is re-checked at the moment the blow lands**, not when the swing starts, so stepping out of a telegraphed attack works. And **getting hit by someone it had not noticed pulls aggro**, so you cannot freely snipe one enemy out of a group.

Enemies damage players through `CombatService.applyDamageToPlayer`, so i-frames apply to them for free, and they take damage by registering as `Damageable`s, so the sword arc never branches on target type.

A practice skeleton spawns next to the training dummy (`EnemyConfig.practice`) and respawns after it dies, so the combat loop is playable before floors exist. Like the dummy it lives in `Workspace/Static`, never `Generated`.

## Bosses

The framework is two pure controllers plus a service that composes them. `BossPhases` decides which act is live from a health fraction — no state, no world, just arithmetic, which is what makes "phase transitions fire at HP thresholds" testable with no Studio at all. `BossAttacks` decides what a phase reaches for and whether a landed attack connects. `BossService` owns the rig, the clock, and the world; it does not know the rules, only how to run them.

**A second boss is a `BossConfig` entry, never a fork of the Warden.** The spec runs both validators — `BossPhases.validate` and `BossAttacks.validate` — over every boss in the config, not over the Warden by name, so the framework's own rules stay generic by construction rather than by discipline.

**The arena is a room template**, not a parallel system. `RoomConfig.templates.Boss` goes through the same seal, clear and exit machinery as a Combat room; only the occupant differs, and the room is not cleared until the boss falls. Building a bespoke arena system would have meant re-solving sealing, occupancy and resets for one encounter.

A boss is not a special case of enemy either: it registers as the same `Damageable` the sword already hits, and it is **invulnerable through a phase transition** — the brief pause is what stops a lucky burst from skipping an act, and it is checked at the same place ordinary i-frames are, by rejecting damage with reason `"transition"`.

Every attack telegraphs — a windup, then a flat disc or wedge on the floor, then the hit. **The windup must outlast the dodge i-frame window**, or a boss you cannot read is noise rather than difficulty, and the spec asserts that relation for every attack in every boss.

**The Warden** (Floor 10, 900 HP) — Sword (Cleave only) → Summon (Cleave, periodic skeletons, capped) → Arena (Cleave and Slam, a radial that ignores facing and covers the whole room, so the read is "dodge through it" rather than "run"). A phase lists its attacks weakest-first, signature-last, and selection reaches for the last usable one — so the boss favours its signature move whenever it is off cooldown and falls back only while that move is cooling.

**Every tenth floor is forced to be the Boss template**, outside the ordinary generation pool — a boss must be a landmark you can count toward, never something that might turn up on floor 3. On the floor before it, both exits lead to the boss rather than offering a fake choice between two doors that go to the same place.

## Feel

Phase 15 is where combat stops feeling like an engineering demo: hit effects, camera shake, damage numbers, enemy reactions, weapon trails, death effects. A sword hit should feel good. This matters more than another twenty mechanics.

All of it is client-side and never gates server logic.
