# autocraft

A Claude Code skill that builds and tests user journeys from `spec.md` with real implementations, screenshot verification, and automated quality scans.

## What it does

- Reads your product spec and builds UI test journeys (XCUITest for macOS, Playwright for web)
- Three agent roles with strict separation: **Builder** (implements), **Inspector** (verifies with automated scans), **Orchestrator** (manages handoffs and commits)
- Builder cannot review its own work or set "polished" — only the Inspector can
- Inspector runs objective scans (file sizes, grep for stubs/bypass flags) before any subjective review
- Orchestrator commits only after Inspector approves
- Tracks every acceptance criterion and won't stop until all are implemented, tested, and screenshot-verified with real output

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

   The loop runs until every acceptance criterion has a real implementation, a test step, and a screenshot proving it works with real output (not empty files or stubbed code).

## How it works

```
Orchestrator
  |
  +-- spawns --> Builder Agent
  |               - Implements real features (no stubs)
  |               - Writes honest tests (asserts on content, not existence)
  |               - Sets up real test content (plays audio, opens windows)
  |               - Sets status to "needs-review"
  |
  +-- spawns --> Inspector Agent
  |               - Runs 4 objective scans (artifacts, bypass flags, stubs, assertions)
  |               - Reviews screenshots for real content
  |               - Sets status to "polished" or "needs-extension"
  |
  +-- commits only when Inspector says "polished"
  +-- re-launches Builder if Inspector says "needs-extension"
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
