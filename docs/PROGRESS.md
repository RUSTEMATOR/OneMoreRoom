# One More Room — progress ledger

Canonical status. The build tracker artifact is a published *view* of this file, synced one way at the end of each session. Nothing is ever read back from the artifact into the repo.

Tracker: https://claude.ai/artifact/AooT5JjezgLaNBticyAfqj
Remote: https://github.com/RUSTEMATOR/OneMoreRoom

## Current milestone

Phase 11 — Second biome

## Awaiting you

Phase 1 is code-complete and its automated suite is green, but two things need a human:

1. **The manual pass (M1–M6 below).** Feel, animation, sound, hitstop, HUD layout and the right-click/camera coexistence cannot be judged headlessly.
2. **The Phase 1 gate** — *does swinging a sword feel good?* If not, tune `src/Shared/CombatConfig.luau`; every feel number is in that one file so the loop is fast.

Phase 2 proceeds on the assumption the gate passes. If it does not, Phase 2's enemy tuning is built on a moving anchor and should be revisited.

### Manual checklist

- **M1** Left click swings; the right arm moves through windup → slash → return; the sword is in the right hand.
- **M2** Right click dodges, **and right-click-drag still pans the camera.** One dodge fires at the start of a drag — expected. If that is intolerable in play, fall back to `Q`.
- **M3** Hitting the dummy: it tilts, flashes, plays an impact sound, and the frame hitches for a beat.
- **M4** Bars track the server. Four dodges empty stamina; it refills in ~5 s.
- **M5** The dummy KOs at 14 swings and resets after 2.5 s. Lethal damage respawns you after 3 s at full bars.
- **M6** The gate.

## Completed

### Phase 0 — Foundation

- [x] Rokit toolchain pinned in-repo (rojo 7.7.0, selene 0.31.0, StyLua 2.5.2)
- [x] Rojo Studio plugin installed and connected; place saved and published
- [x] Repo scaffold, `.gitignore`, `selene.toml`, `stylua.toml`, pre-commit hook
- [x] `default.project.json` with the `$path` ownership boundary
- [x] `CLAUDE.md` — ownership rule, lifecycle rules, MCP limitations, skills table
- [x] Shared: `Rng` (seeded), `Net`, `BuildStamp`, `PlayerDataSchema`
- [x] `ServerMain` + services wired; `ClientMain` + controllers wired
- [x] Spec harness (`Spec`, `RunAll`) and `Phase00_Boot`
- [x] Project-local skills: `playtest`, `phase-start`, `phase-done`, `repro`
- [x] Acceptance playtest passed

### Phase 1 — Player movement & basic combat

- [x] `CombatConfig` — every tunable in one file, with the feel numbers justified
- [x] `CombatTypes` — `CombatFeedback` as a tagged union
- [x] `PlayerService` — vitals, generation counter, character lifecycle, custom spawn/respawn, attribute mirroring
- [x] `CombatService` — attack state machine, arc queries, dodge, i-frames, stamina policy, damageable registry, single Heartbeat tick, zero `task.delay`
- [x] `TrainingDummyService` — code-authored dummy in `Workspace/Static`, hit reaction, auto-reset
- [x] `WeaponBuilder` — sword built from its data spec
- [x] Client: `InputController` (CAS, LMB attack / RMB dodge), `HudController` (attribute-driven bars), `FeedbackController`, `SwingPose` (procedural `Motor6D.Transform` animation)
- [x] `Phase01_Combat` — 79 checks including an end-to-end swing against the real dummy
- [x] **Acceptance playtest passed: 94/94 checks across both specs, zero errors and zero warnings in both datamodels**

### Phase 2 — Skeleton enemy

- [x] `EnemyConfig` — Skeleton stats derived from the Phase 1 anchor (14 damage ≈ 7 player hits; 60 HP = 4 sword swings)
- [x] `EnemyBuilder` — minimal R6 Humanoid rig built from data, so `Humanoid:MoveTo` gives real wall collision
- [x] `EnemyService` — IDLE → NOTICE → CHASE → ATTACK → COOLDOWN → DEAD on one Heartbeat, detection, leashing, aggro-on-hit, stagger, procedural lunge, generation-guarded despawn
- [x] Enemies register as `Damageable`s and damage players through `applyDamageToPlayer`, so the sword arc and player i-frames both work unchanged
- [x] `RunSessionService.addGold` — kills award gold to an active run, and are worth nothing outside one
- [x] Practice skeleton in `Workspace/Static`, respawning, so the loop is playable before floors exist
- [x] `Phase02_Skeleton` — 42 checks
- [x] **Acceptance playtest passed: 136/136 checks across three specs, zero errors and zero warnings in both datamodels**

