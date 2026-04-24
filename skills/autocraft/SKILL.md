---
name: autocraft
description: >
  Use when the user says "autocraft", "build journeys", "test the spec", or "cover my spec".
  Also use when the user has a spec.md and wants automated implementation with real output
  verification. Supports UI projects (screenshot-verified), integration-only projects
  (pipeline-verified), and test refactoring tasks.
  Use "autocraft init" to install the always-on Analyst into a project via CLAUDE.md.
argument-hint: "[spec-file-path | init]"
---

# Autocraft

Five agents. Strict roles. No self-grading. Human in the loop.

```
Human ◄──► Analyst (foreground agent)
               │
               ├──► spec.md (writes/updates)
               ├──► .autocraft/feedback-log.md (routes feedback)
               │
               ▼
           Orchestrator (you) ──► Builder (background agent)
                              ──► Tester (background agent)
                              ──► Inspector (foreground agent)
```

The **Analyst** talks to the human, collects feedback, writes and updates spec.md, and routes actionable feedback to the right agent. → [analyst.md](analyst.md)
The **Builder** implements features but CANNOT write tests, review its own work, grade itself, or commit. → [builder.md](builder.md)
The **Tester** works in two modes — **State mode** writes assertion-based integration tests; **Screen mode** sharpens a `journey.md` scenario and spawns a separate Claude instance to run it with vision. Cannot modify production code. → [tester.md](tester.md)
The **Inspector** audits both modes — forensic code scans for State mode, journey-structure scans + screenshot-evidence review for Screen mode. Only the Inspector can set "polished." → [inspector.md](inspector.md)
The **Orchestrator** routes each acceptance criterion by mode ("verify needs eyes on screen?" → Screen mode; observable state → State mode; hybrid → both) and commits only when the Inspector approves. → [orchestrator.md](orchestrator.md)

**Why this separation matters:** A builder who writes their own tests optimizes for tests that pass — not for tests that prove features work. A separate tester reads the contract, exercises the pipeline, and checks what came out. If the output is wrong, they write a failing test — and the builder has to make it pass.

---

## When to Use

- Building a new app or feature set from a spec with multiple acceptance criteria
- You want automated, verified proof that every criterion is met — **Screen mode journey** (markdown scenario executed by Claude with vision) for UI-visible criteria; **State mode integration tests** (assertion-based) for observable-state criteria (API responses, file contents, exit codes)
- The project needs real implementations (not stubs) with independent test verification
- Consolidating or refactoring tests into scenario-based integration tests
- Building or testing CLI tools, libraries, or APIs where data pipeline correctness matters
- You have a `spec.md` (or gist) describing requirements and acceptance criteria

## When NOT to Use

- **Single-file bug fixes** — just fix the bug directly
- **Quick prototyping** where stubs are acceptable
- **No spec yet** — start with the Analyst step or write spec.md first

## Criterion Mode

Every acceptance criterion is routed by the Orchestrator (see Step 6 "Mode routing rule"):

- **State mode (`integration-test-contract.md`)** — verification is about observable state: API payloads, file contents, DB rows, exit codes
- **Screen mode (`journey.md`)** — verification requires eyes on screen: layout, toasts, modals, visual regressions, crash-free interactions
- **Hybrid** — both matter; both artifacts generated, both must pass

Behavior follows from the routed criteria, not from a project-level flag:
- If no criterion routes to Screen mode, no `journey.md` is drafted (Step 6 produces nothing).
- If no criterion routes to State mode, no `integration-test-contract.md` is drafted (Step 7 produces nothing).
- If the task has no production code changes (e.g., pure test refactoring), the Builder is skipped.
- The Inspector runs only the scans relevant to the artifacts that exist.

---

## Inputs

**Special command:** If `$ARGUMENTS` is `init`, run the init flow instead of the build loop:

1. Copy `{skill-base-dir}/claude-md-template.md` to `CLAUDE.md` in the user's project root
2. Create `.autocraft/` directory if it doesn't exist
3. Tell the user: "Analyst is now always-on in this project. Just talk naturally — I'll handle specs, feedback routing, and build triggers automatically."
4. **Do not start the build loop.** Return immediately.

