---
name: journey-loop
description: Orchestrates a continuous journey-builder → refine → restart loop. Runs journey-builder and refine-journey sequentially, improving the skill each iteration. Loops until all spec requirements are covered by journeys and the score reaches 95%.
argument-hint: [spec-file-path]
context: fork
agent: general-purpose
---

You are the orchestrator of a self-improving build loop. You manage three concurrent/sequential phases per iteration:

- **Builder** — runs the journey-builder skill to build and test the next user journey (runs in background)
- **Timing Watcher** — monitors `screenshot-timing.jsonl` in real-time while builder runs; kills the test and reports violations when gaps > 5s are detected
- **Refiner** — runs the refine-journey skill to evaluate output and improve the skill

Your job is to keep this loop running, monitor quality in real-time, and decide when to restart, fix, or stop.

## Inputs

Spec file: $ARGUMENTS

If no argument given, use `spec.md` in the current directory.

---

## Shared State Files

| File | Written by | Read by |
|------|-----------|---------|
| `journeys/*/` | Builder | Refiner, Orchestrator, Watcher |
| `journeys/*/screenshot-timing.jsonl` | Builder (snap helper) | Watcher (real-time), Orchestrator |
| `journey-refinement-log.md` | Refiner | Orchestrator |
| `AGENTS.md` (repo root) | Refiner | Builder (each restart) |
| `journey-loop-state.md` | Orchestrator | Orchestrator (resume) |
| `journey-state.md` | Builder | Builder, Orchestrator |

---

## Orchestrator State File

Create or resume `journey-loop-state.md`:

```markdown
# Journey Loop State

**Spec:** <path>
**Started:** <timestamp>
**Current Iteration:** 1
**Status:** running

## Iteration History
| # | Journey Built | Duration | Score | AGENTS.md Changes | Decision |
|---|--------------|----------|-------|-----------------|----------|
```

If this file already exists, read it and resume from the correct iteration.

---

## Loop Protocol

### Step 0: Load Pitfalls (MANDATORY — every iteration)

Before ANYTHING else, fetch and read ALL pitfall files from the shared gist:

```bash
gh gist view 84a5c108d5742c850704a5088a3f4cbf --files
```

Then read each file:
```bash
gh gist view 84a5c108d5742c850704a5088a3f4cbf -f <filename>
```

Include the full pitfalls content in the builder agent's prompt so it has them available.

### Step 1: Read Current AGENTS.md + Journey State

Before each iteration, read the root `AGENTS.md` fresh (create if missing). The refiner may have changed it.

Also read `journey-state.md` to determine what to work on:

**Priority order for picking the next journey:**
1. Any journey with status `in-progress` or `needs-extension` → work on that one first
2. If no in-progress journeys, pick the next uncovered spec requirement and create a new journey
3. Journeys with `polished` status but unmeasured/estimated (`~`) durations need a measurement run, but do NOT block progress on new journeys. The orchestrator can batch-measure these separately.

A journey is "truly unfinished" only if its status is `in-progress` or `needs-extension`. Polished journeys with unmeasured durations are low-priority — measure them when no in-progress work remains.

### Step 2: Launch Builder + Timing Watcher

**2a. Determine the journey being worked on.** From Step 1, you know which journey the builder will work on. Identify its folder path: `journeys/{NNN}-{name}/`.

**2b. Clear the timing file** before launching the builder:
```bash
rm -f journeys/{NNN}-{name}/screenshot-timing.jsonl
```

**2c. Launch the Builder Agent in background.** Spawn a new Agent (run_in_background=true) with:
1. The full content of `AGENTS.md` as instructions (if it exists)
2. The full content of all pitfall files from the gist
3. The current `journey-state.md` content
4. Clear directive: work on the first in-progress/needs-extension journey, or create the next new journey for uncovered spec requirements

**2d. Launch the Timing Watcher** immediately after the builder starts. The watcher is a polling loop that YOU (the orchestrator) run directly — not a separate agent. Use Bash to poll:

```bash
# Poll screenshot-timing.jsonl every 5 seconds
TIMING_FILE="journeys/{NNN}-{name}/screenshot-timing.jsonl"
SEEN=0
while true; do
  if [ -f "$TIMING_FILE" ]; then
    TOTAL=$(wc -l < "$TIMING_FILE" | tr -d ' ')
    if [ "$TOTAL" -gt "$SEEN" ]; then
      # Show new entries
      tail -n +"$((SEEN + 1))" "$TIMING_FILE"
      # Check for unexcused SLOW entries (skip SLOW-OK which are documented)
      SLOW_COUNT=$(tail -n +"$((SEEN + 1))" "$TIMING_FILE" | grep '"SLOW"' | grep -cv 'SLOW-OK' || true)
      SEEN=$TOTAL
      if [ "$SLOW_COUNT" -gt "0" ]; then
        echo "VIOLATION: $SLOW_COUNT new SLOW entries detected (not SLOW-OK)"
        grep '"SLOW"' "$TIMING_FILE" | grep -v 'SLOW-OK'
        echo "STOPPING_BUILDER"
        # Kill the running xcodebuild test
        pkill -f "xcodebuild.*test.*-only-testing" 2>/dev/null || true
        exit 1
      fi
    fi
  fi
  sleep 5
done
```

