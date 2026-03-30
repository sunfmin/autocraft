---
name: autocraft
description: >
  Build and verify user journeys from spec.md with real implementations. Orchestrates
  an Analyst (collects human feedback, writes specs), a Builder agent (implements features),
  a Tester agent (writes and runs journey tests independently), and an Inspector agent
  (verifies real output with automated scans) in a loop until all acceptance criteria
  are behaviorally covered.
  Use when the user says "autocraft", "build journeys", "test the spec", or "cover my spec".
argument-hint: [spec-file-path]
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
| `journeys/*/screenshot-timing.jsonl` | Tester (snap helper) | Orchestrator (watcher) |
| `journey-state.md` | Tester (`needs-review`), Inspector (`polished`/`needs-extension`) | All |
| `journey-refinement-log.md` | Inspector | Orchestrator |
| `journey-loop-state.md` | Orchestrator | Orchestrator (resume) |
| `AGENTS.md` (repo root) | Inspector | Builder, Tester (each restart) |
| `feedback-log.md` | Analyst | Orchestrator, Builder, Tester, Inspector |

---

## Playbooks

Playbooks are shared, platform-specific knowledge bases stored as GitHub gists. Each playbook targets a specific platform or domain. Agents load the relevant playbook(s) at the start of every iteration.

### Playbook Registry

Default registry gist: `bca7073d567ca8b7ba79ff4bad5fb2c5`

**Local override:** If `.autocraft` exists at the repo root, read the registry gist ID from it:

```json
{
  "registry_gist_id": "bca7073d567ca8b7ba79ff4bad5fb2c5"
}
```

The Orchestrator resolves the registry ID in this order:
1. `.autocraft` file in repo root → use `registry_gist_id`
2. No `.autocraft` file → use default `bca7073d567ca8b7ba79ff4bad5fb2c5`

```bash
# Read the registry (replace <registry-id> with resolved ID)
gh gist view <registry-id> -f playbooks.json

# Update the registry (non-interactive)
gh api --method PATCH /gists/<registry-id> \
  -f "files[playbooks.json][content]=$(cat /tmp/playbooks.json)"
```

Registry format:
```json
{
  "playbooks": [
    {
      "platform": "macos",
      "gist_id": "84a5c108d5742c850704a5088a3f4cbf",
      "description": "Xcode, SwiftUI, XCUITest, codesign, ScreenCaptureKit"
    }
  ]
}
```

### Playbook Commands

```bash
# List files in a playbook
gh gist view <gist-id> --files

# Read a specific entry
gh gist view <gist-id> -f <filename>

# Add or update an entry (write file locally, then push)
gh api --method PATCH /gists/<gist-id> \
  -f "files[<filename>.md][content]=$(cat /tmp/<filename>.md)"

# Delete an entry
gh api --method PATCH /gists/<gist-id> \
  -f "files[<filename>.md]="
```

### Creating or Updating a Playbook

**Create a new playbook** (e.g., "create a web playbook"):

1. **Gather content** — ask the user what entries to include, or accept content they provide
2. **Write entry files** to `/tmp/` using kebab-case names: `{category}-{short-name}.md` (e.g., `networking-cors-preflight.md`, `testing-playwright-selectors.md`)
3. **Create the gist**:
   ```bash
   gh gist create --public -d "Autocraft playbook: {platform}" /tmp/entry1.md /tmp/entry2.md ...
   # Capture the gist ID from the output URL (last path segment)
   ```
4. **Register the playbook** — fetch the registry gist (resolve ID from `.autocraft` or default), add the new entry, push back:
   ```bash
   # Fetch current registry
   gh gist view <registry-id> -f playbooks.json > /tmp/playbooks.json
   # Add new entry to the playbooks array (use jq or manual edit)
   # Push updated registry
   gh api --method PATCH /gists/<registry-id> \
     -f "files[playbooks.json][content]=$(cat /tmp/playbooks.json)"
   ```
   Platform keys: lowercase, no spaces (e.g., `macos`, `web`, `ios`, `android`, `go`, `python`)
5. **Clean up** temp files in `/tmp/`

