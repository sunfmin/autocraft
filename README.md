# autocraft

A Claude Code skill that builds and tests from `spec.md` with real implementations, automated quality scans, and verified output. Supports UI projects (screenshot-verified), integration-only projects (pipeline-verified), and test refactoring tasks.

## What it does

- Reads your product spec and builds test journeys — UI tests (XCUITest, Playwright) for UI projects, integration tests for CLI/library/API projects
- Five agent roles with strict separation:
  - **Analyst** — talks to the human, gathers requirements, writes and updates `spec.md`
  - **Builder** — implements real features (no stubs, no fakes)
  - **Tester** — writes and runs journey tests independently from the Builder
  - **Inspector** — verifies real output with automated scans and subjective review
  - **Orchestrator** — manages handoffs, generates test contracts, commits only after Inspector approves
- Builder cannot write tests or review its own work; Tester cannot modify production code; only the Inspector can set "polished"
- Inspector runs objective scans (file sizes, grep for stubs/bypass flags) before any subjective review
- Tracks every acceptance criterion and won't stop until all are implemented, tested, and verified with real output (screenshots for UI, test results for integration)

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
             |               - CANNOT write tests or review own work
             |
             +-- generates test contracts (what to prove)
             |
             +-- spawns --> Tester Agent
             |               - Implements test contracts as executable tests
             |               - Runs integration tests first, then UI tests
             |               - Screenshots every step, sets "needs-review"
             |
             +-- spawns --> Inspector Agent
             |               - Runs 4 objective scans (artifacts, bypass flags, stubs, assertions)
             |               - Reviews screenshots for real content
             |               - Sets status to "polished" or "needs-extension"
             |
             +-- commits only when Inspector says "polished"
             +-- re-launches Builder/Tester if Inspector says "needs-extension"
```

## Project layout

After running, your project will contain:

```
spec.md                        # Your product spec (read-only)
journey-state.md               # Status of each journey
journey-loop-state.md          # Orchestrator history and criteria master list
journey-refinement-log.md      # Inspector scoring history
AGENTS.md                      # Project-specific overrides written by Inspector
journeys/
  001-first-launch-setup/
    journey.md                 # Steps, spec coverage, acceptance criteria
    screenshots/               # One PNG per step
    screenshot-timing.jsonl    # Gap timing per screenshot
  002-.../
```

## Requirements

- **macOS apps:** Xcode + XcodeGen (`brew install xcodegen`), `gh` CLI for pitfalls gist access
- **Web apps:** Node.js + Playwright (`npm i -D @playwright/test`)
- A `spec.md` in the project root with requirements and acceptance criteria
