---
name: phase-start
description: Begin a One More Floor development session — load project context, verify the Rojo/Studio connection, and pick up the current milestone. Use at the start of any session working on this project.
---

# Phase start

1. **Read** `CLAUDE.md`, `docs/ARCHITECTURE.md`, and `docs/PROGRESS.md`. The current milestone and the Next list in `PROGRESS.md` say what to do; do not redo anything under Completed.

2. **Resolve the Studio id** with `list_roblox_studios`. Never reuse one from an earlier session.

3. **Start Rojo** if it is not already serving:
   ```sh
   export PATH="$HOME/.rokit/bin:$PATH"
   cd ~/Desktop/one-more-floor
   curl -sS localhost:34872/api/rojo || rojo serve   # run in background if not up
   ```

4. **Bump the build stamp** in `src/Shared/BuildStamp.luau` to `<phase>-<date>`, then run the sync gate from `/playtest` step 2. If the live source does not match, stop and ask the user to click **Plugins → Rojo → Connect**. Never work around it Studio-side.

5. **Check the tree matches expectations** with `rbx-scene-analysis` or a scoped `search_game_tree` before assuming place structure.

6. **State the plan** for this phase in one or two sentences, including its acceptance criteria, before writing code.

Reminders worth re-reading if it has been a while: scripts live on disk only, `multi_edit` is banned, `execute_luau` is read-and-assert only, and nothing calls `math.random`.
