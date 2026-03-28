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
| # | Journey Built | Score | SKILL.md Changes | Decision |
|---|--------------|-------|-----------------|----------|
```

If this file already exists, read it and resume from the correct iteration.

---

## Loop Protocol

### Step 1: Read Current SKILL.md

Before each iteration, read the root `SKILL.md` fresh. The refiner may have changed it.

### Step 2: Launch Builder Agent

Spawn a new Agent with the full content of `SKILL.md` as the task prompt. The builder will:
- Read the spec
- Pick the next uncovered journey
- Write the test
- Run 3 polish rounds
- Commit

Wait for the builder to complete. It's done when a new journey folder exists with `journey.md` and review files.

### Step 3: Launch Refiner Agent

After the builder completes, spawn a new Agent with the full content of `.claude/skills/refine-journey/SKILL.md` as the task prompt, substituting the spec path.

Wait for the refiner to complete. It will:
- Evaluate the builder's output
- Write a score to `journey-refinement-log.md`
- Edit `SKILL.md` with improvements

### Step 4: Read the Score

Read `journey-refinement-log.md`. Extract from the most recent entry:
- `Score:` — the percentage
- `Failures Found:` — list of failures
- `Changes Made to SKILL.md:` — what was changed

### Step 5: Decide Next Action

**If score >= 95% AND all spec requirements have journeys:** Stop — the product is done.

**If score improved from last iteration:** Continue to next journey (builder picks the next uncovered path).

**If score did NOT improve for 2 consecutive iterations:** The builder should still continue to the next journey (each journey is independent), but log a warning. If the same failure pattern appears 3 times, escalate — the fix was insufficient and needs a deeper structural change to SKILL.md.

### Step 6: Update Loop State

Append to `journey-loop-state.md`:
```
| <iteration> | <journey-name> | <score>% | <N changes> | <continue/done> |
```

Increment iteration counter. Go to Step 1.

---

## Stop Condition

Stop when **all** of:
- Overall score >= 95%
- Build passes
- All journey tests pass
- Every requirement in the spec has a journey covering it

When stopped, output:
```
Loop complete after <N> iterations.
Final score: XX%
Journeys built: <list>
Spec coverage: X / N requirements covered
Run all tests with: <exact test command>
```

---

## Safety Limits

- **Max iterations:** 10. If not at 95% after 10, stop and report current state with top remaining failures.
- **Stall detection:** If the builder produces no new journey folder, log the stall and proceed to the refiner — it can diagnose why the builder stalled.
- **Never modify the spec** — the spec is read-only. Only `SKILL.md` gets improved.