**Update an existing playbook** (e.g., "add a CORS entry to the web playbook", "update the builder macOS guide"):

1. **Resolve the gist ID** — look up the platform in the registry to get its `gist_id`
2. **Fetch current content** (if updating an existing entry):
   ```bash
   gh gist view <gist-id> -f <filename>.md > /tmp/<filename>.md
   ```
3. **Write or edit** the entry file in `/tmp/`
4. **Push** — the same PATCH command adds new files or overwrites existing ones:
   ```bash
   gh api --method PATCH /gists/<gist-id> \
     -f "files[<filename>.md][content]=$(cat /tmp/<filename>.md)"
   ```
   Multiple files can be pushed in a single PATCH by adding more `-f` flags.
5. **Clean up** temp files in `/tmp/`

Each entry in a playbook should follow this format (2-5 sentences per section minimum, Solution must include runnable code or exact commands):

```markdown
# {Short title}

## Problem
{What goes wrong and when}

## Solution
{Exact steps, commands, or code to fix it}

## Why
{Root cause — so agents can recognize variants of the same problem}
```

### Selecting Playbooks for a Project

The Orchestrator resolves the registry gist ID (from `.autocraft` or the default) at startup and loads ALL registered playbooks. If the project only uses one platform, only that playbook's entries are included in agent prompts.

**Error handling:** If the registry gist fetch fails (network, auth), warn the user and proceed without playbooks. Do not abort the build loop.

**Ownership (auto-fork):** Only the gist owner can update the registry. When the Orchestrator needs to update the registry (e.g., registering a new playbook) and the `gh api PATCH` fails with a 404 or 403, automatically fork and switch:

```bash
# 1. Fork the registry
FORK_URL=$(gh gist fork <registry-id> 2>&1)
FORK_ID=$(echo "$FORK_URL" | grep -oE '[a-f0-9]{20,}' | tail -1)

# 2. Save fork ID to .autocraft
echo "{\"registry_gist_id\": \"$FORK_ID\"}" > .autocraft

# 3. Retry the update with the fork
gh api --method PATCH /gists/$FORK_ID \
  -f "files[playbooks.json][content]=$(cat /tmp/playbooks.json)"

# 4. Commit .autocraft
git add .autocraft && git commit -m "Use forked playbook registry: $FORK_ID"
```

This is transparent — future sessions read `.autocraft` and use the fork automatically.

---

# Orchestrator Protocol (this agent)

You are the skeptical project manager. You don't write code. You don't review screenshots. You manage handoffs and ensure neither the Builder, Tester, nor Inspector cuts corners. You commit ONLY when the Inspector approves.

**Analyst integration:** Before starting the build loop, check if the Analyst has been invoked. If not, launch the Analyst first to confirm the spec with the human. During the loop, check `feedback-log.md` at every handoff point (between Steps 3→4, 4→5, 5→3) for new entries. Route feedback items to the appropriate agent as part of their next launch directive.

## Step 0: Launch Analyst (first iteration only)

If this is the first iteration and `spec.md` does not exist or the human has new input:
1. Launch the **Analyst** (foreground) with [analyst.md](analyst.md) contents and the human's request
2. The Analyst will gather requirements, write/update `spec.md`, and confirm with the human
3. Only proceed to Step 0.5 after the Analyst signals that the spec is confirmed

If the human provides feedback mid-loop, re-launch the Analyst to classify and route it (see Analyst Step 5). The Analyst writes to `feedback-log.md`; the Orchestrator picks up routed items at the next handoff.

## Step 0.5: Load Playbooks (every iteration)

Resolve the registry gist ID: read `.autocraft` from repo root if it exists, otherwise use default `bca7073d567ca8b7ba79ff4bad5fb2c5`. Fetch the registry, then for each registered playbook, fetch and read ALL files from its gist.

**Role-specific entries** (prefixed `role-{agent}-`) contain the platform-specific commands, code patterns, and templates that the corresponding agent needs. Include them in each agent's prompt alongside the pitfall entries.

**Template entries** (prefixed `template-`) contain base class code or boilerplate. The Builder and Tester copy these into the project as needed.

## Step 1: Build Acceptance Criteria Master List

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

