---
name: autocraft
description: >
  Use when the user says "autocraft", "build journeys", "test the spec", or "cover my spec".
  Also use when the user has a spec.md and wants automated implementation with real output
  verification, or when building UI features that need screenshot-verified acceptance criteria.
argument-hint: "[spec-file-path]"
---

# Autocraft

Five agents. Strict roles. No self-grading. Human in the loop.

```
Human ◄──► Analyst (foreground agent)
               │
               ├──► spec.md (writes/updates)
               ├──► feedback-log.md (routes feedback)
               │
               ▼
           Orchestrator (you) ──► Builder (background agent)
                              ──► Tester (background agent)
                              ──► Inspector (foreground agent)
```

The **Analyst** talks to the human, collects feedback, writes and updates spec.md, and routes actionable feedback to the right agent. → [analyst.md](analyst.md)
The **Builder** implements features but CANNOT write tests, review its own work, grade itself, or commit. → [builder.md](builder.md)
The **Tester** writes journey tests but CANNOT modify production code. They only read it to understand what to test. → [tester.md](tester.md)
The **Inspector** verifies output with automated scans and subjective review. Only the Inspector can set "polished." → [inspector.md](inspector.md)
The **Orchestrator** manages handoffs and commits only when the Inspector approves. → below

**Why this separation matters:** A builder who writes their own tests optimizes for tests that pass — not for tests that prove features work. They know the button is wired up, so they assert it exists and move on. A separate tester doesn't know the internals. They read the spec, click the button, and check what happened. If nothing happened, they write a failing test — and the builder has to make it pass.

---

## When to Use

- Building a new app or feature set from a spec with multiple acceptance criteria
- You want automated, screenshot-verified proof that every criterion is met
- The project needs real implementations (not stubs) with independent test verification
- You have a `spec.md` (or gist) describing requirements and acceptance criteria

## When NOT to Use

- **Single-file bug fixes** — just fix the bug directly, autocraft is overkill
- **Pure refactoring** with no user-visible behavior change — no acceptance criteria to verify
- **Projects without UI** (CLI tools, libraries, APIs) — autocraft's screenshot verification assumes a GUI
- **Quick prototyping** where stubs are acceptable — autocraft enforces real implementations
- **No spec yet and you're not ready to write one** — start with the Analyst step or write spec.md first

---

## Inputs

Spec source: $ARGUMENTS (defaults to `spec.md` in current directory)

**Gist support:** If `$ARGUMENTS` is a GitHub gist URL or gist ID, the spec lives in the gist instead of a local file.

**Detection rules:**
- Starts with `https://gist.github.com/` → gist URL. Extract gist ID from the last path segment.
- Matches `/^[a-f0-9]{20,}$/` → bare gist ID.
- Otherwise → local file path.

```bash
# Read spec from gist
gh gist view <gist-id> -f spec.md

# Update spec in gist (Analyst only) — non-interactive
gh api --method PATCH /gists/<gist-id> \
  -f "files[spec.md][content]=$(cat /tmp/spec-updated.md)"

# If gist has no file named spec.md, list files first:
gh gist view <gist-id> --files
```

**Error handling:** If `gh gist view` fails, print the error, ask the user to verify the gist URL and run `gh auth status`, and do not proceed until the spec is readable.

The Orchestrator detects the source type at startup and stores it in `journey-loop-state.md` as `Spec source: gist:<gist-id>` or `Spec source: file:<path>`. All agents read the spec through a consistent method — the Orchestrator fetches the latest content and includes it in each agent's prompt. The Analyst writes spec updates to a temp file then pushes via `gh api`.

---

## Shared State Files