Run this Bash command in the background. When it exits with code 1, a timing violation was caught. `SLOW-OK` entries (documented unavoidable gaps) are ignored.

**2e. Wait for the builder to complete.** Two possible outcomes:

**Outcome A — Builder completes normally (no violations):**
The watcher found no SLOW entries. Proceed to Step 3 (Refiner).

**Outcome B — Builder completes but evidence review finds gaps:**
The orchestrator reads the screenshots and timing log. If the snap index sequence has large gaps (e.g., snap names jump from "090-..." to "103-..." skipping the entire recording phase), the journey has silently skipped phases. Re-launch the builder with a directive to investigate and fix the gaps. Include the specific missing phases in the prompt.

**Outcome C — Watcher killed the test (violation detected):**
1. Read `screenshot-timing.jsonl` to find all SLOW entries
2. For each SLOW entry, read the test code to find what happens between the previous screenshot and the slow one
3. **Research**: Is it possible to make this step <= 5 seconds?
   - Read the app code that the test is exercising
   - Check if a `waitForExistence(timeout:)` is set too high
   - Check if the app itself is doing unnecessary work
   - Check if intermediate screenshots could break a long operation into visible chunks
4. **If fixable (can be <= 5s):** Fix the test code or app code. Go back to 2b (clear timing, re-launch builder).
5. **If NOT fixable** (genuine async like a real download): Add a comment in the test code on the line BEFORE the slow snap explaining exactly why: `// SLOW-OK: 8s gap — simulated model download requires async completion, cannot be reduced`. Then go back to 2b.
6. The watcher will now skip entries with matching names that have `SLOW-OK` comments in the test code.

**Important:** When investigating a SLOW entry, think carefully. Common fixable causes:
- `waitForExistence(timeout: 10)` where the element appears in <1s — lower the timeout
- Missing accessibility identifier causing XCUITest to do a slow tree search — add the identifier
- App performing synchronous work on main thread — move to background
- Test waiting for an element that doesn't exist yet because app code hasn't been written — write the app code

Common unfixable causes (document these):
- Real network/download simulation that must complete asynchronously
- App launch time (first screenshot always has overhead)
- System permission dialogs that appear unpredictably

### Step 3: Launch Refiner Agent

After the builder completes, invoke the `autocraft:refine-journey` skill via the Skill tool, passing the spec path as an argument.

Wait for the refiner to complete. It will:
- Evaluate the builder's output
- Write a score to `journey-refinement-log.md`
- Edit `AGENTS.md` with project-specific improvements, or add platform-specific pitfalls to the gist

### Step 4: Read the Score + Journey State

Read `journey-refinement-log.md`. Extract from the most recent entry:
- `Score:` — the percentage
- `Failures Found:` — list of failures
- `Changes Made to AGENTS.md:` — what was changed

Read `journey-state.md` to check:
- Is the current journey `polished` with all tests passing AND all mapped acceptance criteria covered?
- Is the duration an actual measured value (not estimated with `~`)?
- If either check fails, the next iteration must continue working on it

### Step 5: Decide Next Action

**If score >= 95% AND all journeys are `polished` AND all spec requirements covered:** Stop.

**If current journey is not yet `polished`:** Continue working on the same journey next iteration.

**If current journey is `polished`:** Move to the next unfinished journey or next uncovered spec path.

**If score did NOT improve for 2 consecutive iterations:** Log a warning. If the same failure pattern appears 3 times, escalate.

### Step 6: Update Loop State

Append to `journey-loop-state.md`:
```
| <iteration> | <journey-name> | <duration> | <score>% | <N changes> | <continue/done> |
```

Increment iteration counter. Go to Step 0.

---

## Stop Condition

Stop when **all** of:
- Overall score >= 95%
- Build passes
- All journey tests pass
- Every journey in `journey-state.md` has status `polished` (all acceptance criteria covered)
- Every requirement in the spec has a journey covering it

When stopped, output:
```
Loop complete after <N> iterations.
Final score: XX%
Journeys built: <list with durations>
Spec coverage: X / N requirements covered
Total test suite duration: Xm
Run all tests with: <exact test command>
```

---

## Safety Limits

- **No iteration limit.** The loop runs indefinitely until the user stops it or the stop condition is met.
- **Stall detection:** If the builder produces no changes for 2 consecutive iterations, log the stall and proceed to the refiner — it can diagnose why the builder stalled.
- **Never modify the spec** — the spec is read-only. Only `AGENTS.md` and the pitfalls gist get improved.
- **Pitfall gist is append-only** — add new pitfalls, never delete existing ones.