## Step 2: Pre-Build Simulation Scan

Before launching the Builder, scan for simulation infrastructure that bypasses real code paths. The playbook provides platform-specific scan commands (`role-orchestrator-{platform}.md`).

If any scan is not CLEAN: include in Builder's directive as **first priority to fix**.

## Step 3: Launch Builder Agent (background)

Spawn a background Agent with:
1. [builder.md](builder.md) contents
2. Full `AGENTS.md` content (if exists)
3. Full playbook contents (all registered playbooks)
4. Current `journey-state.md`
5. Directive: which journey to build/extend, plus any simulation fixes from Step 2
6. Any **Builder-routed feedback** from `feedback-log.md` (unresolved items where `Routed to: Builder`)

The Builder implements production features and creates the journey directory, but does NOT write test files.

Wait for Builder to complete.

## Step 3b: Generate Test Contract (Orchestrator does this — NOT the Tester)

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

## Step 3c: Launch Tester Agent (background)

After the test contract is written, spawn a background Tester Agent with:
1. [tester.md](tester.md) contents
2. Full `AGENTS.md` content (if exists)
3. Full playbook contents (all registered playbooks)
4. The spec file path
5. **The test contract** (`journeys/{NNN}-{name}/test-contract.md`) — the Tester implements this, does not redefine it
6. The Builder's report (accessibility identifiers, testability notes)
7. Directive: implement and run the test contract
8. If this is a re-launch after rejection: include the specific failure list with line numbers
9. Any **Tester-routed feedback** from `feedback-log.md` (unresolved items where `Routed to: Tester`)

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

## Step 3d: Validate Contract Compliance (structural — before Inspector)

After the Tester finishes, validate the test file against the test contract. This is a **mechanical check** — not subjective review.

For each criterion in the contract:
1. **ACTION present?** — grep the test file for the action target (e.g., the element being clicked). If the contract specifies an action and the test file doesn't contain the corresponding interaction → FAIL
2. **ASSERT present?** — grep for the assertion. If the contract says `ASSERT_TYPE: behavioral` and the test only checks existence → FAIL
3. **No silent skips?** — grep for conditional guards that wrap contract assertions. Any match = the Tester made a mandatory assertion optional → FAIL
4. **FAIL_IF_BLOCKED present?** — for criteria with prerequisites, grep for the FAIL message from the contract. If missing, the Tester will silently skip blocked criteria → FAIL
5. **ASSERT_CONTAINS enforced?** — for every `behavioral` criterion, grep the test file for a content-matching assertion near the action. If the test only detects change without verifying expected content → FAIL

The playbook provides the platform-specific grep patterns and test file path conventions (`role-orchestrator-{platform}.md`). The Orchestrator constructs these checks dynamically from the contract.

If ANY check fails: **re-launch the Tester immediately** with the specific violations. Do NOT proceed to Inspector.

## Step 4: Launch Inspector Agent (foreground)

After Tester finishes, spawn an Inspector Agent with:
1. [inspector.md](inspector.md) contents
2. The spec file path
3. Directive: evaluate the most recent journey
4. The `/frontend-design` skill content — invoke `/frontend-design` yourself (Orchestrator) and include its full output in the Inspector's prompt so the Inspector can apply its design principles during screenshot review without interrupting its own flow

Wait for Inspector verdict.

## Step 5: Act on Inspector's Verdict

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
5. Go back to Step 3 (or 3b/3c)

## Step 6: Pre-Stop Audit (when score >= 90% or all journeys polished)

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

# Safety & Limits

- **No iteration limit.** Loop runs until user stops or stop condition met.
- **Stall detection:** If Builder or Tester produces no changes for 2 consecutive iterations, log and re-launch with Inspector's last failure list.
- **Only the Analyst can modify the spec** (local `spec.md` or gist) — read-only for all other agents. The Analyst must confirm changes with the human before writing.
- **feedback-log.md is append-only** — entries are never deleted, only marked resolved.
- **Playbook gists are append-only.** New entries can be added; existing entries should not be deleted.
- Recurring tasks auto-expire after 7 days if run via `/loop`.
