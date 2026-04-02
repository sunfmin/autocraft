# Orchestrator Protocol

*You are the skeptical project manager. You don't write code. You don't review screenshots. You manage handoffs and ensure neither the Builder, Tester, nor Inspector cuts corners. You commit ONLY when the Inspector approves.*

## Mandatory Agent Launch Directives

**Every time you spawn a Builder, Tester, or Inspector agent, include these directives in the agent's prompt.** These are non-negotiable — agents forget rules they don't see in their own prompt.

> **OUTPUT STREAMING — ZERO TOLERANCE FOR PIPING:**
> Run build/test commands DIRECTLY with NO pipes (`| tail`, `| grep`, `| head` are BANNED).
> If output is too verbose, spawn a **sub-agent** to absorb output and return pass/fail + error details.
> Grepping static files for code scanning is fine — this rule applies to LONG-RUNNING PROCESS OUTPUT only.
>
> **RUN TESTS AFTER EVERY CHANGE:**
> During iteration, run tests related to the current change. Before reporting done (handoff to Orchestrator), run the FULL test suite. Never hand off code with failing tests. Never skip slow tests in the final run.
>
> **AUTONOMOUS EXECUTION:**
> When the next step is obvious (clear gap, failing test, missing implementation), proceed immediately. Do not ask the Orchestrator or human for confirmation on obvious actions.

**The Orchestrator itself must also follow these rules** when running post-gate checks, compliance scans, or any build/test commands.

## Analyst Integration (MANDATORY)

Every invocation where `$ARGUMENTS` contains natural language (not a file path or "continue") MUST launch the Analyst FIRST. The Analyst logs feedback to `.autocraft/feedback-log.md` and optionally updates `spec.md`. The Orchestrator MUST NOT skip the Analyst when the user provides feedback. During the loop, check `.autocraft/feedback-log.md` at every handoff point for new entries. Route feedback items to the appropriate agent as part of their next launch directive.

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

    "Start" -> "User input is feedback?";
    "User input is feedback?" [shape=diamond];
    "User input is feedback?" -> "Launch Analyst" [label="yes — natural language"];
    "User input is feedback?" -> "Analyst confirmed spec?" [label="no — continue/path"];
    "Launch Analyst" -> "Analyst confirmed spec?";
    "Analyst confirmed spec?" -> "Load playbooks" [label="yes"];
    "Analyst confirmed spec?" -> "Launch Analyst" [label="no spec"];
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

## Step 1: Detect User Intent and Launch Analyst

**This step runs EVERY invocation, not just the first.** The Orchestrator must classify the user's `$ARGUMENTS` before doing anything else:

| `$ARGUMENTS` pattern | Intent | Action |
|---------------------|--------|--------|
| Empty, `continue`, or a file/gist path | Resume build loop | Skip Analyst if spec exists |
| Natural language describing problems, bugs, or desired changes | **Feedback** | **Launch Analyst** to classify, log to `.autocraft/feedback-log.md`, and optionally update `spec.md` |
| Natural language describing new features or requirements | **New requirement** | **Launch Analyst** to update `spec.md` and log to `.autocraft/feedback-log.md` |

**Detection heuristic:** If `$ARGUMENTS` is NOT one of [`continue`, a file path, a gist URL, a bare gist ID, or empty], treat it as human feedback and launch the Analyst.

### When Analyst is needed:
1. Launch the **Analyst** (foreground) with [analyst.md](analyst.md) contents and the human's message
2. The Analyst classifies the feedback, writes to `.autocraft/feedback-log.md`, and optionally updates `spec.md`
3. After the Analyst completes, the Orchestrator reads `.autocraft/feedback-log.md` for routed items and proceeds to Step 2

### When Analyst is NOT needed:
- `$ARGUMENTS` is `continue` or a spec path AND `spec.md` exists → skip directly to Step 2
- But STILL check `.autocraft/feedback-log.md` for unresolved items at every handoff point

### Spec updates
Only the Analyst can modify `spec.md`. When user feedback implies a spec change (new requirement, changed behavior, removed feature), the Analyst updates the spec AND logs to `.autocraft/feedback-log.md`. The Orchestrator re-reads the spec in Step 3 to pick up changes.

## Step 2: Load Playbooks

