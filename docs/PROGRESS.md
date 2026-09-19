# One More Floor — progress ledger

Canonical status. The build tracker artifact is a published *view* of this file, synced one way at the end of each session. Nothing is ever read back from the artifact into the repo.

Tracker: https://claude.ai/artifact/AooT5JjezgLaNBticyAfqj

## Current milestone

Phase 0 — Foundation

## Completed

- [x] Rokit toolchain pinned in-repo (rojo 7.7.0, selene 0.31.0, StyLua 2.5.2)
- [x] Rojo Studio plugin installed
- [x] Repo scaffold, git init, `.gitignore`, `selene.toml`, `stylua.toml`, pre-commit hook
- [x] `default.project.json` with the `$path` ownership boundary
- [x] `CLAUDE.md` — ownership rule, lifecycle rules, MCP limitations, skills table
- [x] Shared: `Rng` (seeded), `Net` (remote manifest), `BuildStamp`, `PlayerDataSchema`
- [x] `ServerMain` + five services wired (`PlayerService`, `SaveService`, `FloorService`, `CombatService`, `RunSessionService`)
- [x] `ClientMain` + three controllers wired
- [x] Spec harness (`Spec`, `RunAll`) and `Phase00_Boot`
- [x] Project-local skills: `playtest`, `phase-start`, `phase-done`, `repro`
- [x] Static gate green: stylua, selene, rojo build

## Current

- [ ] Phase 0 acceptance playtest in Studio (needs the user to click Plugins → Rojo → Connect)

## Known bugs

None recorded yet.

## Next

1. User clicks Connect in Studio, then Save As to `place/OneMoreFloor.rbxl`
2. Run the Phase 0 acceptance playtest — `OMF_ServerReady`, `OMF_ClientReady`, `RunAll` all-pass, zero errors in both datamodels
3. Publish the build tracker artifact
4. Phase 1 — player health, stamina, sword attack, dodge, death, respawn

## Phase gates

Two hard stops in the roadmap. Phase 1: if swinging a sword at nothing does not feel good, fix feel before adding an enemy. Phase 3: the vertical slice — if spawn → fight → win → leave is not fun, do not proceed to the floor system.
