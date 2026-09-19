# One More Room

A roguelite tower climber for Roblox. Choose a door, fight, loot, upgrade, climb. Boss every 10 floors. Die, keep some progression, run again.

## Start every session with this

1. Read this file, `docs/ARCHITECTURE.md`, and `docs/PROGRESS.md`.
2. Resolve the Studio id with `list_roblox_studios` — **never hardcode it**, it changes whenever Studio restarts.
3. Bump `src/Shared/BuildStamp.luau` and run the sync gate (see *Verification*).
4. Continue from the current milestone in `PROGRESS.md`. Do not redo completed work.

The `/phase-start` and `/phase-done` skills automate this.

## The one rule that matters most: who owns what

Code on disk is the source of truth. Rojo syncs disk → Studio. The boundary is enforced by Rojo's own semantics and is readable straight off `default.project.json`:

> A node **with `$path`** → Rojo deletes unknown children and overwrites `Source` on every sync. **Rojo territory.**
> A node **without `$path`** → Rojo leaves it completely alone. **MCP territory.**

Therefore:

- **Scripts live on disk only.** Edit `src/` and `tests/` with the file tools.
- **`multi_edit` is banned project-wide.** Every script sits under a `$path`, so there is no legitimate use. Treat any `multi_edit` call as a bug. Editing a script in Studio means it is silently overwritten — or deleted — on the next sync, with no error.
- **`execute_luau` is read-and-assert only.** Never build persistent geometry with it; a one-off `Instance.new` in Edit mode is invisible to git and will confuse the next session.
- **`rojo syncback` is banned.** It reverses the direction of truth and destroys the whole model.
- World Instances go in `Workspace`, split into **`Workspace/Static`** (hand-authored, persists) and **`Workspace/Generated`** (code-authored, cleared at the start of every run by `FloorService`).

If disk edits are not showing up in Studio, the plugin is not connected. **Stop and ask the user to click Plugins → Rojo → Connect.** Never work around it from the Studio side — that is how you end up with two divergent sources of truth.

A connected plugin can still be holding the sync: read the Rojo panel's text with `execute_luau` over `PluginGuiService`, and if it shows a pending **Accept / Abort** confirmation, ask the user to click Accept. Rojo's **Settings → Confirmation Behavior** should be **Never** for this project — disk is authoritative here by design, so the confirmation is guarding against precisely the behavior we want.

**Team Create must stay off.** It and Rojo both want to own script contents. The console line "joined live editing session" means it is on.

## Conventions

- **Never name a module after a `game:GetService()` name.** This is why the run-state service is `RunSessionService`, not `RunService` — the latter shadows the real service wherever both are needed, and the resulting bug reads as correct code.
- **Never call `math.random`.** Use `Shared/Rng.luau`. A single bare `math.random` destroys seeded-run reproducibility and is nearly impossible to find afterwards. The pre-commit hook rejects it.
- **Server authority, always.** Clients send intent (`RequestAttack`); they never report outcomes. Damage, gold, loot, purchases, and floor completion are computed server-side. Phase 17 audits this; it does not retrofit it.
- **Services are plural from day one.** State is keyed by player and functions take player lists, even while that list has one entry. Phase 14 tunes co-op scaling rather than rearchitecting.
- **Content is Lua data, not Studio-authored instances.** A room template is a ~20-line table, diffable one line at a time and parameterizable by seed. Exceptions: imported art referenced by ID from `Shared/Assets/AssetIds.luau`, and genuinely hand-sculpted set pieces as committed `.rbxmx`. If you edit a `.rbxmx` in a third phase, it should have been data.

## Service lifecycle

A service is a ModuleScript returning a table with optional `Init()` and `Start()`. Three rules:

1. **`Init` may not call other services.** So load order cannot cause a nil-reference, and circular requires are fine.
2. **`Start` may not yield.** So boot is synchronous and the "everything booted" signal is trustworthy. A service needing a loop `task.spawn`s it itself inside `Start`.
3. Services reference each other by plain sibling `require` — no locator, no injection, full type inference.

`ServerMain` requires from an explicit ordered list, not `:GetChildren()`: boot order is part of the contract, shows in diffs, and fails loudly on a typo. It sets `OMF_ServerReady` when done. Errors are deliberately uncaught — a crash leaves the attribute unset and produces a clean stack trace, failing both QA signals instead of hiding.

## Verification

Full loop in `docs/ARCHITECTURE.md`, automated by the `/playtest` skill. The short version:

```sh
stylua --check src tests && selene src tests && rojo build default.project.json -o "$SCRATCH/omf.rbxl"
```

then start play, poll `OMF_ServerReady`, run `require(ServerStorage.Specs.RunAll)()`, and sweep `LogService:GetLogHistory()` in **both** the Server and Client datamodels filtering on a timestamp captured before the run. **Pass = zero `MessageError` in both.**

## Roblox Studio MCP skills

Available on demand via `mcp__Roblox_Studio__skill`. Use them instead of guessing:

| Skill | When |
|---|---|
| `rbx-docs-search` | **Before writing any unfamiliar Roblox API call.** Do not work from memory |
| `rbx-debug` | Breakpoints and thread inspection — **before** reaching for print statements |
| `rbx-scene-analysis` | **Before assuming place structure** |
| `rbx-unit-test` | Roblox-native unit-test guidance |
| `rbx-perf-profiling` | Phase 15/16, when juice and co-op start costing frames |
| `rbx-device-simulator-lua` | Phase 12, HUD on mobile form factors |
| `rbx-configs-experimentation` | Phase 16 — ConfigService for live-tunable balance values |
| `rbx-convert-to-streaming` | Phase 11+, if the tower needs streaming |
| `rbx-create-skill` | Authoring project-local skills |

## MCP limitations to remember

- **In Edit mode, `RunService:IsServer()` *and* `IsClient()` both return `true`.** Never branch on those — use `IsRunning()` / `IsStudio()`.
- `character_navigation` and `user_keyboard_input` are **Client-datamodel only** and require play mode.
- `screen_capture` is edit-time oriented and takes no datamodel selector. For deterministic visual evidence, stop play and capture in Edit with explicit camera coordinates.
- `get_console_output` has no severity filter, no time filter, and no clear. Use `LogService:GetLogHistory()` — it returns structured `{ message, timestamp, messageType }`.
- `wait_job_finished` needs a `jobId` from an `async: true` call; no tool in the QA loop exposes that. Bounded-poll instead.
- `search_game_tree` caps at 200 nodes, default depth 3. Always scope with `path`.
- **No MCP tool opens or saves a place file.** This is why the loop uses `rojo serve`, not `rojo build`.
- The place is published (`placeId 89607768864554`), so DataStore is reachable. **Studio Access to API Services** (Game Settings → Security) still has to be enabled before Phase 13.
- `studio_id` changes on every Studio restart — the acceptance run for Phase 0 hit this. Always resolve it with `list_roblox_studios`.

## Layout

```
src/Server/     → ServerScriptService   (ServerMain + Services/)
src/Client/     → StarterPlayerScripts  (ClientMain + Controllers/)
src/Shared/     → ReplicatedStorage.Shared
tests/specs/    → ServerStorage.Specs   (server-only, never replicates)
docs/           → design, architecture, combat, economy, progress ledger
```

Rojo name mapping: `*.server.luau` → `Script`, `*.client.luau` → `LocalScript`, plain `*.luau` → `ModuleScript`, folder → `Folder`. **Never add `init.luau` to `src/Server/Services/`** or the folder collapses into a ModuleScript.