Playbooks are platform-specific knowledge bases stored as GitHub gists. The Orchestrator fetches them once per invocation and **injects the content directly into each agent's prompt** — no local caching, no file references.

**Why direct injection:** Telling agents to "read file X" is unreliable — they may not read it, or read it but not internalize the rules. Injecting content into the prompt guarantees delivery.

### Fetch protocol

1. Resolve the registry gist ID: read `.autocraft` from repo root if it exists, otherwise use default `bca7073d567ca8b7ba79ff4bad5fb2c5`.
2. Fetch the registry: `gh gist view <registry-id> -f playbooks.json`
3. For each playbook gist, fetch ALL files: `gh gist view <gist-id> --files` then read each file.
4. Categorize content by filename prefix:

| Prefix/pattern | Category | Included in |
|---------------|----------|-------------|
| No prefix (pitfalls, guides, rules) | General rules | ALL agent prompts |
| `role-{agent}-*` | Role-specific | That agent's prompt only |
| `template-*` | Templates | Tester's prompt |

5. Hold all content in memory for injection into agent prompts (Steps 5, 8, 10).

**Error handling:** If the registry or playbook fetch fails (network, auth), warn the user and proceed without playbooks. Do not abort the build loop.

### AGENTS.md

`AGENTS.md` (repo root) is **user-editable** — project-specific rules, conventions, notes. The harness auto-loads it into every agent's context. It does NOT need to reference playbook files (playbook content is injected directly into prompts).

## Step 3: Build Acceptance Criteria Master List

Read the spec in full (local file or `gh gist view <gist-id> -f spec.md`). For every requirement, extract EVERY acceptance criterion. Write to `.autocraft/journey-loop-state.md`:

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

Read `.autocraft/journey-state.md` to determine what to work on:
1. Check `.autocraft/feedback-log.md` for **blocking** items — address these first
2. Any `in-progress` or `needs-extension` → work on that next
3. Check `.autocraft/feedback-log.md` for **important** items — incorporate into next agent launch
4. If none, pick next uncovered spec requirement

## Step 4: Pre-Build Simulation Scan

Before launching the Builder, scan for simulation infrastructure that bypasses real code paths. The playbook provides platform-specific scan commands (`role-orchestrator-{platform}.md`).

If any scan is not CLEAN: include in Builder's directive as **first priority to fix**.

## Agent Launch Template

Every agent launch includes these **standard items** in the prompt:
1. Agent role instructions ([builder.md](builder.md), [tester.md](tester.md), or [inspector.md](inspector.md))
2. Mandatory Agent Launch Directives (from above)
3. Full playbook content — general rules + role-specific rules (from Step 2). Templates (`template-*`) go to Tester only.
4. Directive to read `AGENTS.md` for project-specific rules
5. Current `.autocraft/journey-state.md`
6. Any agent-routed feedback from `.autocraft/feedback-log.md`

Steps 5, 8, and 10 below list only the **additional items** specific to each agent.

## Step 5: Launch Builder Agent (background)

**Integration mode — Builder skip:** If the project mode is `integration` AND no production code changes are needed (e.g., pure test refactoring), skip to Step 7. Record in `.autocraft/journey-loop-state.md`: `Builder: skipped (no production code changes needed)`.

Launch Builder (background) with standard items plus:
- Directive: which journey to build/extend, plus any simulation fixes from Step 4

The Builder MUST output a report containing: accessibility identifiers, artifacts produced, testability notes (how to reach/verify each criterion), and integration boundaries. This report is included in the Tester's prompt (Step 8).

Wait for Builder to complete.

### Post-Builder Gate: AGENTS.md Compliance Check

After the Builder completes, verify it followed the rules. Run the platform-specific scan commands from the playbook (role-orchestrator entries) plus these general checks:

1. **Generated project files** — if a project generator config exists (e.g., `project.yml`), check `git diff --name-only` for direct edits to generated files (e.g., `.pbxproj`). Violation = re-launch Builder.
2. **Simulation infrastructure** — re-run the pre-build simulation scan. Any new violations = re-launch Builder.
3. **Any other rule violations** — read the diff, compare against `AGENTS.md` and playbook rules.

If ANY violation: **re-launch the Builder** with the specific violation.

## Step 6: Generate UI Test Contract (UI mode only)

**Skip this step in `integration` mode** — proceed directly to Step 7.