| File | Written by | Read by |
|------|-----------|---------|
| `journeys/*/` | Builder (code), Tester (tests+screenshots) | Inspector, Orchestrator |
| `journeys/*/test-contract.md` | **Orchestrator** | **Tester** (implements it), Inspector (validates against it) |
| `journeys/*/integration-test-contract.md` | **Orchestrator** | **Tester** (implements unit tests), Inspector (validates) |
| `journeys/*/screenshot-timing.jsonl` | Tester (snap helper) | Orchestrator (watcher) |
| `journey-state.md` | Tester (`needs-review`), Inspector (`polished`/`needs-extension`) | All |
| `journey-refinement-log.md` | Inspector | Orchestrator |
| `journey-loop-state.md` | Orchestrator | Orchestrator (resume) |
| `AGENTS.md` (repo root) | Inspector | Builder, Tester (each restart) |
| `feedback-log.md` | Analyst | Orchestrator, Builder, Tester, Inspector |

---

## Playbooks

Playbooks are shared, platform-specific knowledge bases stored as GitHub gists. Agents load the relevant playbook(s) at the start of every iteration.

Default registry gist: `bca7073d567ca8b7ba79ff4bad5fb2c5`. Override via `.autocraft` file at repo root. See [playbooks.md](playbooks.md) for full registry management, CRUD commands, entry format, and auto-fork behavior.

---

# Orchestrator Protocol (this agent)

You are the skeptical project manager. You don't write code. You don't review screenshots. You manage handoffs and ensure neither the Builder, Tester, nor Inspector cuts corners. You commit ONLY when the Inspector approves.

**Analyst integration:** Before starting the build loop, check if the Analyst has been invoked. If not, launch the Analyst first to confirm the spec with the human. During the loop, check `feedback-log.md` at every handoff point for new entries. Route feedback items to the appropriate agent as part of their next launch directive.

```dot
digraph orchestrator_loop {
    rankdir=TB;

    "Start" [shape=doublecircle];
    "Analyst confirmed spec?" [shape=diamond];
    "Launch Analyst" [shape=box];
    "Load playbooks" [shape=box];
    "Build criteria master list" [shape=box];
    "Pre-build simulation scan" [shape=box];
    "Launch Builder" [shape=box];
    "Generate test contract" [shape=box];
    "Integration tests needed?" [shape=diamond];
    "Generate integration contract" [shape=box];
    "Launch Tester" [shape=box];
    "Validate contract compliance" [shape=box];
    "Compliance passes?" [shape=diamond];
    "Launch Inspector" [shape=box];
    "Inspector verdict?" [shape=diamond];
    "Commit + next criteria" [shape=box];
    "All criteria covered?" [shape=diamond];
    "Done" [shape=doublecircle];
    "Route failures to agents" [shape=box];

    "Start" -> "Analyst confirmed spec?";
    "Analyst confirmed spec?" -> "Load playbooks" [label="yes"];
    "Analyst confirmed spec?" -> "Launch Analyst" [label="no"];
    "Launch Analyst" -> "Load playbooks";
    "Load playbooks" -> "Build criteria master list";
    "Build criteria master list" -> "Pre-build simulation scan";
    "Pre-build simulation scan" -> "Launch Builder";
    "Launch Builder" -> "Generate test contract";
    "Generate test contract" -> "Integration tests needed?";
    "Integration tests needed?" -> "Generate integration contract" [label="yes"];
    "Integration tests needed?" -> "Launch Tester" [label="no"];
    "Generate integration contract" -> "Launch Tester";
    "Launch Tester" -> "Validate contract compliance";
    "Validate contract compliance" -> "Compliance passes?";
    "Compliance passes?" -> "Launch Inspector" [label="yes"];
    "Compliance passes?" -> "Launch Tester" [label="no — re-launch"];
    "Launch Inspector" -> "Inspector verdict?";
    "Inspector verdict?" -> "Commit + next criteria" [label="polished"];
    "Inspector verdict?" -> "Route failures to agents" [label="needs-extension"];
    "Route failures to agents" -> "Launch Builder";
    "Commit + next criteria" -> "All criteria covered?";
    "All criteria covered?" -> "Done" [label="yes — score >= 95%"];
    "All criteria covered?" -> "Load playbooks" [label="no — next iteration"];
}
```

## Step 1: Launch Analyst (first iteration only)