### Phase 3 — First complete room

- [x] `RoomConfig` — room templates as data; a room is a ~30-line table
- [x] `RoomBuilder` — floor, walls, two doorways built from the template around the room's own origin
- [x] `RoomService` — Open → Sealing → Clearing → Cleared, occupancy polled (never `.Touched`), doors driven server-side, encounter spawned and cleaned up with the room
- [x] Leaving mid-fight resets the room, so dying does not leave a sealed room the run can never re-enter
- [x] Practice room in `Workspace/Static`, walkable before floors exist
- [x] `Phase03_Room` — 37 checks covering geometry, sealing, the encounter, clearing, and reset
- [x] **Acceptance playtest passed: 173/173 checks across four specs, run twice for stability, zero errors and zero warnings in both datamodels**

### Phase 4 — Floor system

- [x] `WorldFolders` — folder ownership moved out of `FloorService`, breaking a real cycle: `RoomService` needs somewhere to parent a room and `FloorService` needs `RoomService` to make one
- [x] `FloorConfig` — the run's fixed template sequence, floor spacing, and the clear bonus
- [x] `FloorService` rewritten as the run orchestrator: `beginRun`, `loadFloor`, `advance`, `endRun`, deterministic per-floor origins, and a Heartbeat watching for the player leaving a cleared room
- [x] `RoomService.playersPastExit` / `entranceCFrame` — the exit trigger and the spawn point a floor loads you into
- [x] Floor number is authoritative in `RunSessionService`; gold and seed carry across floors
- [x] `Phase04_Floor` — 38 checks, including returning the tester to spawn so the manual pass is not left stranded
- [x] **Acceptance playtest passed: 211/211 checks across five specs, run twice, zero errors and zero warnings in both datamodels**

### Phase 5 — Room types (partial: 4 of 6)

Built: **Combat, Elite, Treasure, Healing.** All four are pure data entries — `RoomService` has no per-type branching, which is the actual Phase 5 acceptance criterion.

- [x] `SkeletonElite` — a data entry, not a new enemy: same state machine, 150 HP, 22 damage, 26 gold. Its telegraph still outlasts the dodge window, because an elite you cannot dodge is unfair rather than hard.
- [x] Reward rooms — a template with an empty `enemySpawns` clears itself the moment it seals, so no new code path was needed
- [x] `reward = { kind = "gold" | "heal" }` and a spinning prize the player walks into. No interaction UI, because there is none until Phase 12 and proximity needs none. The heal is a **fraction of max health**, so it keeps its value once Phase 9 raises the ceiling.
- [x] Floor rotation is now Combat → Treasure → Combat → Elite → Healing: fight, breathe, fight harder, recover
- [x] `Phase05_RoomTypes` — 72 checks
- [x] **Acceptance playtest passed: 283/283 checks across six specs, run twice, zero errors and zero warnings in both datamodels**

**Not built: Shop and Event.** A shop needs gold worth spending (Phase 7 loot) and a way to choose (Phase 12 UI); building it now would mean faking both. The spec asserts they stay absent so nobody half-adds one. They are a data entry away once those phases land.

### Phase 6 — Seeded procedural generation

The QA keystone. Every bug report can now carry a seed and a path and be replayed exactly.

- [x] `FloorPlan` — generation as a **pure function** of `(seed, depth, template)` returning plain data, entirely separate from the code that builds Instances. This is what makes the reproducibility test arithmetic rather than a playthrough.
- [x] **Two exit doors per cleared room**, offering two different seeded room types — the "choose a door" the pitch opens with. Where a door leads is keyed on the room you are in, so the choice genuinely branches without making the test space exponential.
- [x] Seeded room type, door options, enemy count and placement, and reward amounts. Placement uses bounded rejection sampling with a deterministic fallback, so rigs never stack and physics — which is not seeded — never gets to decide anything.
- [x] Encounter size grows with depth
- [x] Random seed per run, shown in the HUD and logged, over the previously-unused `RunStateChanged` remote
- [x] `RunState.path` records each door taken; `RunSessionService.describe()` prints `seed:839271 path:1,2,1`
- [x] Golden-hash regression with the constant committed in the spec, paired with `FloorConfig.generationVersion`
- [x] `Phase06_Generation` — 300+ checks, nearly all pure
- [x] **Acceptance playtest passed: 578/578 checks across seven specs, run twice, zero errors and zero warnings in both datamodels**

### Phase 7 — Loot