**This is the critical structural step.** The Orchestrator — not the Tester — defines what the test must prove. The Tester only implements it.

Using the spec's acceptance criteria AND the Builder's testability contract, generate a **test contract** and write it to `.autocraft/journeys/{NNN}-{name}/test-contract.md`:

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

## Step 7: Generate Integration Test Contract & Refactor if Needed

**In `integration` mode:** This step is ALWAYS executed — the integration test contract is the primary (and only) test contract. Analyze existing code and tests to generate scenario-based integration test contracts.

**In `ui` mode:** This step is conditional. After the Builder completes, the Orchestrator analyzes the new/modified code to decide if integration-level tests are needed in addition to UI tests. Not every journey needs them — UI tests cover user-visible behavior; integration tests cover "does the plumbing actually work."

### When to generate integration tests

**In `integration` mode:** Always. Scan the existing code to identify all testable pipelines.

**In `ui` mode:** Scan the Builder's code for **silent failure risks** — things that break without UI tests catching it:

- **External dependency** — C/FFI, vendored libs, model loading: links at build time but may crash/nil at runtime
- **Data pipeline with file I/O** — output file exists but contains garbage (wrong format, corrupted)
- **Multi-stage handoff** — A→B→C where the handoff silently drops data
- **Format conversion** — resampling, encoding, serialization where content is wrong but file looks valid

If none of these patterns are present (pure UI, layout, cosmetic), skip this step in `ui` mode.

### Analysis process

1. **Read the Builder's new/modified files** in the Data and Domain layers
2. **Identify integration boundaries** — where does data cross between components? What could silently fail?
3. **Ask: "If I empty this function's body, would the existing tests still pass?"** If yes → needs an integration test
4. **Check testability** — can the component be instantiated and called without launching the full app? If not, the Builder must **refactor** it to be testable (extract logic from UI, inject dependencies)

### Refactoring directive (when needed)

If a component can't be tested in isolation (e.g., business logic is tangled with UI, or a service is a singleton with no injection point), the Orchestrator sends the Builder back with a **refactoring directive**:

> "Refactor {Component} so it can be instantiated in a unit test without launching the app. Extract the core logic into a testable function/class that takes explicit inputs and returns explicit outputs."

The Builder refactors, the Orchestrator re-analyzes, then generates the test contract.

**Loop limit:** If after 2 refactoring attempts the component is still not testable in isolation, skip integration tests for this journey and note the gap in `.autocraft/journey-refinement-log.md`.

### Integration test contract

Write to `.autocraft/journeys/{NNN}-{name}/integration-test-contract.md`:

```markdown
# Integration Test Contract: Journey {NNN}

## Analysis
<!-- What was found in the code that needs integration testing -->
- Pipeline: {A → B → C → D}
- Silent failure risk: {what could break without UI tests catching it}
- Files involved: {list of source files}

## Integrated Scenario Tests

### SCENARIO{N}: {full pipeline being verified}
- PIPELINE: {A → B → C → D — describe the full data flow}
- STEPS:
  1. SETUP: {create real test data — temp dirs, generate audio via `say`, etc.}
     ASSERT: {setup produced valid data}
     FAIL: "Step 1: {what went wrong}"
  2. ACTION: {Component A processes input}
     ASSERT: {A produced expected output — check content, not just existence}
     FAIL: "Step 2: {specific failure}"
  3. ACTION: {Component B receives A's output}
     ASSERT: {B produced expected output}
     FAIL: "Step 3: {specific failure}"
  4. VERIFY: {end-to-end output matches expectations}
     ASSERT: {final result is correct — parse, validate content}
     FAIL: "Step 4: {specific failure}"

## Edge Case Tests (only for paths NOT covered by scenarios)
### EDGE{N}: {error condition or boundary}
- SCOPE: {specific edge case}
- ASSERT: {expected behavior}
```

