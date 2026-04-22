# autocraft

A Claude Code skill that builds and tests from `spec.md` with real implementations, automated quality scans, and verified output. Two test modes, routed per acceptance criterion:

- **Mode A — integration tests** (assertion-based code) for criteria whose verification is observable state: API responses, file contents, exit codes, DB rows
- **Mode B — UI journeys** (markdown scenarios executed by a Claude instance with vision, via `driving-macos-with-wda-vision` for macOS or Playwright MCP for web) for criteria whose verification requires eyes on screen: layout, toasts, modals, visual regressions, crash-free interactions

Hybrid criteria generate both artifacts; both must pass before a journey is marked polished.

## What it does

- Reads your product spec, routes each acceptance criterion to Mode A or Mode B (or both), and builds the right artifact — assertion-based test code or executable natural-language journey
- Five agent roles with strict separation:
  - **Analyst** — talks to the human, gathers requirements, writes and updates `spec.md`
  - **Builder** — implements real features (no stubs, no fakes); emits testability notes for both modes
  - **Tester** — Mode A: writes integration tests with platform assertion macros. Mode B: sharpens the Orchestrator's journey draft and spawns a separate Claude instance to run it with vision
  - **Inspector** — Mode A: forensic code scans (stubs, bypass flags, vacuous assertions). Mode B: journey-structure scans (vague PASS clauses, missing hazards, evidence-verdict agreement). Subjective screenshot review in both
  - **Orchestrator** — manages handoffs, routes criteria to modes, drafts artifacts, commits only after Inspector approves
- Builder cannot write tests or review its own work; Tester cannot modify production code; only the Inspector can set "polished"
- Tracks every acceptance criterion and won't stop until all are implemented, covered by a Mode A test or Mode B journey, and verified with real output (screenshots for Mode B, test runs for Mode A)

## Installation

```bash
npx skills add sunfmin/autocraft
```

## Skills

| Skill | Command | When to use |
|-------|---------|-------------|
| `preflight-permissions` | `/preflight-permissions` | **Run once first.** Sets up code signing, grants macOS TCC permissions, runs a smoke test. |
| `autocraft` | `/autocraft [spec.md]` | Build, test, and verify all journeys from your spec. Runs the full builder+inspector loop. |

## Quick start

1. Add a `spec.md` to your project root describing your product's requirements and acceptance criteria.

2. Run preflight once to set up permissions:
   ```
   /preflight-permissions
   ```

3. Start the automated loop:
   ```
   /autocraft
   ```

   The loop runs until every acceptance criterion has a real implementation, a test step, and verified proof it works with real output — screenshots for UI projects, passing integration tests for non-UI projects.

## How it works

```
Human ◄──► Analyst (foreground)
               │
               ├──► spec.md (writes/updates)
               ├──► feedback-log.md (routes feedback)
               │
               ▼
           Orchestrator
             |
             +-- spawns --> Builder Agent
             |               - Implements real features (no stubs)
             |               - Sets up real dependencies and content
             |               - Emits testability notes (locators, prereqs, data flows)
             |               - CANNOT write tests or review own work
             |
             +-- per criterion: routes to Mode A (integration contract)
             |                     or Mode B (journey.md)
             |                     or both (hybrid)
             |
             +-- spawns --> Tester Agent
             |               Mode A: implements integration contracts as
             |                       assertion-based test code, runs them
             |               Mode B: sharpens journey locators/waits/PASS clauses,
             |                       spawns a fresh Claude instance to execute
             |                       the journey with vision + mac2.sh/Playwright
             |
             +-- spawns --> Inspector Agent
             |               Mode A: forensic scans (stubs, bypass flags,
             |                       vacuous assertions, silent skip guards)
             |               Mode B: structure scans (vague PASS clauses,
             |                       missing hazards, evidence-verdict agreement)
             |               Both:   screenshot sanity review, spec coverage
             |
             +-- commits only when Inspector says "polished"
             +-- re-launches Builder/Tester if Inspector says "needs-extension"
```

## Project layout

After running, your project will contain:

```
spec.md                                  # Your product spec (read-only)
AGENTS.md                                # Project-specific overrides written by Inspector
.autocraft/
  journey-state.md                       # Status of each journey
  journey-loop-state.md                  # Orchestrator history + criteria master list
  journey-refinement-log.md              # Inspector scoring history
  feedback-log.md                        # Analyst feedback routing
  journeys/
    001-first-launch-setup/
      journey.md                         # Mode B scenario (drafted by Orchestrator,
                                         # sharpened by Tester, executed by a
                                         # spawned Claude instance with vision)
      integration-test-contract.md       # Mode A contract (when hybrid or integration-only)
      screenshots/                       # Evidence screenshots from the journey executor
    002-.../
```

## Requirements

- **macOS UI projects (Mode B):** the `driving-macos-with-wda-vision` skill (provides `mac2.sh` + a running Appium instance on `:4723`). Xcode + XcodeGen (`brew install xcodegen`) for the app itself.
- **Web UI projects (Mode B):** the Playwright MCP (`npm i -D @playwright/mcp`) or a compatible browser-automation driver the spawned executor can call.
- **Integration tests (Mode A):** the project's native test runner — XCTest for Swift, `go test`, Jest, pytest, etc. Installed as project-level dev dependencies.
- Platform playbooks ship inside the skill — no network or `gh` CLI needed.
- A `spec.md` in the project root with requirements and acceptance criteria.
