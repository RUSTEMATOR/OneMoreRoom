---
name: phase-done
description: Close out a One More Room phase — verify, update the progress ledger and bug list, sync the build tracker artifact, and commit. Use when a phase's work is finished.
---

# Phase done

1. **Add this phase's spec.** Write `tests/specs/PhaseNN_<name>.luau` asserting the phase's acceptance criteria, and append its name to the `SPECS` list in `tests/specs/RunAll.luau`. Every later phase then re-runs it for free — that is the regression check.

2. **Run `/playtest`** with this phase's acceptance criteria. It must come back with `allPassed == true` and zero errors in both the Server and Client datamodels. Do not proceed on a partial pass.

3. **Update `docs/PROGRESS.md`** — move the phase into Completed, set the new Current milestone, record any Known bugs (with a repro seed where one applies), and rewrite Next.

4. **Sync the build tracker artifact.** One direction only: `PROGRESS.md` → `ArtifactData` rows. Update the `phases` row for this phase, add any new `bugs` rows, and add a `playtests` row with the seed and result. Never read artifact state back into the repo.

5. **Commit.** The pre-commit hook runs stylua, selene, and the `math.random` guard. If it fails, fix the cause — never `--no-verify`.

   ```
   Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
   ```

6. **Report** in two or three sentences: what landed, what the playtest showed, and what the next phase is.

If the phase hit one of the roadmap's hard gates — Phase 1 (does swinging a sword feel good?) or Phase 3 (is the vertical slice fun?) — say so explicitly and ask before continuing.