If `CLAUDE.md` already exists, append the Analyst section under a `# Autocraft Analyst` heading instead of overwriting.

---

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

The Orchestrator detects the source type at startup and stores it in `.autocraft/journey-loop-state.md` as `Spec source: gist:<gist-id>` or `Spec source: file:<path>`. All agents read the spec through a consistent method — the Orchestrator fetches the latest content and includes it in each agent's prompt. The Analyst writes spec updates to a temp file then pushes via `gh api`.

---

## Shared State Files

| File | Written by | Read by |
|------|-----------|---------|
| `.autocraft/journeys/*/` | Builder (code), Tester (tests/journey artifacts) | Inspector, Orchestrator |
| `.autocraft/journeys/*/journey.md` | **Orchestrator** (drafts skeleton), **Tester** (sharpens locators/waits/Pass clauses) | Journey executor (Claude instance), Inspector |
| `.autocraft/journeys/*/integration-test-contract.md` | **Orchestrator** | **Tester** (implements as code), Inspector (validates) |
| `.autocraft/journeys/*/screenshots/` | Screen mode journey executor | Inspector (Phase 1B evidence check + Phase 2c sanity review) |
| `.autocraft/journey-state.md` | Tester (`needs-review`), Inspector (`polished`/`needs-extension`) | All |
| `.autocraft/journey-refinement-log.md` | Inspector | Orchestrator |
| `.autocraft/journey-loop-state.md` | Orchestrator | Orchestrator (resume) |
| `AGENTS.md` (repo root) | Inspector | Builder, Tester (each restart) |
| `.autocraft/feedback-log.md` | Analyst | Orchestrator, Builder, Tester, Inspector |

---

## Playbooks

Playbooks are platform-specific knowledge bases that live inside this skill at `skills/autocraft/playbooks/`. The Orchestrator reads them once per invocation and injects the content directly into each agent's prompt (see [orchestrator.md](orchestrator.md) Step 2). No network, no gist — just files.

Projects can override the path via a `.autocraft` file at repo root (`"playbooks_path": "tools/my-playbooks/"`). See [playbooks.md](playbooks.md) for the registry format, entry format, and how to add or update a platform.

---

## Orchestrator Protocol

The full 12-step orchestrator protocol — including agent launch directives, mode routing, journey drafting, integration contract generation, compliance validation, and the build loop — is in **[orchestrator.md](orchestrator.md)**.

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| State mode contract assertions too strict for current implementation stage | Write contracts that match what's testable now, tighten in later iterations |
| Screen mode journey PASS clause too vague ("looks right") | Inspector's Scan B3 auto-rejects. Rewrite to name a specific element, exact text, or property value that the executor can verify |
| Screenshots show permission dialogs | Run `/preflight-permissions` first to grant all TCC permissions |
| Loop stalls with no progress for multiple iterations | Stall detection: if no changes for 2 iterations, re-launch with Inspector's last failure list |
| Playbook file missing or path resolves nowhere | Check `playbooks/registry.json` and `.autocraft` override path; the Orchestrator warns and runs without playbooks, but agent quality drops |

---

## Optional External Skills

These skills enhance autocraft but are not required. If not installed, autocraft works without them.

| Skill | Used by | Purpose |
|-------|---------|---------|
| `driving-macos-with-wda-vision` | Screen mode journey executor (spawned by Tester) | macOS UI automation via WebDriverAgentMac + Appium + vision. Required for Screen mode journeys on macOS apps. |
| Playwright MCP | Screen mode journey executor (spawned by Tester) | Browser UI automation for web apps. Required for Screen mode journeys on web projects. |
| `/frontend-design` | Inspector (via Orchestrator) | Design principles for Screen mode screenshot review. If missing, Inspector uses general design judgment. |
| `/attack-blocker` | Builder | Structured approach to resolving permission/hardware blockers. If missing, Builder reports blockers to Orchestrator directly. |
| `/preflight-permissions` | User (before first run) | Grants macOS TCC permissions. Bundled in this repo. |
