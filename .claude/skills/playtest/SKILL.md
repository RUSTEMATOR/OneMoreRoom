---
name: playtest
description: Run the full MCP QA loop against Roblox Studio — static gate, sync verification, play, spec suite, and a zero-error log sweep in both datamodels. Use after every phase, or whenever asked to verify, playtest, or QA a change in this project.
---

# Playtest

The project's verification loop. Argument (optional): the acceptance criteria for this phase. Steps 1–3 are cheap and catch most failures without touching Studio — never skip them to save time.

Resolve the Studio id with `list_roblox_studios` first. Never hardcode it; it changes whenever Studio restarts.

## 1. Static gate

```sh
export PATH="$HOME/.rokit/bin:$PATH"
cd ~/Desktop/one-more-floor
stylua --check src tests && selene src tests && rojo build default.project.json -o /tmp/omf-check.rbxl
```

All three must exit 0. Stop on failure — a syntax error makes every later step meaningless.

## 2. Sync gate (blocking)

`curl -sS localhost:34872/api/rojo` proves Rojo is *serving*. That is not the same as the plugin being *connected*, and the gap is the main way a session silently diverges.

Read the build stamp out of the live place with `execute_luau`, `datamodel_type: "Edit"`:

```lua
local shared = game.ReplicatedStorage:FindFirstChild("Shared")
local stamp = shared and shared:FindFirstChild("BuildStamp")
return { present = stamp ~= nil, source = stamp and stamp.Source or nil }
```

If the source does not contain the id currently in `src/Shared/BuildStamp.luau`, **stop and ask the user to click Plugins → Rojo → Connect.** Do not attempt to fix it from the Studio side.

## 3. Timestamp baseline

`execute_luau`, `Edit`: `return { t0 = os.time() }`. There is no tool to clear the console, so time-filtering is the substitute. Carry `t0` into step 6.

## 4. Start play

`start_stop_play(is_start: true)`, then poll `get_studio_state` until the available datamodels include `Server` and `Client`.

## 5. Wait for boot

`execute_luau`, `Server`, up to ~10 polls:

```lua
return { ready = game:GetAttribute("OMF_ServerReady") == true }
```

Do not use `wait_job_finished` — it needs a `jobId` from an `async: true` call, which no tool here exposes.

## 6. Run the suite and sweep logs

`execute_luau`, `Server`:

```lua
return require(game:GetService("ServerStorage").Specs.RunAll)()
```

Then the log sweep, run in **`Server` and again in `Client`** — they have separate `LogService`s. Substitute the real `t0`:

```lua
local LogService = game:GetService("LogService")
local SINCE = <t0>
local errors, warnings = {}, {}
for _, entry in LogService:GetLogHistory() do
	if entry.timestamp >= SINCE then
		if entry.messageType == Enum.MessageType.MessageError then
			table.insert(errors, entry.message)
		elseif entry.messageType == Enum.MessageType.MessageWarning then
			table.insert(warnings, entry.message)
		end
	end
end
return { errorCount = #errors, warningCount = #warnings, errors = errors, warnings = warnings }
```

**Pass = `allPassed == true` and `errorCount == 0` in both datamodels.** Warnings do not fail the phase but must be recorded in the ledger.

## 7. Interaction, if the phase needs it

`character_navigation` and `user_keyboard_input` are **Client-datamodel only** and need play mode, which is why they come after step 4. Re-run step 6 afterwards to catch anything the interaction broke.

## 8. Stop and report

`start_stop_play(is_start: false)`, then one `get_console_output` for a human-readable tail.

Report: the structured JSON from step 6 (that is the evidence), pass/fail against the acceptance criteria, and any warnings for the ledger. If anything failed, add it to Known bugs in `docs/PROGRESS.md` with a repro seed where one applies.
