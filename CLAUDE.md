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

## On the `roblox-engineer` skill

A general-purpose `roblox-engineer` skill is installed at `~/.claude/skills/`. It is useful background, but **this file wins where they disagree**, and they do disagree:

| It says | We do | Why ours |
|---|---|---|
| `src/shared`, lowercase | `src/Shared` | Rojo maps the folder name straight to `ReplicatedStorage.Shared`; renaming breaks every `require` |
| kebab-case docs | `docs/COMBAT.md` | Existing convention, no reason to churn |
| TestEZ | `tests/specs` + a 30-line `Spec` harness | Deliberate Phase 0 decision — revisit past ~15 spec files, not before |
| `.forgewright/project-profile.json` | not used | Not our toolchain |
| Client sends a target, server distance-checks it | Remotes take **zero arguments** | Ours is strictly stronger: there is no target to spoof |
| `Humanoid:TakeDamage` | write `Health` directly | `TakeDamage` is silently swallowed by a ForceField |

Do not restructure the project to match it. Its two genuinely useful checklist items — scale per-frame work by delta time, and do not leak `RBXScriptConnection`s — are conventions here, and auditing against them found two real bugs, so they earn their keep.

**It also contains factually wrong APIs.** Its NPC section uses `Instance.new("PathfindingAgent")` and `Humanoid.PathfindingAgent`, neither of which exists, and it puts a `task.wait(30)` inside a `Heartbeat` handler. Verify anything it claims with `rbx-docs-search` before writing it.

Its one forward-looking contribution worth keeping: **ProfileService** for Phase 13, over raw DataStore, for session locking and reconciliation.

## Conventions

- **Never name a module after a `game:GetService()` name.** This is why the run-state service is `RunSessionService`, not `RunService` — the latter shadows the real service wherever both are needed, and the resulting bug reads as correct code.
- **Never call `math.random`.** Use `Shared/Rng.luau`. A single bare `math.random` destroys seeded-run reproducibility and is nearly impossible to find afterwards. The pre-commit hook rejects it. The one sanctioned exception is `FloorService.rollSeed`, which draws the run seed itself from an unseeded `Random.new()` — everything downstream of the seed is then deterministic.
- **`Rng` sub-stream keys are delimited.** `Rng.new(seed, "encounter", depth, template)` folds a separator between parts, because without one `("k", 1, 23)` and `("k", 12, 3)` are the same stream. Do not "simplify" that away, and apply the same rule to anything that hashes fields.
- **Generation is pure.** `Shared/FloorPlan.luau` takes `(seed, depth, template)` and returns plain data. It never accepts a live `Rng` — that would make call order load-bearing, so reordering two lines elsewhere would silently change the world. Realization (`RoomService`) receives a plan; it never asks for one.
- **`FloorService.loadFloor` must never yield.** The floor slab ends exactly at the exit wall, so the exit trigger volume sits over void. Clear → build → pivot → teleport completing in one frame is the only thing stopping a player who just walked out from free-falling with the advance latch held.
- **`BindableEvent:Fire` is deferred, not synchronous.** This place runs Roblox's `Deferred` signal behaviour: a listener does not run until the next resumption point, so every observer in the project is one frame behind the thing it observes. Verified directly — fire a Bindable and read the flag on the next line and it is still `false`. Two consequences that bite: a spec must `task.wait()` after the action before asserting on a listener's side effects, and a listener may run *after* the state it wants has already moved on, so read the state you need rather than inferring it from the event's ordering.
- **Server authority, always.** Clients send intent (`RequestAttack`); they never report outcomes. Damage, gold, loot, purchases, and floor completion are computed server-side. Phase 17 audits this; it does not retrofit it.
- **Services are plural from day one.** State is keyed by player and functions take player lists, even while that list has one entry. Phase 14 tunes co-op scaling rather than rearchitecting.
- **Content is Lua data, not Studio-authored instances.** A room template is a ~20-line table, diffable one line at a time and parameterizable by seed. Exceptions: imported art referenced by ID from `Shared/Assets/AssetIds.luau`, and genuinely hand-sculpted set pieces as committed `.rbxmx`. If you edit a `.rbxmx` in a third phase, it should have been data.

## Service lifecycle

A service is a ModuleScript returning a table with optional `Init()` and `Start()`. Three rules:

1. **`Init` may not call other services.** So load order cannot cause a nil-reference.
2. **`Start` may not yield.** So boot is synchronous and the "everything booted" signal is trustworthy. A service needing a loop `task.spawn`s it itself inside `Start`.
3. Services reference each other by plain sibling `require` — no locator, no injection, full type inference.

**The dependency graph is one-way and must stay that way.** `ServerMain` requires every service at top level, so a top-level cycle is a hard boot error — circular requires are only safe when lazy (inside a function). Current DAG:

```
TrainingDummyService ──> CombatService ──> PlayerService
         └────────────> FloorService
```

**`PlayerService` requires no other service, ever.** It sits at the root. A service that needs to react to the character lifecycle connects its own `CharacterAdded`/`CharacterRemoving` and compares `PlayerService.generation(player)`; where `PlayerService` genuinely has to notify outward, it fires a `BindableEvent` (`onDied`, `onSpawned`) rather than calling anyone.

`ServerMain` requires from an explicit ordered list, not `:GetChildren()`: boot order is part of the contract, shows in diffs, and fails loudly on a typo. It sets `OMF_ServerReady` when done. Errors are deliberately uncaught — a crash leaves the attribute unset and produces a clean stack trace, failing both QA signals instead of hiding.

## Verification

Full loop in `docs/ARCHITECTURE.md`, automated by the `/playtest` skill. The short version:

```sh
stylua --check src tests && selene src tests && rojo build default.project.json -o "$SCRATCH/omf.rbxl"
```

then start play, poll `OMF_ServerReady`, run the spec suite, and sweep `LogService:GetLogHistory()` in **both** the Server and Client datamodels filtering on a timestamp captured before the run. **Pass = zero `MessageError` in both.**

### Two rules the QA loop breaks without

**1. Restart Play after every code change.** Rojo syncs into the **Edit** datamodel. A running Play session keeps the code it started with, so editing a file and re-running the suite silently re-tests the old code — and the check counts look plausible enough not to notice. Always `start_stop_play(false)` then `(true)` after a sync, and confirm the change landed by reading the module's `Source` in the Edit datamodel first.

**2. Run specs through `OMF_RunSpecs`, never by requiring `RunAll` directly.** `execute_luau` runs in its **own Lua VM with its own module cache**. A spec required from there gets fresh, un-booted copies of every service: `PlayerService.all()` comes back empty while the real one has players, and every module-state assertion fails for a reason that looks like a product bug. `ServerMain` publishes a `BindableFunction` at `ServerStorage.OMF_RunSpecs` whose callback was created in the boot context; it returns the result as a JSON string so it survives the VM boundary.

```lua
local raw = game.ServerStorage:WaitForChild("OMF_RunSpecs"):Invoke()
local result = game:GetService("HttpService"):JSONDecode(raw)
```

Specs that only read the DataModel (instances, attributes) pass either way — which is exactly why this is easy to miss until a spec touches service state.

**This applies to ad-hoc probing too, not just specs.** `require(ServerScriptService.Services.PlayerService)` typed straight into `execute_luau` returns a fresh, un-booted copy: `PlayerService.all()` comes back empty while the real service has players, and it reads exactly like a catastrophic state-loss bug. It is not. **When probing from `execute_luau`, read DataModel state — attributes, instances, properties — because those are shared across VMs.** If you genuinely need module state, go through `OMF_RunSpecs`.

**4. The suite runs against a live world, so quiesce it.** `RunAll` disables the practice skeleton for the duration and restores it afterwards. Before that existed, the practice skeleton wandered into the Phase 1 i-frame check and hit the player for exactly 14 — which reads as a combat bug rather than interference. **Any future world content that acts on its own belongs in that quiesce list.**

Related: `Humanoid:MoveTo` has no pathfinding, so a spec that places an enemy with scenery between it and the player will fail its chase assertion for the wrong reason. Phase 2's offsets run along +X specifically to avoid the training dummy.

**3a. A long-running `execute_luau` call can silently stall on the MCP bridge itself, independent of the code.** One `OMF_RunSpecs` run hung for 1899s and was killed by the tool's own idle timeout — no infinite loop, no Studio freeze; a rerun of the identical code completed normally in the expected ~70-80s. **Never invoke a suite run as one long blocking call.** Instead: `task.spawn` the `runner:Invoke()`, stash the result on `_G`, return immediately, then poll with short `execute_luau` calls a few seconds apart until `done` is true. This turns an indefinite stall into a bounded, diagnosable wait, and if it genuinely hangs you still have a live Studio to inspect instead of a dead 30-minute call.

**3. `default.project.json` changes need a `rojo serve` restart.** Rojo does not hot-reload the project file, so a newly added node never appears. Restarting drops the plugin connection and needs a manual Connect, so batch project-file changes rather than making them mid-session.

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
- `screen_capture` is edit-time oriented and takes no datamodel selector. **Confirmed: during Play it returns a blank magenta frame.** For visual evidence, stop play and capture in Edit with explicit camera coordinates — but note that anything built at runtime (the dummy, enemies) does not exist in Edit, so it cannot be photographed at all. Structured JSON from the spec suite is the real evidence.
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