If this is the first iteration and `spec.md` does not exist or the human has new input:
1. Launch the **Analyst** (foreground) with [analyst.md](analyst.md) contents and the human's request
2. The Analyst will gather requirements, write/update `spec.md`, and confirm with the human
3. Only proceed to Step 2 after the Analyst signals that the spec is confirmed

If the human provides feedback mid-loop, re-launch the Analyst to classify and route it (see Analyst Step 5). The Analyst writes to `feedback-log.md`; the Orchestrator picks up routed items at the next handoff.

## Step 2: Load Playbooks (every iteration)

Resolve the registry gist ID: read `.autocraft` from repo root if it exists, otherwise use default `bca7073d567ca8b7ba79ff4bad5fb2c5`. Fetch the registry, then for each registered playbook, fetch and read ALL files from its gist.

**Role-specific entries** (prefixed `role-{agent}-`) contain the platform-specific commands, code patterns, and templates that the corresponding agent needs. Include them in each agent's prompt alongside the pitfall entries.

**Template entries** (prefixed `template-`) contain base class code or boilerplate. The Builder and Tester copy these into the project as needed.

## Step 3: Build Acceptance Criteria Master List

Read the spec in full (local file or `gh gist view <gist-id> -f spec.md`). For every requirement, extract EVERY acceptance criterion. Write to `journey-loop-state.md`:

```markdown
# Journey Loop State

**Spec:** <path>
**Started:** <timestamp>
**Current Iteration:** 1
**Status:** running

## Acceptance Criteria Master List
Total requirements: N
Total acceptance criteria: M

| ID | Requirement | Criterion # | Criterion Text |
|----|-------------|-------------|----------------|
```

Read `journey-state.md` to determine what to work on:
1. Check `feedback-log.md` for **blocking** items — address these first
2. Any `in-progress` or `needs-extension` → work on that next
3. Check `feedback-log.md` for **important** items — incorporate into next agent launch
4. If none, pick next uncovered spec requirement

## Step 4: Pre-Build Simulation Scan

Before launching the Builder, scan for simulation infrastructure that bypasses real code paths. The playbook provides platform-specific scan commands (`role-orchestrator-{platform}.md`).

If any scan is not CLEAN: include in Builder's directive as **first priority to fix**.

## Step 5: Launch Builder Agent (background)

Spawn a background Agent with:
1. [builder.md](builder.md) contents
2. Full `AGENTS.md` content (if exists)
3. Full playbook contents (all registered playbooks)
4. Current `journey-state.md`
5. Directive: which journey to build/extend, plus any simulation fixes from Step 4
6. Any **Builder-routed feedback** from `feedback-log.md` (unresolved items where `Routed to: Builder`)

The Builder implements production features and creates the journey directory, but does NOT write test files.

Wait for Builder to complete.

## Step 6: Generate Test Contract (Orchestrator does this — NOT the Tester)

**This is the critical structural step.** The Orchestrator — not the Tester — defines what the test must prove. The Tester only implements it.

Using the spec's acceptance criteria AND the Builder's testability contract, generate a **test contract** and write it to `journeys/{NNN}-{name}/test-contract.md`:

```markdown
# Test Contract: Journey {NNN}

## State Machine
<!-- Order matters. Later phases depend on states established by earlier phases. -->
Phase 1: [initial state]
Phase 2: [state after action X] — depends on Phase 1
Phase 3: [state after action Y] — depends on Phase 2
...

## Criteria

### AC{N}: {criterion text from spec}
- PREREQUISITE: {state the app must be in — reference the Phase that establishes it}
- ACTION: {exact UI action — e.g., "click quickAction_Summarize"}
- ASSERT: {exact observable result — e.g., "terminalOutputArea contains 'Summarize'"}
- ASSERT_CONTAINS: {specific content that PROVES the action completed — e.g., "multi-line output", "contains 'Summary:'". NEVER just "changed" or "not empty"}
- ASSERT_TYPE: behavioral | state | existence
  <!-- behavioral = action produces the EXPECTED result (REQUIRED for action-verbs like "sends", "opens", "seeks")
       state = element property matches expected value (OK for "disabled when X")
       existence = element is present (ONLY OK for "visible" criteria) -->
- SCREENSHOT: {name}
- FAIL_IF_BLOCKED: "FAIL('Cannot test AC{N}: {prerequisite} not met — {what went wrong}')"
  <!-- The playbook maps FAIL to the platform's assertion failure macro (e.g., XCTFail for macOS/XCUITest) -->
```

