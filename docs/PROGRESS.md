# One More Room — progress ledger

Canonical status. The build tracker artifact is a published *view* of this file, synced one way at the end of each session. Nothing is ever read back from the artifact into the repo.

Tracker: https://claude.ai/artifact/AooT5JjezgLaNBticyAfqj
Remote: https://github.com/RUSTEMATOR/OneMoreRoom

## Current milestone

Phase 10 — Boss framework and The Warden

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

- **DataStore unavailable.** The place is published (`placeId 89607768864554`). Studio Access to API Services still needs enabling before Phase 13.
- **Rojo sync stalls on a confirmation.** Fix is Rojo Settings → Confirmation Behavior → Never.
- **Specs could not see service state.** `execute_luau` runs in its own Lua VM with its own module cache, so a directly-required spec tested fresh, un-booted service copies. Fixed with the `ServerStorage.OMF_RunSpecs` BindableFunction, whose callback is created in the boot context. Recorded in `CLAUDE.md`; this affects every future phase.
- **Stale Play sessions.** Rojo syncs into the Edit datamodel, so a running Play session keeps its original code and silently re-tests it. Always restart Play after a sync. Recorded in `CLAUDE.md`.

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

The suite now spends ~70 s in real waits (respawn, cooldowns, regen, chase, despawn, door tweens). That is not a hang.

## Next

1. **You:** walk the slice and call both gates — Phase 1 (does swinging feel good?) and Phase 3 (is spawn → fight → win → leave fun?). Everything after this is built on those answers.
2. Decide whether Shop and Event should wait for Phase 7/12 as I assumed, or get placeholder versions sooner.
3. Phase 10 — the boss framework and The Warden, which is the last system the MVP gate needs.

## Where to go in-game

Everything is walkable from the spawn pad:

- **Training dummy** — 18 studs north (−Z). Takes 14 swings, tilts, resets.
- **Practice skeleton** — beside it, respawns 6 s after you kill it.
- **Practice room** — 78 studs north. Walk in and the entrance seals, an encounter spawns, and clearing it opens **two** exits. Walk back out mid-fight and it resets.
- **Upgrade shrines** — 26 studs west, a row of four. Each shows its level and cost; walk into one to buy. You need Soul Shards, which you get by ending a run.

## Phase gates

Two hard stops. Phase 1: if swinging a sword at nothing does not feel good, fix feel before adding an enemy. Phase 3: the vertical slice — if spawn → fight → win → leave is not fun, do not proceed to the floor system.
