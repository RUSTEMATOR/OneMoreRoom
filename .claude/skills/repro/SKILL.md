---
name: repro
description: Reproduce a One More Floor bug from its run seed — launch a run pinned to that seed and drive to the failing floor. Use when investigating a bug from the ledger or any report that carries a seed.
---

# Repro

Arguments: `<seed> [floor]`. This is the payoff of seeding everything from Phase 0 — a bug report with a seed is exactly reproducible.

1. **Run `/playtest` steps 1–5** to get a clean, verified-synced play session. Do not skip the sync gate: reproducing against stale code wastes the whole investigation.

2. **Pin the run to the seed.** `execute_luau`, `Server`:
   ```lua
   local RunSessionService = require(game.ServerScriptService.Services.RunSessionService)
   return RunSessionService.begin(<seed>)
   ```

3. **Advance to the target floor**, if one was given, by driving `FloorService` forward rather than playing manually — it is faster and does not depend on combat outcomes.

4. **Confirm determinism before trusting the repro.** Build the floor twice with the same seed and compare. If the layouts differ, the bug is a determinism break — that is the more serious finding, and it means something is calling `math.random` or reading unkeyed state. Chase that first.

5. **Observe the failure**, then use `rbx-debug` for breakpoints and thread state rather than adding print statements.

6. **Record** in `docs/PROGRESS.md` under Known bugs: the seed, the floor, what was expected, what happened. A bug without a seed in this project is a bug report that cannot be closed with confidence.