- [x] `LootConfig` — 5 relics and 3 armour pieces, each declaring plain named effect fields. Nothing knows how an effect is applied; `InventoryService` folds, combat reads the fold.
- [x] `InventoryService` — run-scoped holdings, modifier aggregation, walk-into pickups, Soul Shard payouts
- [x] **Drops are pre-rolled but not pre-decided.** The plan fixes a 0–1 roll per enemy; the *threshold* is evaluated live at kill time including Lucky Coin. That is what lets a relic change drop rates without making generation depend on inventory — and drops no longer depend on kill order.
- [x] Relics measurably change combat: outgoing damage, incoming damage, max health and stamina regen all read the aggregate. Conditional effects are evaluated when asked, never cached.
- [x] Soul Shards paid at run end, scaled by floors cleared, banked through `SaveService`
- [x] Golden hash regenerated and `generationVersion` bumped to 2, deliberately, in the same commit — loot is now part of what a seed promises
- [x] `Phase07_Loot` — 141 checks
- [x] **Acceptance playtest passed: 719/719 checks across eight specs, run twice, zero errors and zero warnings in both datamodels**

**Not built: weapon drops.** Dropping "a Sword" when the Sword is the only weapon is a reward that changes nothing; the archetypes and modifiers that make it a real choice are Phase 8's subject. The category exists so that becomes a data entry, and the spec asserts the pool stays weapon-free until then. *(Turned on in Phase 8.)*

### Phase 8 — Weapons

- [x] **Greatsword** (34 dmg, 0.92 s cycle, 7.5 reach, 140° sweep) and **Daggers** (9 dmg, 0.28 s, 4.0 reach, 90° jab) alongside the Sword
- [x] **None dominates.** Sustained damage is within 15% across all three, so the choice is commitment versus power rather than better versus worse. The spec asserts the spread stays under 25% — the moment one weapon wins on both axes there is no choice left.
- [x] `WeaponStats` — a pure fold of archetype plus modifiers into resolved numbers. Nothing downstream knows a modifier exists.
- [x] Five modifiers (Rusted, Heavy, Keen, Swift, Reaching), applying identically to every archetype, stacking multiplicatively, and naming the weapon they make
- [x] Speed scales the **whole cycle**, not just windup — a "fast" weapon with a slow recovery would be a lie
- [x] **A swing snapshots its stats**, so swapping weapons mid-swing cannot retune the swing in flight
- [x] Weapon drops are **generated, not catalogued**: archetype plus zero to two seeded modifiers. Picking one up equips it and swaps the model.
- [x] `Phase08_Weapons` — 158 checks
- [x] **Acceptance playtest passed: 877/877 checks across nine specs, run twice, zero errors and zero warnings in both datamodels**

### Phase 9 — Progression

**This phase closes the loop the MVP gate is defined by**: die, return to the lobby, buy something, start again stronger.

- [x] `UpgradeConfig` — four upgrades (Vitality, Power, Fortune, Heirloom) with linear cost curves and hard caps. The spec asserts the caps stay restrained so nobody quietly widens them.
- [x] `ProgressionService` — levels, costs, folded multipliers, and lobby shrines
- [x] **No purchase remote at all.** You walk into a shrine and the server decides; a client cannot ask for an upgrade or a price. That is the strongest server authority available — the attack surface does not exist.
- [x] Upgrades scale the **base**, run equipment adds on top: Vitality makes Iron Heart better in absolute terms rather than multiplying it too
- [x] Fortune applies where gold enters a run, so every source benefits rather than whichever ones someone remembered
- [x] Heirloom grants **seeded** starting relics, keyed separately from floor generation so buying it cannot shift layouts
- [x] Death clears the run and preserves the meta — asserted directly, both halves
- [x] `Phase09_Progression` — 64 checks
- [x] **Acceptance playtest passed: 941/941 checks across ten specs, run twice, zero errors and zero warnings in both datamodels**

### Phase 10 — Boss framework and The Warden

**This is the last system the MVP gate needs.** Floor 1 through a boss floor now works end to end.

- [x] `BossPhases` and `BossAttacks` — two pure controllers. Phase selection and attack choice are arithmetic with no world, so the headline criterion ("phase transitions fire at HP thresholds") is testable with no Studio.
- [x] **The arena is a room template**, not a parallel system. `RoomConfig.templates.Boss` goes through the same seal/clear/exit machinery as every other room.
- [x] `BossService` composes the two controllers; it owns the rig and the clock but not the rules
- [x] The Warden: 900 HP, three phases (Sword → Summon → Arena), a melee Cleave and a radial Slam that ignores facing
- [x] **Invulnerable through a transition** — checked the same way i-frames are, rejecting damage with reason `"transition"`, so a burst cannot skip an act
- [x] Every attack telegraphs longer than the dodge i-frame window, asserted for every attack on every boss, not just the Warden
- [x] Floor 10 (and every tenth floor after) is forced to the Boss template outside the generation pool; the floor before it offers the boss on both doors rather than faking a choice
- [x] `Phase10_Boss` — 76 checks, running the validators generically over every `BossConfig` entry rather than the Warden by name, so a second boss is provably a config rather than a fork
- [x] **Acceptance playtest passed: 1017/1017 checks across eleven specs, run twice, zero errors and zero warnings in both datamodels**

