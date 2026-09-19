# One More Room — progress ledger

Canonical status. The build tracker artifact is a published *view* of this file, synced one way at the end of each session. Nothing is ever read back from the artifact into the repo.

Tracker: https://claude.ai/artifact/AooT5JjezgLaNBticyAfqj
Remote: https://github.com/RUSTEMATOR/OneMoreRoom

## Current milestone

Phase 2 — Skeleton enemy

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

The Phase 1 suite spends ~12 s in real waits (respawn, cooldowns, regen, auto-reset). That is not a hang.

## Next

1. **You:** run the manual checklist and call the Phase 1 gate
2. Phase 2 — the Skeleton: one enemy, one state machine (IDLE → DETECT → CHASE → ATTACK → COOLDOWN), health, contact damage, death, hit reaction, and a reward drop
3. Phase 3 — the first complete room, and the vertical-slice gate

## Phase gates

Two hard stops. Phase 1: if swinging a sword at nothing does not feel good, fix feel before adding an enemy. Phase 3: the vertical slice — if spawn → fight → win → leave is not fun, do not proceed to the floor system.
