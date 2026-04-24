---
name: autocraft
description: >
  Use when the user says "autocraft", "build journeys", "test the spec", or "cover my spec".
  Use when the user has a spec.md with acceptance criteria and wants every criterion covered
  by real implementation plus independent verification — screenshot-verified for UI behavior
  (Screen mode) or assertion-verified for observable state like API payloads, file contents,
  exit codes (State mode). Use when consolidating or refactoring tests into scenario-based
  integration tests. Use for CLI tools, libraries, or data pipelines where end-to-end
  correctness matters and stubbed/mocked tests would hide real bugs.
argument-hint: "[spec-file-path | init]"
---

# Autocraft

Five agents. Strict roles. No self-grading. Human in the loop.

The **Analyst** talks to the human, writes/updates `spec.md`, and routes feedback. → [analyst.md](analyst.md)
The **Builder** implements features. Cannot write tests or grade itself. → [builder.md](builder.md)
The **Tester** implements the Orchestrator's artifact — **State mode** writes assertion-based integration tests; **Screen mode** sharpens a `journey.md` and spawns a separate Claude instance to run it with vision. Cannot touch production code. → [tester.md](tester.md)
The **Inspector** audits both modes — forensic scans for State mode, structural scans + screenshot-evidence review for Screen mode. Only the Inspector sets `polished`. → [inspector.md](inspector.md)
The **Orchestrator** routes each criterion by mode, drafts the artifacts, and commits only when the Inspector approves. → [orchestrator.md](orchestrator.md)

Separation exists because a builder who writes their own tests optimizes for tests that pass, not tests that prove the feature works.

---

## When to Use

- Building from a spec with acceptance criteria that need independent proof per criterion
- UI projects (screenshot-verified) or pipeline/CLI/library projects (assertion-verified) — or both
- Consolidating/refactoring existing tests into scenario-based integration tests

## When NOT to Use

- Single-file bug fix — just fix it directly
- Quick prototyping where stubs are acceptable
- No spec yet — write one (or launch the Analyst) first

## Criterion Mode

The Orchestrator routes each acceptance criterion (see [orchestrator.md](orchestrator.md) Step 6):

- **State mode (`integration-test-contract.md`)** — verification is observable state: API payloads, file contents, DB rows, exit codes
- **Screen mode (`journey.md`)** — verification needs eyes on screen: layout, toasts, modals, visual regressions, crash-free interactions
- **Hybrid** — both artifacts, both must pass

If no criterion routes to a mode, that artifact isn't drafted. If the task has no production code changes, the Builder is skipped. The Inspector runs only the scans matching existing artifacts.

---

## Inputs

`$ARGUMENTS` is a local spec path, a gist URL/ID, `continue`, or `init`.

**`init`** — copy `{skill-base-dir}/claude-md-template.md` to `CLAUDE.md` at project root (append under a `# Autocraft Analyst` heading if `CLAUDE.md` already exists), create `autocraft/` if missing, tell the user "Analyst is now always-on in this project; just talk naturally." Do not start the build loop.

**Spec source.** Local path → read directly. Gist URL (`https://gist.github.com/...`) or bare 20+ hex ID → fetch via `gh gist view <id> -f spec.md`. See [orchestrator.md](orchestrator.md) Step 1 for detection rules, gist error handling, and resume logic. Only the Analyst writes to the spec (local file or gist).

---

## Shared State Files

**Path resolution.** `autocraft/` is resolved relative to the **spec file's parent directory**, not repo root. Single-spec projects (spec.md at root) behave as before. Multi-spec projects can put specs under subdirs — e.g. `specs/feature-a/spec.md` gets its own `specs/feature-a/autocraft/`, isolated from other specs. `AGENTS.md` is the one exception: always at repo root, shared project-wide.

| File | Written by | Read by |
|------|-----------|---------|
| `autocraft/journeys/*/` | Builder (code), Tester (tests/journey artifacts) | Inspector, Orchestrator |
| `autocraft/journeys/*/journey.md` | **Orchestrator** (drafts skeleton), **Tester** (sharpens locators/waits/Pass clauses) | Journey executor, Inspector |
| `autocraft/journeys/*/integration-test-contract.md` | **Orchestrator** | **Tester** (implements as code), Inspector (validates) |
| `autocraft/journeys/*/screenshots/` | Screen mode journey executor | Inspector (Phase 1B + Phase 2c) |
| `autocraft/journey-state.md` | Tester (`needs-review`), Inspector (`polished`/`needs-extension`) | All |
| `autocraft/journey-refinement-log.md` | Inspector | Orchestrator |
| `autocraft/journey-loop-state.md` | Orchestrator | Orchestrator (resume) |
| `AGENTS.md` (repo root) | Inspector | Builder, Tester (each restart) |
| `autocraft/feedback-log.md` | Analyst | Orchestrator, Builder, Tester, Inspector |

---

## Playbooks

Platform-specific knowledge bases inside this skill at `skills/autocraft/playbooks/`. The Orchestrator loads them at invocation time and injects the content directly into each agent's prompt (see [orchestrator.md](orchestrator.md) Step 2). No network, no gist.

Projects can override via `autocraft/config.json` (`"playbooks_path": "tools/my-playbooks/"`). See [playbooks.md](playbooks.md).

---

## Orchestrator Protocol

The 12-step protocol — launch directives, mode routing, journey drafting, integration contract generation, compliance validation, and loop — is in **[orchestrator.md](orchestrator.md)**.

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| State mode contract assertions too strict for current implementation stage | Write contracts that match what's testable now, tighten in later iterations |
| Screen mode journey PASS clause too vague ("looks right") | Inspector Scan B3 auto-rejects. Name a specific element, exact text, or property value. |
| Screenshots show permission dialogs | Run `/preflight-permissions` first to grant all TCC permissions |
| Loop stalls with no progress for multiple iterations | Stall detection: if no changes for 2 iterations, re-launch with Inspector's last failure list |
| Playbook file missing or path resolves nowhere | Check `playbooks/registry.json` and `autocraft/config.json`; Orchestrator warns and runs without playbooks, but agent quality drops |

---

## Optional External Skills

These enhance autocraft; none are required.

| Skill | Used by | Purpose |
|-------|---------|---------|
| `driving-macos-with-wda-vision` | Screen mode executor | macOS UI automation + vision |
| Playwright MCP | Screen mode executor | Web UI automation |
| `/frontend-design` | Inspector | Design principles for screenshot review |
| `/attack-blocker` | Builder | Structured approach to permission/hardware blockers |
| `/preflight-permissions` | User (once) | macOS TCC permissions setup (bundled here) |