#### Fixed during Phase 10

- **A stale sed replacement silently dropped `RoomService.boss`.** An earlier automated edit's anchor text no longer matched after a StyLua reformat, so the accessor was never inserted — `python`'s `str.replace` fails silently on a non-match, which is exactly the danger of scripted edits without verifying the diff. Caught by the acceptance run, not by review; added `RoomService.boss` directly.
- **The acceptance spec drove a live boss fight without protecting the test player.** The Warden is real AI, not a mock, and keeps fighting through every `task.wait` in the spec — left unguarded it could kill the tester, firing `FloorService.endRun()` and destroying the room mid-assertion. Added a `surviveWait` helper that keeps the tester topped up through the fight without touching the boss's own timing.
- **A 1899s `execute_luau` stall that was not a code bug.** One suite run hung on the MCP bridge itself and was killed by the tool's idle timeout; the identical code completed normally in ~70s on retry. `CLAUDE.md` now says to never invoke a spec run as one long blocking call — launch it with `task.spawn` against `_G`, return immediately, and poll.

#### Fixed during Phase 9

- **The practice skeleton was chewing on idle players in the lobby.** Its 34-stud detect range reached the spawn pad, so you could not stand still and read shrine prices. Moved out of aggro range of both spawn and the shrines; verified by watching an idle player hold full health.

#### Fixed during Phase 6

- **`Rng` sub-stream keys collided.** Parts were folded with no separator, so `Rng.new(s, "k", 1, 23)` and `Rng.new(s, "k", 12, 3)` were the *same stream*. Invisible while every key was `(name, depth)` — and Phase 6 introduces exactly the colliding shape. Caught before any golden hash was committed, which is the only reason the fix was free. `Phase00_Boot` now regresses it.
- **Death on a cleared floor stranded the player.** They respawned at the lobby while the run continued 2000 studs away, unreachable. Death now ends the run, which is the designed roguelite loop anyway. **You will lose your run when you die — that is intended.**
- **A fixed entrance offset put the player outside small rooms.** `entranceOffset.Z = 16` is fine in a 40-deep Combat room and lands outside a 28-deep Healing room, so it never sealed. Now derived from the template's own interior.

#### Fixed during Phase 3

- **Practice skeleton respawn fired on any enemy death.** `onKilled` is a service-wide event and the listener did not filter by id, so killing any skeleton respawned the practice one on top of the live one, compounding each time. Found by auditing against the newly installed `roblox-engineer` skill's connection-leak checklist. `onKilled` now leads with the enemy id, and Phase 2 regresses it.
- **`CombatService.onPlayerAdded` could double-connect** — `Start` both connects `PlayerAdded` and loops `GetPlayers()`. Now returns early like `PlayerService` does.
- **`FeedbackController` highlight counter could ratchet** — if a flashed target was destroyed mid-tween, `Completed` might never fire and flashing would disable itself permanently at the cap. Now released exactly once by whichever of tween-completion or a timeout comes first.
- **Spec suite was not isolated from the live world.** The practice skeleton hit the player during the Phase 1 i-frame check. `RunAll` now quiesces and restores the practice world around the suite.

## Known issues

- **`StarterCharacterScripts.Health` is not synced.** The node was added to `default.project.json`, but Rojo does not hot-reload the project file and a restart would drop the plugin connection. Harmless right now: `PlayerService.bindCharacter` destroys the default regen script as a backstop, and the acceptance run confirms no `Health` script survives on the character. **Fix by restarting `rojo serve` at the start of the next session.**
- The right-click dodge fires once at the start of a camera-pan drag. Known and accepted; see M2.

## Resolved risks

