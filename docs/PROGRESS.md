# One More Room — progress ledger

Canonical status. The build tracker artifact is a published *view* of this file, synced one way at the end of each session. Nothing is ever read back from the artifact into the repo.

Tracker: https://claude.ai/artifact/AooT5JjezgLaNBticyAfqj
Remote: https://github.com/RUSTEMATOR/OneMoreRoom

## Current milestone

Phase 1 — Player movement & basic combat

## Completed

### Phase 0 — Foundation

- [x] Rokit toolchain pinned in-repo (rojo 7.7.0, selene 0.31.0, StyLua 2.5.2)
- [x] Rojo Studio plugin installed and connected; place saved and published
- [x] Repo scaffold, git init, `.gitignore`, `selene.toml`, `stylua.toml`, pre-commit hook
- [x] `default.project.json` with the `$path` ownership boundary
- [x] `CLAUDE.md` — ownership rule, lifecycle rules, MCP limitations, skills table
- [x] Shared: `Rng` (seeded), `Net` (remote manifest), `BuildStamp`, `PlayerDataSchema`
- [x] `ServerMain` + five services wired (`PlayerService`, `SaveService`, `FloorService`, `CombatService`, `RunSessionService`)
- [x] `ClientMain` + three controllers wired
- [x] Spec harness (`Spec`, `RunAll`) and `Phase00_Boot`
- [x] Project-local skills: `playtest`, `phase-start`, `phase-done`, `repro`
- [x] **Acceptance playtest passed** — see log below

## Current

- [ ] Phase 1 — health, stamina, sword light attack, dodge with i-frames, death, respawn

## Known bugs

None recorded.

## Resolved risks

- **DataStore unavailable.** The place is published (`placeId 89607768864554`), so this is retired ahead of Phase 13. Studio Access to API Services still needs enabling before then.
- **Rojo sync stalls on a confirmation.** A connected plugin can still hold the patch behind an Accept/Abort dialog. Fix is Rojo Settings → Confirmation Behavior → Never; recorded in `CLAUDE.md`.

## Next

1. Phase 1 — player health and stamina on the server, sword light attack with windup/active/recovery, dodge on Shift with stamina cost and i-frames, death and respawn
2. Write `tests/specs/Phase01_Combat.luau` and append it to `RunAll`
3. **Gate:** if swinging a sword at nothing does not feel good, fix feel before adding an enemy

## Playtest log

| Date | Phase | Specs | Errors | Result |
|---|---|---|---|---|
| 2026-09-19 | 00 | 14 / 14 | 0 server, 0 client | pass |

## Phase gates

Two hard stops in the roadmap. Phase 1: if swinging a sword at nothing does not feel good, fix feel before adding an enemy. Phase 3: the vertical slice — if spawn → fight → win → leave is not fun, do not proceed to the floor system.