**Rules for writing the contract:**
1. If the criterion's verb describes an **action** ("sends", "opens", "auto-cds", "seeks"), the ASSERT_TYPE MUST be `behavioral` — the test must verify an observable change, not just element existence
2. Every criterion with a prerequisite must reference the Phase that establishes it. If that Phase fails, the test must FAIL with the FAIL_IF_BLOCKED message
3. The Orchestrator must think adversarially: "If the Builder left the handler empty but kept the UI element, would this assertion catch it?" If not, strengthen the assertion.
4. Every `behavioral` criterion MUST have an ASSERT_CONTAINS that would FAIL if the action produced an error, a prompt, or any unintended intermediate state instead of the expected result. "Output changed" or "output is not empty" are NEVER sufficient for ASSERT_CONTAINS.

## Step 7: Analyze for Integration Tests & Refactor if Needed

After the Builder completes, the Orchestrator analyzes the new/modified code to decide if integration-level unit tests are needed. **Not every journey needs them.** UI tests cover user-visible behavior; integration tests cover "does the plumbing actually work."

### When to generate integration tests

Scan the Builder's code for **silent failure risks** — things that break without UI tests catching it:

- **External dependency** — C/FFI, vendored libs, model loading: links at build time but may crash/nil at runtime
- **Data pipeline with file I/O** — output file exists but contains garbage (wrong format, corrupted)
- **Multi-stage handoff** — A→B→C where the handoff silently drops data
- **Format conversion** — resampling, encoding, serialization where content is wrong but file looks valid

If none of these patterns are present (pure UI, layout, cosmetic), skip this step.

### Analysis process

1. **Read the Builder's new/modified files** in the Data and Domain layers
2. **Identify integration boundaries** — where does data cross between components? What could silently fail?
3. **Ask: "If I empty this function's body, would the UI test still pass?"** If yes → needs an integration test
4. **Check testability** — can the component be instantiated and called without launching the full app? If not, the Builder must **refactor** it to be testable (extract logic from UI, inject dependencies)

### Refactoring directive (when needed)

If a component can't be tested in isolation (e.g., business logic is tangled with UI, or a service is a singleton with no injection point), the Orchestrator sends the Builder back with a **refactoring directive**:

> "Refactor {Component} so it can be instantiated in a unit test without launching the app. Extract the core logic into a testable function/class that takes explicit inputs and returns explicit outputs."

The Builder refactors, the Orchestrator re-analyzes, then generates the test contract.

### Integration test contract

Write to `journeys/{NNN}-{name}/integration-test-contract.md`:

```markdown
# Integration Test Contract: Journey {NNN}

## Analysis
<!-- What was found in the code that needs integration testing -->
- Pipeline: {A → B → C}
- Silent failure risk: {what could break without UI tests catching it}
- Files involved: {list of source files}

## Tests

### IT{N}: {pipeline or integration being verified}
- SCOPE: {the full pipeline being tested — not a single method}
- SETUP: {test fixtures, temp directories, sample data files}
- ACTION: {instantiate the pipeline, feed known input, run to completion}
- ASSERT: {verify the output is correct — file exists AND content is valid}
- FAIL_MESSAGE: "{what's broken if this fails}"
```

**Rules:**
1. Test **pipelines**, not individual methods — each test should exercise a real data flow from input to output
2. Use real dependencies (real files, real libraries) — mocks hide the exact bugs these tests are meant to catch
3. Tests must be runnable without launching the app — use `@testable import` and direct instantiation
4. Fast: <30s per test. Use small test data (short audio clips, tiny models if possible, minimal files)
5. Each test must validate **output content**, not just **output existence** — a file existing but containing garbage is a failure
6. If a test needs a large resource (ML model, large file), check it exists first and fail with a clear message ("Model not found at path X — run setup first") rather than silently skipping

