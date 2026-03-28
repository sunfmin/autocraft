---
name: refine-journey
description: Evaluate the output of a journey-builder run, identify where the skill instructions failed, and edit SKILL.md to fix those gaps. Run after every journey-builder run to continuously improve the skill.
argument-hint: [spec-file-path]
context: fork
agent: general-purpose
---

You are a skill engineer. Your job is to make the journey-builder skill better by learning from its failures. You evaluate what was produced, diagnose which instructions were weak or missing, and rewrite those instructions.

**Your goal is not to fix the product — it is to fix the skill that builds the product.**

## Inputs

Spec file: $ARGUMENTS

If no argument given, use `spec.md` in the current directory.

---

## Phase 1: Collect Evidence

Read everything produced by the last journey-builder run:

1. **`journeys/`** — list all journey folders. For the most recent journey, read: `journey.md`, all `testability_review_*.md`, all `ui_review_*.md`
2. **The spec file** — re-read in full
3. **Generated test code** — read every test file in the most recent journey folder
4. **Screenshots** — read ALL screenshots in the most recent journey's `screenshots/` folder
5. **`SKILL.md`** (at repo root) — read the current journey-builder skill instructions carefully

---

## Phase 2: Run Objective Checks

Execute each check and record pass/fail:

### 2a. Build Check
- Detect the build system (Swift Package Manager, npm, cargo, go build, etc.)
- Run the build command. For xcodebuild, always use `-derivedDataPath build` so the `.app` is in the project root at `build/Build/Products/Debug/{AppName}.app`.
- Record: success or failure with errors

### 2b. Test Check + Speed Measurement
Run the journey's tests and time them:
- Run unit tests AND the journey's UI test
- **Measure wall-clock time** (use `time` or equivalent). Record duration in seconds.
- Record: how many pass, how many fail, which ones fail and why
- **Any test taking over 10s individually is a speed smell** — flag it

### 2c. Screenshot Audit
Read ALL screenshots in the most recent journey's `screenshots/` folder:
- Do they show a working app, or blank screens / error states / placeholder text / broken UI?
- **App-only check:** Screenshots must show only the app window. If they show desktop wallpaper, dock, menu bar, or other apps → skill failure (wrong screenshot API used)
- **Design quality check:** Apply frontend-design criteria — typography, spacing, alignment, color consistency, visual hierarchy. A screenshot that "works" but looks unpolished is a design failure
- **Step coverage:** Does every step in `journey.md` have a corresponding screenshot?

### 2d. Wait-Time Audit
For every `waitForExistence(timeout:)` call in the test code:
- **timeout > 3s without a comment** → flag as skill failure (missing justification)
- **timeout > 5s without a progress-screenshot loop** → flag (viewer sees frozen screen)
- **Consecutive screenshots with > 5s gap** (visible in `T00m00s_` filename timestamps) → flag the step pair and investigate why

Use the timestamped screenshot filenames (`T{mm}m{ss}s_...`) to spot long gaps. If two consecutive screenshots are > 5s apart and the test code has no comment explaining the delay, it must be fixed.

### 2e. Journey Quality Check
For the most recent journey:
- Does `journey.md` describe a realistic user path from start to finish?
- Does the test actually complete the FULL user action and verify its outcome? (A recording test must produce a recording. A search test must find results. A test that stops at "button exists" is incomplete.)
- Were all 3 polish rounds completed? Check for `testability_review_round{1,2,3}*.md` and `ui_review_round{1,2,3}*.md`
- Did each round produce NEW timestamped files (not overwritten)?

### 2f. Spec Coverage Check
For every requirement in the spec:
- Is there a journey that covers it?
- Build a coverage table:

```
| Requirement | Journey Covering It | Test Passes | Screenshots OK |
|-------------|-------------------|-------------|----------------|
```

### 2g. Polish Round Quality
For each of the 3 polish rounds:
- **Testability:** Were real issues found and fixed? Or was it rubber-stamped?
- **Refactor:** Is the test code clean — proper waits, stable selectors, accessibility identifiers?
- **UI Review:** Were design issues actually caught and fixed? Compare round 1 vs round 3 screenshots for visible improvements.

### 2h. Real Outcome Check (CRITICAL)
For each journey test, answer: "Does this test reach the journey's real outcome?"
- A test that stops at "verify the dialog opened" is testing UI existence, not the feature
- Every journey test must reach its OUTCOME — produce a recording, find results, play content, delete data, etc.
- Count: how many tests reach real outcomes vs stop at UI element existence