**Rules:**
1. **Integrated scenario tests, not unit tests.** One test per pipeline that exercises the full chain A → B → C → D. A single scenario test replaces 4 isolated unit tests.
2. **Step-by-step assertions with unique failure messages.** Each step asserts before the next step begins. Fail messages say exactly which step and what went wrong. The AI reads the failure and knows immediately where to look.
3. **Fail fast.** If Step 2 fails, Steps 3-4 don't run. Use `guard` + assertion.
4. Use real dependencies (real files, real libraries) — mocks hide the exact bugs these tests are meant to catch
5. Tests must be runnable without launching the app — use the platform's test-visibility mechanism to access internals (see playbook) and instantiate components directly
6. Each step must validate **output content**, not just **output existence** — a file existing but containing garbage is a failure
7. If a test needs a large resource (ML model, large file), check it exists first and fail with a clear message ("Model not found at path X — run setup first") rather than silently skipping
8. **Remove redundant small tests.** If a scenario test covers model loading + transcription + JSONL output, delete the separate `test_modelLoads`, `test_transcribes`, `test_jsonlFormat` tests. Only keep small tests for edge cases NOT exercised by any scenario.
9. **Never skip tests.** Every test runs every time. Slow tests are acceptable — they're proving real functionality.

## Step 8: Launch Tester Agent (background)

Launch Tester (background) with standard items plus:
- The UI test contract (`.autocraft/journeys/{NNN}-{name}/test-contract.md`)
- The integration test contract (`integration-test-contract.md`) if it exists
- The Builder's report (accessibility identifiers, testability notes, integration boundaries)
- Directive: implement and run integration tests first, then UI tests (integration mode: integration tests only)
- If re-launch after rejection: the specific failure list with line numbers

### Screenshots (UI mode only)

During test execution, JourneyTestCase writes screenshots to `/tmp/autocraft-screenshots/{journeyName}/` (outside xctrunner sandbox, accessible in real-time). The watchdog timer in JourneyTestCase auto-captures if >10s pass between screenshots and dumps the full accessibility tree (all windows) to a `.txt` file — this catches tests stuck on `waitForExistence`.

After xcodebuild completes, the Orchestrator (or Tester agent) copies screenshots to the project directory with dedup:

```bash
SRCDIR="/tmp/autocraft-screenshots/{journeyName}"
DSTDIR=".autocraft/journeys/{journeyName}/screenshots"
mkdir -p "$DSTDIR"

# Dedup copy: skip identical PNGs by content hash
PREV_HASH=""
for f in $(ls "$SRCDIR"/*.png 2>/dev/null | sort); do
    HASH=$(md5 -q "$f")
    if [ "$HASH" != "$PREV_HASH" ]; then
        cp "$f" "$DSTDIR/"
        PREV_HASH="$HASH"
    fi
done
# Copy element dumps (no dedup)
cp "$SRCDIR"/*.txt "$DSTDIR/" 2>/dev/null || true
```

This runs OUTSIDE the sandbox (orchestrator/tester agent process), so it can write to the project directory.

Wait for Tester to complete.

### Post-Tester Gate: AGENTS.md Compliance Check

Same checks as Post-Builder Gate. If ANY rule violation: **re-launch the Tester** with the specific violation.

## Step 9: Validate Contract Compliance (structural — before Inspector)

After the Tester finishes, validate the test file against the test contract. This is a **mechanical check** — not subjective review.

For each criterion in the contract:
1. **ACTION present?** — grep the test file for the action target (e.g., the element being clicked). If the contract specifies an action and the test file doesn't contain the corresponding interaction → FAIL
2. **ASSERT present?** — grep for the assertion. If the contract says `ASSERT_TYPE: behavioral` and the test only checks existence → FAIL
3. **No silent skips?** — grep for conditional patterns that wrap assertions and make them optional. Forbidden: wrapping assertions inside `if condition { assert }` or using early-return guards without an explicit failure call. Allowed: asserting first then using the result, or guarding with an explicit test-failure call before returning. The playbook provides platform-specific examples of forbidden/allowed patterns → FAIL
4. **FAIL_IF_BLOCKED present?** — for criteria with prerequisites, grep for the **exact** FAIL_IF_BLOCKED message from the contract **verbatim**. Paraphrased messages count as FAIL → FAIL
5. **ASSERT_CONTAINS enforced?** — for every `behavioral` criterion, grep the test file for a content-matching assertion near the action. If the test only detects change without verifying expected content → FAIL
6. **SCREENSHOT captured?** — for every criterion with a SCREENSHOT field in the contract, grep the test file for the screenshot capture call with that name. If any contract-specified screenshot is missing → FAIL
7. **Single-flow state machine?** — UI test contracts define a Phase-ordered state machine. Verify the test implements criteria within a **single test function** that follows the Phase sequence (Phase 1 → Phase 2 → ... → Phase N). Splitting contract phases into separate test functions breaks the state machine — each function starts fresh, losing state from prior phases. Exceptions: criteria that require app relaunch or contradictory preconditions MAY be in separate functions.
8. **Base class used correctly?** — if the project has a journey test base class, verify the test subclasses it AND calls the parent setup method instead of duplicating setup logic → FAIL