## Step 8: Launch Tester Agent (background)

After the test contracts are written, spawn a background Tester Agent with:
1. [tester.md](tester.md) contents
2. Full `AGENTS.md` content (if exists)
3. Full playbook contents (all registered playbooks)
4. The spec file path
5. **The UI test contract** (`journeys/{NNN}-{name}/test-contract.md`)
6. **The integration test contract** (`journeys/{NNN}-{name}/integration-test-contract.md`) if it exists
7. The Builder's report (accessibility identifiers, testability notes, integration boundaries)
8. Directive: implement and run integration tests first, then UI tests
9. If this is a re-launch after rejection: include the specific failure list with line numbers
10. Any **Tester-routed feedback** from `feedback-log.md` (unresolved items where `Routed to: Tester`)

**Also launch the Timing Watcher** — poll `screenshot-timing.jsonl` every 5s, kill test on unexcused SLOW entries:

```bash
TIMING_FILE="journeys/{NNN}-{name}/screenshot-timing.jsonl"
SEEN=0
while true; do
  if [ -f "$TIMING_FILE" ]; then
    TOTAL=$(wc -l < "$TIMING_FILE" | tr -d ' ')
    if [ "$TOTAL" -gt "$SEEN" ]; then
      tail -n +"$((SEEN + 1))" "$TIMING_FILE"
      SLOW_COUNT=$(tail -n +"$((SEEN + 1))" "$TIMING_FILE" | grep '"SLOW"' | grep -cv 'SLOW-OK' || true)
      SEEN=$TOTAL
      if [ "$SLOW_COUNT" -gt "0" ]; then
        echo "VIOLATION: $SLOW_COUNT SLOW entries"
        # Kill test process — platform-specific command from playbook (role-orchestrator-{platform}.md)
        exit 1
      fi
    fi
  fi
  sleep 5
done
```

Wait for Tester to complete.

## Step 9: Validate Contract Compliance (structural — before Inspector)

After the Tester finishes, validate the test file against the test contract. This is a **mechanical check** — not subjective review.

For each criterion in the contract:
1. **ACTION present?** — grep the test file for the action target (e.g., the element being clicked). If the contract specifies an action and the test file doesn't contain the corresponding interaction → FAIL
2. **ASSERT present?** — grep for the assertion. If the contract says `ASSERT_TYPE: behavioral` and the test only checks existence → FAIL
3. **No silent skips?** — grep for conditional guards that wrap contract assertions. Any match = the Tester made a mandatory assertion optional → FAIL
4. **FAIL_IF_BLOCKED present?** — for criteria with prerequisites, grep for the FAIL message from the contract. If missing, the Tester will silently skip blocked criteria → FAIL
5. **ASSERT_CONTAINS enforced?** — for every `behavioral` criterion, grep the test file for a content-matching assertion near the action. If the test only detects change without verifying expected content → FAIL

The playbook provides the platform-specific grep patterns and test file path conventions (`role-orchestrator-{platform}.md`). The Orchestrator constructs these checks dynamically from the contract.

If ANY check fails: **re-launch the Tester immediately** with the specific violations. Do NOT proceed to Inspector.

## Step 10: Launch Inspector Agent (foreground)

After Tester finishes, spawn an Inspector Agent with:
1. [inspector.md](inspector.md) contents
2. The spec file path
3. Directive: evaluate the most recent journey
4. If the `/frontend-design` skill is installed, invoke it and include its output in the Inspector's prompt for design principles during screenshot review (optional — skip if not available)

Wait for Inspector verdict.

## Step 11: Act on Inspector's Verdict

**If Inspector set `polished`:**
1. Commit all changes (journey files, screenshots, app code, updated journey-state.md)
2. Update `journey-loop-state.md` with iteration results
3. Move to next uncovered criteria

