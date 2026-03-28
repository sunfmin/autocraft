---
name: refine-journey
description: Evaluate the output of a journey-builder run, identify instruction gaps, and edit the project root AGENTS.md (or add pitfalls to the gist) to fix those gaps. Does NOT modify the journey-builder skill itself.
argument-hint: [spec-file-path]
context: fork
agent: general-purpose
---

You are a refinement engineer. Your job is to improve the project root `AGENTS.md` (project-specific overrides for the journey-builder skill) and the pitfalls gist (platform-specific patterns) by learning from journey-builder failures. You evaluate what was produced, diagnose which instructions were weak or missing, and write fixes to `AGENTS.md` or the gist.

**Your goal is not to fix the product or the journey-builder skill itself — it is to fix the project-level overrides and pitfalls that guide the skill.**

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
5. **`AGENTS.md`** (at repo root, if it exists) — read the current project-specific instructions

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
- **timeout > 5s without a comment** → flag as skill failure (missing justification)
- **timeout > 5s without a progress-screenshot loop** → flag (viewer sees frozen screen)
- **Consecutive screenshots with > 5s gap** (visible in `T00m00s_` filename timestamps) → flag the step pair and investigate why

Use the timestamped screenshot filenames (`T{mm}m{ss}s_...`) to spot long gaps. If two consecutive screenshots are > 5s apart and the test code has no comment explaining the delay, it must be fixed.

### 2e. Journey Quality Check
For the most recent journey:
- Does `journey.md` describe a realistic user path from start to finish?
- Does the test actually complete the FULL user action and verify its outcome? (A recording test must produce a recording. A search test must find results. A test that stops at "button exists" is incomplete.)
- Were all 3 polish rounds completed? Check for `testability_review_round{1,2,3}*.md` and `ui_review_round{1,2,3}*.md`
- Did each round produce NEW timestamped files (not overwritten)?

### 2f. Spec Coverage Check (per-criterion)

Read `spec.md` in full. For every requirement and for EVERY one of its acceptance criteria:

**Step 1 — Map each criterion to a journey:**
Search every `journeys/*/journey.md` Spec Coverage section. A criterion is "mapped" only if it appears by number in a journey's Spec Coverage. A requirement having a journey does NOT mean all its criteria are mapped — check the criterion count in `spec.md` vs. the count listed in the journey.

**Step 2 — Verify implementation evidence:**
For each mapped criterion: (1) does the test code contain a step exercising this criterion (search the test file for keywords from the criterion text), and (2) does a screenshot file exist in `screenshots/` that corresponds to that step?

**Step 3 — Build the per-criterion coverage table:**
```
| Req ID | Requirement | Crit # | Summary | Journey | Mapped? | Test Step? | Screenshot? | Status |
|--------|-------------|--------|---------|---------|---------|------------|-------------|--------|
| P0-0   | First Launch | 1 | Consent dialog | 001-... | YES | YES | YES | COVERED |
| P0-2   | Window Picker | 3 | ... | none | NO | NO | NO | UNCOVERED |
```

**Step 4 — List every criterion with status UNCOVERED or MISSING SCREENSHOT. These MUST be addressed before the loop stops.**

### 2f.5. Journey Status Correction (MANDATORY if gaps found in 2f)

If Phase 2f found any criterion with status UNCOVERED or MISSING SCREENSHOT for a journey whose current status in `journey-state.md` is `polished`, the refiner MUST:

1. Change that journey's status in `journey-state.md` from `polished` to `needs-extension`
2. Append to `journey-refinement-log.md` under the current run's section:
   ```
   ### Status Corrections
   - Journey `{NNN}-{name}`: downgraded `polished` → `needs-extension`
     Reason: criteria [P0-2 #3, P0-2 #4] mapped but no screenshot evidence
   ```

A journey MUST NOT remain `polished` when any of its mapped criteria lack screenshot evidence.

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
Criteria Coverage:   X / M acceptance criteria fully covered (impl+test+screenshot) (weight: 35%)
Tests:               X / N tests passing                   (weight: 15%)
Build:               passing / failing                     (weight: 10%)
Screenshot Quality:  X / N screenshots pass design check   (weight: 15%)
Real Outcomes:       X / N journey tests reach real outcome (weight: 15%)
Polish Completeness: X / 3 rounds fully completed          (weight: 5%)
Step Coverage:       X / N journey steps have screenshots   (weight: 5%)
Test Speed:          Xs total (informational only — not scored; flag if > 120s)

Overall Score: XX%
```

**Criteria Coverage scoring:**
- M = total acceptance criteria across ALL requirements in `spec.md`
- X = criteria that have: (1) a journey mapping them by number, (2) a test step exercising them (keywords from criterion text appear in test code), AND (3) a screenshot proving the outcome
- Partial (mapped but no screenshot, or mapped + screenshot but test step missing) counts as 0
- At 35% weight, <90% criterion coverage makes reaching 95% total score mathematically impossible — this is intentional

Write this score to `journey-refinement-log.md` (create if missing), with timestamp and findings summary.

---

## Phase 4: Diagnose Skill Instruction Failures

For each gap found in Phase 2, ask: **"what instruction was missing, unclear, or too weak to prevent this?"**

Apply 5 Whys to trace back to the skill instruction:

```
Failure: <what the journey-builder agent failed to do>

Why 1: Why did it fail to do this?
Why 2: Why did the agent behave that way?
Why 3: Why was it instructed that way?
Why 4: Why does the skill text say that (or not say that)?
Why 5: Why does that gap exist in the skill?

Instruction Gap: <what's missing — in AGENTS.md or pitfalls gist>
Fix: <specific new or revised instruction to add>
Target: <AGENTS.md if project-specific, pitfalls gist if platform-specific>
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

## Phase 5: Write Fixes to the Right Place

For each diagnosed instruction gap, decide WHERE the fix belongs:

**Platform-specific patterns** (SwiftUI, XCUITest, xcodegen, codesign, Playwright, etc.) → **Add a pitfall to the gist.** These are reusable across all projects.
```bash
gh gist edit 84a5c108d5742c850704a5088a3f4cbf -a <category>-<short-name>.md
```

**Project-specific rules** (this app's architecture decisions, known violations, app-specific workflows) → **Edit `AGENTS.md` at the project root** (create if missing).

Rules for editing AGENTS.md:
- **Surgical edits** — change the specific weak section, don't rewrite everything
- **Concrete over abstract** — replace "verify it works" with exact commands and expected output
- **Must not should** — change optional-sounding language to mandatory
- **Add examples** — when a rule is abstract, add a concrete right-vs-wrong example

**Anti-bloat rule:**
- Every sentence must cause the agent to DO something. Cut concept descriptions.
- Prefer sharpening an existing rule over adding a new one.
- After edits, count total lines. If net growth > 20 lines, find something to cut.
- No duplicate rules across sections — merge them.

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

### Changes Made to AGENTS.md / Pitfalls
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
- What was changed in AGENTS.md or added to pitfalls gist
- Exact command to run next: `/journey-builder`
- What to watch for in the next run
