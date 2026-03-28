---
name: journey-loop
description: Orchestrates a continuous journey-builder → refine → restart loop. Runs journey-builder and refine-journey sequentially, improving the skill each iteration. Loops until all spec requirements are covered by journeys and the score reaches 95%.
argument-hint: [spec-file-path]
context: fork
agent: general-purpose
---

You are the orchestrator of a self-improving build loop. You manage two sequential phases per iteration:

- **Builder** — runs the journey-builder skill to build and test the next user journey
- **Refiner** — runs the refine-journey skill to evaluate output and improve the skill

Your job is to keep this loop running, read their outputs, and decide when to restart, continue, or stop.

## Inputs

Spec file: $ARGUMENTS

If no argument given, use `spec.md` in the current directory.

---

## Shared State Files

| File | Written by | Read by |
|------|-----------|---------|
| `journeys/*/` | Builder | Refiner, Orchestrator |
| `journey-refinement-log.md` | Refiner | Orchestrator |
| `SKILL.md` (repo root) | Refiner | Builder (each restart) |
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
| # | Journey Built | Duration | Score | SKILL.md Changes | Decision |
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

### Step 1: Read Current SKILL.md + Journey State

Before each iteration, read the root `SKILL.md` fresh. The refiner may have changed it.

Also read `journey-state.md` to determine what to work on:
- If any journey has status `in-progress` or `needs-extension` → builder must work on THAT journey (extend and polish it)
- If a journey claims `polished` but its `Test Duration` is blank, `unknown`, or contains `~` (estimated) → treat it as `needs-extension`. **The duration column MUST contain the actual measured wall-clock time from a passing `xcodebuild test` run** (e.g., `12m30s`). Estimated values like `~5m` are NOT valid.
- If a journey has `polished` status but duration < 10 minutes → treat it as `needs-extension`. **10 minutes is a hard limit — no exceptions.**
- Only when ALL journeys have `polished` status with verified real durations >= 10 minutes → builder picks the next uncovered path from the spec

**The builder always starts with the first unfinished journey.** It does not skip ahead. A journey is "unfinished" if ANY of: status is not `polished`, duration is missing/estimated/contains `~`, or duration < 10 minutes.

### Step 2: Launch Builder Agent

Spawn a new Agent with:
1. The full content of `SKILL.md` as instructions
2. The full content of all pitfall files from the gist
3. The current `journey-state.md` content
4. Clear directive: work on the first unfinished journey, or extend it to 10+ minutes

The builder will:
- Load pitfalls (Step 0 of builder)
- Check journey state
- Extend existing journey OR create new one
- Write/extend the test to fill 10+ minutes
- Run 3 polish rounds
- Update `journey-state.md`
- Commit

Wait for the builder to complete.

### Step 3: Launch Refiner Agent

After the builder completes, spawn a new Agent with the full content of the refine-journey SKILL.md as the task prompt, substituting the spec path.

Wait for the refiner to complete. It will:
- Evaluate the builder's output
- Write a score to `journey-refinement-log.md`
- Edit `SKILL.md` with improvements

### Step 4: Read the Score + Journey State

Read `journey-refinement-log.md`. Extract from the most recent entry:
- `Score:` — the percentage
- `Failures Found:` — list of failures
- `Changes Made to SKILL.md:` — what was changed

Read `journey-state.md` to check:
- Is the current journey `polished` with a real measured duration >= 10m AND all tests pass?
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
- Every journey in `journey-state.md` has status `polished` with duration >= 10 minutes
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

- **Max iterations:** 10. If not at 95% after 10, stop and report current state with top remaining failures.
- **Stall detection:** If the builder produces no changes for 2 consecutive iterations, log the stall and proceed to the refiner — it can diagnose why the builder stalled.
- **Never modify the spec** — the spec is read-only. Only `SKILL.md` gets improved.
- **Pitfall gist is append-only** — add new pitfalls, never delete existing ones.