**If Inspector set `needs-extension`:**
1. Read Inspector's specific failure list from `journey-refinement-log.md`
2. DO NOT commit
3. Route each failure to the right agent:
   - Production code issue (feature doesn't work, stub, missing implementation) → re-launch **Builder**
   - Test issue (existence-only assertion, missing interaction, wrong verification) → **update the test contract** to strengthen the failing assertions, then re-launch **Tester** with the updated contract + Inspector's failure list
   - Both → re-launch Builder first, then update contract + re-launch Tester
   - Visual/UX issue (garbled rendering, incomplete flow, broken layout visible in screenshots) → re-launch **Builder** with the specific screenshot and failure description. The Builder must fix the root cause (e.g., use a proper rendering library, pre-configure interactive tools, handle prompts automatically).
4. When updating the contract after Inspector rejection:
   - For each failed criterion, tighten the ASSERT to make the failure structurally impossible (e.g., if the Tester used `.exists` where the contract said `behavioral`, add an explicit example assertion to the contract)
   - Add any missing FAIL_IF_BLOCKED messages the Inspector identified
5. Go back to Step 5 (or Step 6/8 depending on failure type)

## Step 12: Pre-Stop Audit (when score >= 90% or all journeys polished)

1. Read the Acceptance Criteria Master List (M rows)
2. For each criterion: confirm journey maps it + test step exists + screenshot exists
3. Build audit table with VERDICT column
4. If uncovered > 0: do NOT stop. Re-launch Builder for gaps.
5. Stop ONLY when: score >= 95% AND 0 uncovered AND all journeys `polished` by Inspector

## Stop Condition

ALL of:
- Inspector score >= 95%
- All journeys set to `polished` by Inspector (not by Builder)
- Pre-stop audit: 0 uncovered criteria
- All objective scans pass (no bypass flags, no stubs, no empty artifacts)

---

# Templates

The playbook provides the platform-specific test base class template (`template-journey-test-case.md`). Copy it into the test target if not already present. It provides:
- Screenshot capture with dedup and timing
- Setup/teardown lifecycle
- Timing log for the Orchestrator's watcher

Usage patterns and code examples are documented in the playbook template entry.

---

# Common Mistakes

| Mistake | Fix |
|---------|-----|
| Builder keeps getting re-launched because test contract assertions are too strict for the current implementation stage | Orchestrator should write contracts that match what's actually testable now, then tighten in later iterations |
| Inspector rejects because screenshots show permission dialogs | Run `/preflight-permissions` first to grant all TCC permissions |
| Tester writes existence-only assertions (`.exists`) for behavioral criteria | Orchestrator's contract compliance check (Step 9) should catch this before Inspector — if it doesn't, tighten the contract |
| Builder and Tester both try to modify the same file | Enforce role separation — Builder writes production code, Tester writes test code only |
| Loop stalls with no progress for multiple iterations | Check stall detection — if Builder/Tester produce no changes for 2 iterations, re-launch with Inspector's last failure list |
| Playbook gist update fails with 403/404 | Auto-fork triggers automatically — see [playbooks.md](playbooks.md) |

---

# Safety & Limits

- **No iteration limit.** Loop runs until user stops or stop condition met.
- **Stall detection:** If Builder or Tester produces no changes for 2 consecutive iterations, log and re-launch with Inspector's last failure list.
- **Only the Analyst can modify the spec** (local `spec.md` or gist) — read-only for all other agents. The Analyst must confirm changes with the human before writing.
- **feedback-log.md is append-only** — entries are never deleted, only marked resolved.
- **Playbook gists are append-only.** New entries can be added; existing entries should not be deleted.
- Recurring tasks auto-expire after 7 days if run via `/loop`.

---

# Optional External Skills

These skills enhance autocraft but are not required. If not installed, autocraft works without them.

| Skill | Used by | Purpose |
|-------|---------|---------|
| `/frontend-design` | Inspector (via Orchestrator) | Design principles for screenshot review. If missing, Inspector uses general design judgment. |
| `/attack-blocker` | Builder | Structured approach to resolving permission/hardware blockers. If missing, Builder reports blockers to Orchestrator directly. |
| `/preflight-permissions` | User (before first run) | Grants macOS TCC permissions. Bundled in this repo. |
