# Architecture

## Runtime tree

```
ReplicatedStorage
├── Shared          ← src/Shared    (Rojo-owned)
├── Remotes         ← folder declared by Rojo, children created at runtime by Net
└── Assets          ← folder only

ServerScriptService ← src/Server    (Rojo-owned)
├── ServerMain      (Script)
└── Services/
    ├── PlayerService
    ├── SaveService
    ├── FloorService
    ├── CombatService
    └── RunSessionService

ServerStorage
└── Specs           ← tests/specs   (Rojo-owned, server-only, never replicates)

StarterPlayer/StarterPlayerScripts ← src/Client (Rojo-owned)
├── ClientMain      (LocalScript)
└── Controllers/{Input, Hud, Camera}

Workspace           (MCP territory)
├── Static          hand-authored, persists
└── Generated       code-authored, cleared at the start of every run
```

`Lighting`, `SoundService`, and `StarterGui` are deliberately absent from `default.project.json`. A service that is not mentioned is not managed at all, which is safer and leaner than declaring it.

## Why Remotes are half-static

The folder is Rojo-declared so it exists in the Explorer during **Edit** mode, which lets `inspect_instance` and `search_game_tree` see the structure without starting a playtest. The remotes inside it are created at runtime by `Shared/Net.luau`, which holds the manifest as a Lua table.

The alternative — static `.model.json` remotes — would mean every remote name appears in JSON *and* in Lua, two files to desync, with a typo surfacing as a silent `nil` at runtime. One text source of truth is worth more here. Because the folder has no `$path`, Rojo never deletes the runtime-created children.

## Boot

`ServerMain` runs `Net.buildRemotes()` first so remotes exist before any service references them, then requires every service from an explicit ordered list, then all `Init`, then all `Start`, then sets `OMF_ServerReady`. `ClientMain` mirrors it and sets `OMF_ClientReady` on the LocalPlayer.

`Init` may not call other services; `Start` may not yield. Those two restrictions are what make a registry or DI container unnecessary — see `CLAUDE.md`.

## Determinism

`Shared/Rng.luau` wraps `Random.new` and derives sub-streams by string key: `Rng.new(seed, "floor", depth)`. Keying matters — it means adding a new consumer cannot shift an existing one's sequence, so a Phase 7 loot table cannot silently change Phase 6 floor layouts.

Nothing in `src/` may call `math.random`. The pre-commit hook greps staged diffs and rejects it.

## The QA loop

Automated by `/playtest`. Steps 1–3 are cheap and catch most failures without touching Studio.

1. **Static gate** (~2s, no Studio). `stylua --check src tests`, `selene src tests`, `rojo build default.project.json -o "$SCRATCH/omf.rbxl"`. All exit 0 or stop — a syntax error makes every later step meaningless. `rojo build` here is a compile check, not a deliverable: it validates the project JSON and parses every file.
2. **Sync gate.** `curl -sS localhost:34872/api/rojo` proves *serving*, which is not the same as the plugin being *connected*. Bump `Shared/BuildStamp.luau` at phase start, then read `ReplicatedStorage.Shared.BuildStamp.Source` via `execute_luau` in the `Edit` datamodel. If it lacks the id just written to disk, stop and ask the user to click Connect.
3. **Timestamp baseline.** Capture `os.time()` as `t0`. There is no tool to clear the console, so filtering by time is the substitute.
4. **Start play.** `start_stop_play(is_start: true)`, then poll `get_studio_state` until the `Server` and `Client` datamodels appear.
5. **Wait for boot.** Poll `game:GetAttribute("OMF_ServerReady")` up to ~10 times.
6. **Run the suite.** `require(game:GetService("ServerStorage").Specs.RunAll)()` in the Server datamodel. Every phase appends its spec to `RunAll`, so later phases re-run all earlier specs for free — that is the regression check.
7. **Assert zero errors, in both datamodels.** Server and client have separate `LogService`s. Sweep `GetLogHistory()` in each, filter `timestamp >= t0`, count `MessageError` and `MessageWarning`. Pass = zero errors in both; warnings go in the ledger. Errors inside `task.spawn` do surface here; errors swallowed by a bare `pcall` do not, so async-heavy phases also hook `ScriptContext.Error` in the spec.
8. **Interaction**, if the phase needs it. `character_navigation` / `user_keyboard_input`, Client datamodel only. Re-run 6 and 7 afterwards.
9. **Evidence.** The structured JSON from 6–7 is primary. `screen_capture` is secondary; for deterministic images, stop play and capture in Edit with explicit camera coordinates.
10. **Stop and sweep.** `start_stop_play(is_start: false)`, then one `get_console_output` for a human-readable tail. Narrative only — the verdict was already reached in step 7.

Why `OMF_ServerReady` matters as a *second* signal: a clean log alone cannot distinguish "everything worked" from "boot crashed before anything could log." Requiring both closes that gap.

## Known risks

| Risk | Mitigation |
|---|---|
| Rojo silently clobbers a Studio-side script edit | `$path` boundary, blanket `multi_edit` ban, blocking BuildStamp probe |
| Plugin serving but not connected | Step 2 is mandatory and blocking; never fix Studio-side |
| DataStore unavailable before Phase 13 | Retired: the place is published (`placeId 89607768864554`). `SaveService.isPersistent()` still guards it; enable Studio Access to API Services before Phase 13 |
| "Zero errors" false negative | Timestamp-filtered sweep in *both* datamodels plus the independent `OMF_ServerReady` signal |
| Procedural content drift | `Generated` cleared each run, `Static` never touched by code; spec asserts `Generated` is empty pre-run |
| Seed reproducibility breaks | Pre-commit `math.random` grep plus golden-hash layout spec |