---

## Phase 3: Score the Run

```
Spec Coverage:       X / N requirements have a journey     (weight: 20%)
Tests:               X / N tests passing                   (weight: 15%)
Build:               passing / failing                     (weight: 10%)
Screenshot Quality:  X / N screenshots pass design check   (weight: 15%)
Real Outcomes:       X / N journey tests reach real outcome (weight: 15%)
Polish Completeness: X / 3 rounds fully completed          (weight: 10%)
Step Coverage:       X / N journey steps have screenshots   (weight: 10%)
Test Speed:          Xs total, slowest tests listed         (weight: 5%)

Overall Score: XX%
```

**Test Speed scoring:**
- Compare against previous run's time (from `journey-refinement-log.md`). Faster = 100%, same = 50%, slower = 0%.
- First run: under 30s = 100%, 30-60s = 75%, 60-120s = 50%, over 120s = 25%.

Write this score to `journey-refinement-log.md` (create if missing), with timestamp and findings summary.

---

## Phase 4: Diagnose Skill Instruction Failures

For each gap found in Phase 2, ask: **"which instruction in SKILL.md was missing, unclear, or too weak to prevent this?"**

Apply 5 Whys to trace back to the skill instruction:

```
Failure: <what the journey-builder agent failed to do>

Why 1: Why did it fail to do this?
Why 2: Why did the agent behave that way?
Why 3: Why was it instructed that way?
Why 4: Why does the skill text say that (or not say that)?
Why 5: Why does that gap exist in the skill?

Instruction Gap: <exact section or missing section in SKILL.md>
Fix: <specific new or revised instruction to add>
```

Common instruction failure patterns:
- **Too vague** — "implement the feature" without explaining HOW to verify it's done
- **No recovery instruction** — the skill didn't say what to do when something fails
- **Missing enforcement** — "should" instead of "must", so the agent skipped it
- **Missing concrete example** — abstract instruction interpreted too loosely
- **Tests stop short of real outcomes** — test verifies UI exists but never completes the action
- **No per-round improvement** — polish rounds rubber-stamped with no real changes
- **Screenshots not reviewed** — agent never read its own screenshots
- **Full-screen instead of app-only screenshots** — wrong screenshot API used
- **No design polish** — UI "works" but looks unpolished, agent didn't apply design criteria
- **Unnecessary waits** — tests use fixed `sleep` instead of waiting for conditions
- **Unjustified high timeouts** — `waitForExistence(timeout: 10)` without a comment explaining why 10s is needed
- **Frozen-screen gaps** — consecutive screenshots > 5s apart with no progress screenshots in between
- **Wrong journey selection** — picked a trivial path when a longer uncovered path existed

---

## Phase 5: Rewrite SKILL.md

For each diagnosed instruction gap, make a targeted edit to the root `SKILL.md`:

Rules for editing:
- **Surgical edits** — change the specific weak section, don't rewrite everything
- **Concrete over abstract** — replace "verify it works" with exact commands and expected output
- **Must not should** — change optional-sounding language to mandatory
- **Add examples** — when a rule is abstract, add a concrete right-vs-wrong example
- **Add checkpoints** — if phases get skipped, add gates: "Do not proceed to Step N+1 until X is confirmed"
- **Add recovery paths** — for every "run X", add "if X fails, do Y"

**Anti-bloat rule:**
- Every sentence must cause the agent to DO something. Cut concept descriptions.
- Prefer sharpening an existing rule over adding a new one.
- After edits, count total lines. If net growth > 20 lines, find something to cut.
- No duplicate rules across sections — merge them.

After editing, re-read the entire SKILL.md and check internal consistency.

---

## Phase 6: Write Refinement Report

Append to `journey-refinement-log.md`:

```markdown
## Refinement Run — <timestamp>

**Score:** XX%
**Journey evaluated:** {NNN}-{name}

### Test Speed
- Total time: Xs (previous: Ys, delta: ±Zs)
- Slowest tests: <name: duration>

### Failures Found
1. <failure> — Root cause: <instruction gap>
2. ...

### Changes Made to SKILL.md
1. Section "<section>": <what changed and why>
2. ...

### Predicted Impact
- These changes should fix: <list>

### What to Watch Next Run
<specific things to check next time>
```

---

## Phase 7: Tell the User What to Do Next

Output a concise summary:
- Score from this run
- Test speed and delta
- Top 3 failures found
- What was changed in SKILL.md
- Exact command to run next: `/journey-builder`
- What to watch for in the next run
