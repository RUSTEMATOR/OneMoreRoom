---
name: repro
description: Reproduce a One More Room bug from its run seed — launch a run pinned to that seed and drive to the failing floor. Use when investigating a bug from the ledger or any report that carries a seed.
---

# Repro

Arguments: `<seed> <path>` — for example `839271 1,2,1`. Both halves are required.

**Why the path matters.** Generation is deterministic, but which door the player took is an *input* to the run, not an output of the seed. A seed alone reproduces the same *tree* of possible rooms; seed plus path reproduces the exact rooms they actually saw. `RunSessionService.describe()` prints both in the form a report should carry, and the HUD shows the seed live.

1. **Run `/playtest` steps 1–5** to get a clean, verified-synced play session. Do not skip the sync gate: reproducing against stale code wastes the whole investigation.

2. **Start the run on that seed.** Remember that `execute_luau` has its own Lua VM, so this has to go through the boot context — drive it from a spec or the `OMF_RunSpecs` seam, not a bare `require`.
   ```lua
   FloorService.beginRun(<seed>)
   ```

3. **Replay the path** by calling `FloorService.advance(index)` once per recorded choice, rather than playing manually — it is faster and does not depend on combat outcomes.

4. **Confirm determinism before trusting the repro.** Compare `FloorPlan.fingerprint(seed, 8)` against the golden constant in `tests/specs/Phase06_Generation.luau`. If it differs, the bug is a determinism break — a far more serious finding — and something is calling `math.random`, reading unkeyed state, or iterating a hash table. Chase that first.

5. **Observe the failure**, then use `rbx-debug` for breakpoints and thread state rather than adding print statements.

6. **Record** in `docs/PROGRESS.md` under Known bugs: the seed, the path, the floor, what was expected, what happened. A bug without a seed and path in this project is a bug report that cannot be closed with confidence.