- **There was no player-facing way to start a real run.** Found by your manual check: clearing the practice room opens two doors, and walking through either does nothing, which reads as "the rooms aren't connected." They never were connected — the practice room is a standalone Phase 3 test bed, and `FloorService.beginRun` had never been wired to anything a player could touch; it was only ever called by specs. Every phase from 4 (floor system) through 10 (boss) had been spec-tested but never once played by a human. Fixed with a physical "Descend" pad 20 studs south of spawn — walking onto it calls `beginRun` server-side, the same proximity-poll pattern the upgrade shrines already use (never `.Touched`). Regression-tested in `Phase04_Floor`.
- **The fix above was itself undiscoverable.** Your very next manual check: standing in the practice room again, same "no second room" read. Live state showed no run active and an empty `Generated` — you'd never found the gate. Root cause was `SpawnLocation`'s facing: it pointed north at the practice room, directly away from the gate at +Z, so the strongest signal a new player gets — their first camera direction — pointed at the one thing that doesn't lead anywhere. Fixed two ways: rotated spawn to face the gate (a hand-placed `Workspace` fixture, MCP territory, not a `src/` change), and replaced the flat "Descend" pad with a 24-stud neon beam and a two-line "START RUN / Step here to descend" sign visible across the lobby. Regression-tested in `Phase04_Floor` — asserts spawn's flat facing dots positively toward the gate, so a future spawn-pad edit cannot silently point it away again.
- **DataStore unavailable.** The place is published (`placeId 89607768864554`). Studio Access to API Services still needs enabling before Phase 13.
- **Rojo sync stalls on a confirmation.** Fix is Rojo Settings → Confirmation Behavior → Never.
- **Specs could not see service state.** `execute_luau` runs in its own Lua VM with its own module cache, so a directly-required spec tested fresh, un-booted service copies. Fixed with the `ServerStorage.OMF_RunSpecs` BindableFunction, whose callback is created in the boot context. Recorded in `CLAUDE.md`; this affects every future phase.
- **Stale Play sessions.** Rojo syncs into the Edit datamodel, so a running Play session keeps its original code and silently re-tests it. Always restart Play after a sync. Recorded in `CLAUDE.md`.
- **A suite that stops responding was undiagnosable.** `RunAll` now publishes the running spec's name to the `OMF_SpecRunning` DataModel attribute — chosen because an attribute is the one kind of state `execute_luau`'s separate VM can read. A stalled suite now names the spec it is sitting in instead of just returning "running".
- **`BindableEvent:Fire` is deferred here, not synchronous.** Confirmed by experiment: fire a Bindable and the listener's flag is still false on the next line. An audit of every fire site and listener in `src/` found no production code that depends on synchronous delivery — `FloorService.endRun` already fires last, and the deferred queue is FIFO, so a fatal hit's `onDamaged` is still accumulated before `onRunEnded` is handled. Specs must `task.wait()` after an action before asserting on a listener's effects. Recorded in `CLAUDE.md`.

## Playtest log

| Date | Phase | Specs | Errors | Result |
|---|---|---|---|---|
| 2026-09-19 | 00 | 14 / 14 | 0 server, 0 client | pass |
| 2026-09-19 | 01 | 94 / 94 (both specs) | 0 server, 0 client | pass |
| 2026-09-19 | 02 | 136 / 136 (three specs) | 0 server, 0 client | pass |
| 2026-09-19 | 03 | 173 / 173 (four specs, ×2 runs) | 0 server, 0 client | pass |
| 2026-09-19 | 04 | 211 / 211 (five specs, ×2 runs) | 0 server, 0 client | pass |
| 2026-09-19 | 05 | 283 / 283 (six specs, ×2 runs) | 0 server, 0 client | pass |
| 2026-09-19 | 06 | 578 / 578 (seven specs, ×2 runs) | 0 server, 0 client | pass |
| 2026-09-19 | 07 | 719 / 719 (eight specs, ×2 runs) | 0 server, 0 client | pass |
| 2026-09-19 | 08 | 877 / 877 (nine specs, ×2 runs) | 0 server, 0 client | pass |
| 2026-09-19 | 09 | 941 / 941 (ten specs, ×2 runs) | 0 server, 0 client | pass |
| 2026-09-20 | 10 | 1017 / 1017 (eleven specs, ×2 runs) | 0 server, 0 client | pass |
| 2026-09-20 | run review | 1102 / 1102 (twelve specs) | 0 server, 0 client | pass |
| 2026-09-20 | Sentry + reskin | 1268 / 1268 (thirteen specs) | 0 server, 0 client | pass |
| 2026-09-20 | balance digest | 1315 / 1315 (fourteen specs) | 0 server, 0 client | pass |
| 2026-09-20 | run gate | 1318 / 1318 (fourteen specs) | 0 server, 0 client | pass |
| 2026-09-20 | Cultist | 1481 / 1481 (fifteen specs) | 0 server, 0 client | pass |
| 2026-09-20 | gate signage | 1483 / 1483 (fifteen specs) | 0 server, 0 client | pass |
| 2026-09-20 | Chrome Husk fix + cyborg skins | 1549 / 1549 (sixteen specs) | 0 server, 0 client | pass |
| 2026-09-20 | enemy limbs | 1629 / 1629 (sixteen specs) | 0 server, 0 client | pass |