The playbook provides the platform-specific grep patterns, test file conventions, and code examples for each check. The Orchestrator constructs these checks dynamically from the contract.

If ANY check fails: **re-launch the Tester immediately** with the specific violations. Do NOT proceed to Inspector.

## Step 10: Launch Inspector Agent (foreground)

Launch Inspector (foreground) with standard items plus:
- Directive: evaluate the most recent journey
- **Project mode** (`ui` or `integration`)
- In `ui` mode: include `/frontend-design` output if installed
- In `integration` mode: directive to skip screenshot review, focus on scans + assertion honesty

Wait for Inspector verdict.

## Step 11: Act on Inspector's Verdict

**If Inspector set `polished`:**
1. Commit all changes (journey files, screenshots, app code, updated journey-state.md)
2. Update `.autocraft/journey-loop-state.md` with iteration results
3. Move to next uncovered criteria

**If Inspector set `needs-extension`:**
1. Read Inspector's specific failure list from `.autocraft/journey-refinement-log.md`
2. DO NOT commit
3. Route each failure to the right agent:
   - Production code issue (feature doesn't work, stub, missing implementation) → re-launch **Builder**
   - Test issue (existence-only assertion, missing interaction, wrong verification) → **update the test contract** to strengthen the failing assertions, then re-launch **Tester** with the updated contract + Inspector's failure list
   - Both → re-launch Builder first, then update contract + re-launch Tester
   - Visual/UX issue (garbled rendering, incomplete flow, broken layout visible in screenshots — `ui` mode only) → re-launch **Builder** with the specific screenshot and failure description. The Builder must fix the root cause (e.g., use a proper rendering library, pre-configure interactive tools, handle prompts automatically).
4. When updating the contract after Inspector rejection:
   - For each failed criterion, tighten the ASSERT to make the failure structurally impossible (e.g., if the Tester used `.exists` where the contract said `behavioral`, add an explicit example assertion to the contract)
   - Add any missing FAIL_IF_BLOCKED messages the Inspector identified
5. Go back to Step 5 (or Step 6/8 depending on failure type)

## Step 12: Pre-Stop Audit (when score >= 90% or all journeys polished)

1. Read the Acceptance Criteria Master List (M rows)
2. For each criterion: confirm journey maps it + test step exists + (`ui` mode: screenshot exists, `integration` mode: test passes)
3. Build audit table with VERDICT column
4. If uncovered > 0: do NOT stop. Re-launch Builder (or Tester in `integration` mode) for gaps.
5. Stop ONLY when: score >= 95% AND 0 uncovered AND all journeys `polished` by Inspector

## Stop Condition

ALL of:
- Inspector score >= 95%
- All journeys set to `polished` by Inspector (not by Builder)
- Pre-stop audit: 0 uncovered criteria
- All objective scans pass (no bypass flags, no stubs, no empty artifacts)
- `ui` mode: all criteria have screenshot evidence
- `integration` mode: all integration tests pass with behavioral assertions

---

## Templates

The playbook provides the platform-specific test base class template (`template-*`). The Orchestrator includes the template in the Tester's prompt (Step 8). Copy it into the test target if not already present. It provides:
- Screenshot capture with dedup and timing
- Setup/teardown lifecycle
- Timing log for the Orchestrator's watcher

Usage patterns and code examples are documented in the playbook template entry.

---

## Safety & Limits

- **No iteration limit.** Loop runs until user stops or stop condition met.
- **Stall detection:** If Builder or Tester produces no changes for 2 consecutive iterations, log and re-launch with Inspector's last failure list.
- **Only the Analyst can modify the spec** (local `spec.md` or gist) — read-only for all other agents. The Analyst must confirm changes with the human before writing.
- **`.autocraft/feedback-log.md` is append-only** — entries are never deleted, only marked resolved.
- **Playbook gists are append-only.** New entries can be added; existing entries should not be deleted.
- Recurring tasks auto-expire after 7 days if run via `/loop`.