The suite now spends ~70 s in real waits (respawn, cooldowns, regen, chase, despawn, door tweens) when Studio has focus — several times longer when it does not, which is Studio throttling a backgrounded process, not a hang; the `OMF_SpecRunning` attribute says which spec it is sitting in either way.

## The post-run review

Not a roadmap phase. When a run ends, `RunReviewService` — a pure observer with no edge back into any other service — sends the run's shape to the TypeSafe System One API in a `task.spawn` and records a verdict: how frustrating the run probably felt, whether it contained a difficulty spike, and the single best explanation for how it ended. Nothing waits on it and nothing seeded can see it, so the reproducibility guarantee is untouched.

Three empirical findings shaped it, none of them assumptions:

- **~615 ms round trip**, six times the documented figure. Acceptable after a run, unacceptable anywhere near the tick.
- **Identical payloads return drifting numbers** (0.83 / 0.82 / 0.80 on one Choice, 3.08 / 3.07 / 3.04 on one Score). The winning option and the Score *level* are stable; the floats are not. So the verdict keeps the level index, never the float.
- **Confidence is well calibrated.** Every answer at 0.88 or above was correct; both wrong answers self-reported at 0.26 and 0.42. Hence a confidence floor, with anything below it filed as `unclassified` rather than believed — see below for why that floor is no longer a single number.

One design bug the experiments caught: the root-cause question originally had no no-match option, and confidently answered "attrition" for a run in which nobody died. Adding `survived` fixed it (0.99 confidence on a survived run, 0.90 on a boss wall). `RunReview`'s spec asserts that option still exists.

**Still needed from you before it can reach the API:** enable HTTP requests in Experience Settings, and add a `TYPESAFE_API_KEY` secret in Creator Hub. Until then every run simply ends without a verdict, which is the designed failure mode and is regression-tested.

**Revisited against the live TypeSafe docs.** The API contract hadn't drifted, but the docs argue against a single uniform confidence floor: a wrong `frustrationLevel` is a soft miss, a wrong `rootCause` actively misleads a QA session into chasing a pattern that was never real. Split into `frustrationConfidenceFloor = 0.7` (unchanged, matches the measurement above) and `rootCauseConfidenceFloor = 0.85` (new, stricter — no equivalent measurement yet, treat it as a starting point).

**Added the balance digest.** A second, aggregate use of the same API: `RunReviewService.runDigest()` batches every review this session has recorded and asks three questions across the whole set — which room type most often coincides with frustration or death, whether the difficulty curve reads front-loaded / even / back-loaded, and whether similar-depth runs feel consistent with each other. Room type per run is reconstructed from just `(seed, path)` via `FloorPlan`'s existing pure functions — telemetry never had to track it going in. Gated below 3 samples so a call is never spent on a batch too small to mean anything. It is a QA report, not a gameplay system, and it only covers runs played since the last boot — there's no Phase 13 save system yet to persist across sessions. Exposed the same way as the spec suite: `ServerStorage.OMF_RunBalanceDigest`, a BindableFunction created in the boot context, invoked with the same `task.spawn` + poll pattern (it yields — a live HTTP call).

## Setting pivot + the Signal Sentry

Built ahead of the Phase 1/3 gates, at explicit instruction: the roadmap's own rule is to hold content until those gates are called, but the user asked to keep going regardless, treating this project as a test of build velocity and quality rather than a strict phase-gated production. Worth knowing if you're reading this ledger to judge what "done" means at any given commit — the gates are still open and still matter for a real ship decision.

Two things landed together because the second prompted the first:

- **The Bone Archer** (`kind = "Archer"`) — biome 1's design always named Skeleton, Archer and Cultist, but only Skeleton existed, which made "back off" the dominant strategy against every fight in the game. It's a genuine ranged enemy: holds a band (`preferredRange`/`retreatRange`), fires a real travelling projectile through `CombatService.applyDamageToPlayer` (so player i-frames apply to it exactly as they do to a sword), and the draw is tuned longer than the dodge window on purpose — you're meant to read the charge, not the bolt. Wired into generation as a new **Outpost** room (`RoomConfig.templates.Outpost`, `encounter.kind = "Archer"`), added to `FloorConfig.pool` — `generationVersion` bumped 4→5 and the golden hash regenerated in `Phase06_Generation`, both deliberate per that file's own contract.
- **The setting pivot** (see `GAME_DESIGN.md`'s Setting section) — cyborg / industrial-apocalypse, MÖRK BORG-inspired, decided now rather than after biome 2 committed more content to the old fantasy-crypt assumption. Reskinned entirely through `displayName`, rig colour/material and flavour text; internal `kind` ids are untouched because they're load-bearing for `RoomConfig`, loot and the golden hash. Skeleton → **Rust Husk**, SkeletonElite → **Chrome Husk**, Archer → **Signal Sentry**, biome 1 → **The Corroded Choir**. The Warden needed no rename — "an overseer AI" and "a crypt guardian" are the same boss read two ways.

Two Creator Store assets, verified insertable and free at time of writing, cover the Sentry's fire and impact (`bowRelease`/`arrowImpact` in `AssetIds.luau`, swapped for laser-flavoured ones to match the reskin — a sci-fi shot and a laser impact rather than a bow, since the enemy is now a drone, not an archer). The user gave standing permission to pull from the Creator Store "to your liking" for this kind of work.

New spec: `tests/specs/Archer.luau` — the numbers (fragility, telegraph-vs-flight-time math, kiting band), and a live section confirming the bolt is a real travelling object, damages through the same i-frame gate as everything else, and the sentry actually backs away when crowded.

## The Signal Cultist

The third enemy `GAME_DESIGN.md` named alongside Skeleton and Archer, closing that gap. Reads as a cyborg zealot overloading its own battery into the machine: it rushes at 14 studs/s (faster than the Rust Husk's 11, still slower than the player's 16), arms a fuse the instant it comes within 8 studs, and detonates for area damage in a 9-stud radius rather than landing a normal hit. The torso tweens from resting ember-orange to warning red over the fuse's 0.9s, so the telegraph needs no separate VFX system.

The design intent is the opposite of the other two enemies: the Rust Husk is a trade, the Signal Sentry is a threat you close on, the Cultist is a threat you back away from. Two properties make that honest rather than just "a delayed hit":

- **The blast radius (9) is deliberately larger than the arming trigger (8).** If it were the reverse, standing still the instant it stops moving would already be safe, and the fuse would be decoration.
- **Killing it before the fuse ends denies the explosion outright.** `detonate()` is only ever called from the fuse completing, never from taking lethal damage — a sword kill goes through the same `die()` every other enemy death does, with no area effect attached. This is the real counterplay for a player who reacts fast enough, not just running away.

Wired into generation as a new **Sanctum** room (`RoomConfig.templates.Sanctum`, `encounter.kind = "Cultist"`), added to `FloorConfig.pool` — `generationVersion` bumped 5→6, golden hash regenerated. One more Creator Store asset (`cultistDetonation` in `AssetIds.luau`, verified insertable and free) covers the boom, broadcast through a new `Detonation` feedback kind that names no single target — a blast can catch several players or none, unlike `RangedImpact`.

New spec: `tests/specs/Cultist.luau` — the safety property (blast radius exceeds trigger range) as an explicit assertion, a live section confirming it actually rushes and arms, that retreating past the blast radius after arming takes no damage, that standing in the blast when the fuse ends does, and that killing it early costs the player nothing.

## Chrome Husk was unbeatable, and every enemy now wears a real skin

Two things you reported together, fixed together.

**The balance bug.** Chrome Husk's `attackRange` (7.5) reached 2 full studs past the player's own 5.5-stud sword — the base Rust Husk only reaches 1 stud past it — and `attackWindup` (0.38) left only 0.08s of slack over the 0.30s dodge window, versus the base Husk's 0.15s. Combined with `walkSpeed` (13) closing to within 3 studs of the player's own 16, retreating and re-engaging was never actually possible: an elite that cannot be dodged is not harder, it is unfair. All three numbers pulled back — `attackRange` to 6.5 (matching the base Husk), `attackWindup` to 0.42 (restoring real reaction margin), `walkSpeed` to 12.

The existing spec had already asserted `attackWindup > CombatConfig.dodge.iframes` and passed the whole time — 0.38 > 0.30 is technically true. That is the bug in the *test*, not just the config: a check that only verifies a positive sign catches nothing near the boundary. Tightened to require real slack (`>= 0.1`), and added the missing other half — `elite.attackRange <= basic.attackRange` — since nothing had ever asserted an elite shouldn't out-range the enemy it's a harder version of.

**The reskin.** Every enemy kind, plus the Warden, now wraps a Creator Store texture over its rig — rust-streaked metal on the Rust Husk, chrome on the Chrome Husk, a cyber-tech circuit board on the Signal Sentry, hazard stripes on the Signal Cultist, a server rack on the Warden. Applied as `Decal`s layered over each rig's existing material and colour, never replacing them: the colour is still the actual gameplay signal read at range (cyan means Sentry, ember means Cultist), the texture is surface detail for up close, and a texture that fails to load degrades to "flat colour" rather than a missing/pink part. Wrapped on all four side faces of the Torso so it holds together from any angle a top-down camera catches.

Worth stating plainly: **I could not visually verify these render correctly**, and the evidence I have is genuinely mixed. What IS verified, in the new `EnemySkins.luau` spec: every kind's `textureId` resolves to the id `AssetIds.textures` names for it, every built rig gets exactly four Decals covering Front/Back/Left/Right, and the base colour survives independent of the texture — so even in the worst case, a broken texture degrades to a solid, correctly-coloured part, never a missing/pink one.

## The reskin still looked wrong, because it was never the texture

Your next report — a screenshot of the Rust Husk standing next to your own avatar — showed exactly why: **it was a single rust-coloured box next to a fully-clothed character.** Not a texture problem. A shape problem. The rig this whole project has used since Phase 2 is three parts: HumanoidRootPart, Torso, Head. No arms, no legs. A decal on a torso is still a decal on a crate if the crate has no limbs.

Fixed by giving `EnemyBuilder.buildFromRig` four more parts — Left Arm, Right Arm, Left Leg, Right Leg — R6-proportioned off the torso's own size, jointed to it the same way Neck already joints the head. Nothing about combat needed to change: `CombatService.damageableFor` already walks up to 4 ancestors from whatever part was actually hit (its own comment says "a hit part is a limb or a child mesh, not the root" — the system was built anticipating this and just never had limbs to prove it on), and the swing/explosion queries scan the whole volume rather than named parts, so arms and legs are valid hit targets with zero changes to `CombatService.luau`. Limbs are `CanCollide = false` (same as Head), so Torso stays the sole physical collider and the four new unanchored rigid bodies cannot introduce jitter.

Confirmed visually, with a genuinely surprising result: a `Skeleton` model built and screenshotted this way showed the rust decal rendering correctly — mottled rust texture on every part, not a flat colour. But the exact same asset id, and four other candidate decals besides, came back **blank** on isolated test parts moments later, even after a full minute's wait. I could not find a pattern that explains the difference (material, timing, and part naming were all tried as explanations and none held up), so the honest position is: **decal rendering could not be reliably verified from here, in either direction** — it worked once, in the one test that matters most (an actual built enemy model), and failed unpredictably elsewhere. The shape fix (limbs) is the one I'm fully confident in, since it was screenshotted directly and is now spec-tested (`EnemySkins.luau` asserts all four limbs exist, are jointed to the torso, and do not collide). **Your own next look at the game is the real answer on the decals** — if any of them read as a flat, textureless colour, that enemy's `rig.textureId` in `EnemyConfig.luau` (or `BossConfig.luau` for the Warden) is the one line to revisit.

## Next

1. **You:** walk the slice and call both gates — Phase 1 (does swinging feel good?) and Phase 3 (is spawn → fight → win → leave fun?). Everything after this is built on those answers.
2. Decide whether Shop and Event should wait for Phase 7/12 as I assumed, or get placeholder versions sooner.
3. Phase 11 — the second biome (The Forgotten Crypt), only after Phase 1–10 is genuinely playable, per the roadmap's own rule.

## Where to go in-game

Everything is walkable from the spawn pad:

- **Training dummy** — 18 studs north (−Z). Takes 14 swings, tilts, resets.
- **Practice skeleton** — beside it, respawns 6 s after you kill it.
- **Practice room** — 78 studs north. Walk in and the entrance seals, an encounter spawns, and clearing it opens **two** exits. **Those exits are decorative** — this is a standalone practice/test room, not floor 1 of an actual run, so walking through either door leads nowhere. Confirmed and fixed as a real gap below. Walk back out mid-fight and the room resets.
- **The run gate** — directly ahead of spawn (you now face it on join), a glowing pillar labelled **START RUN**. Walk onto it to start an actual run: a real seeded floor 1, with real exits that really lead to floor 2, 3, and onward through the boss at floor 10. This did not exist before 2026-09-20 — see the bug ledger. Its first version was easy to miss entirely — a flat pad labelled "Descend," 20 studs behind a spawn that faced the practice room instead — caught by manual QA the same session it shipped. Fixed twice, both in the bug ledger.
- **Upgrade shrines** — 26 studs west, a row of four. Each shows its level and cost; walk into one to buy. You need Soul Shards, which you get by ending a run.
- **The Warden** — walk a run from the gate to floor 10, or call `FloorService.loadFloor(10, "Combat")` directly in a spec; the depth forces the Boss template regardless.

## Phase gates

Two hard stops. Phase 1: if swinging a sword at nothing does not feel good, fix feel before adding an enemy. Phase 3: the vertical slice — if spawn → fight → win → leave is not fun, do not proceed to the floor system.
