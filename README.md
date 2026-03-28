# autocraft

A Claude Code plugin that builds and tests user journeys from `spec.md` with screenshot verification, a self-improving refinement loop, and design quality checks.

## What it does

- Reads your product spec and builds one UI test journey at a time (XCUITest for macOS, Playwright for web)
- Takes a screenshot at every step and enforces a 5-second gap rule between screenshots
- Runs 3 polish rounds per journey: testability → refactor → UI/design review
- Tracks every acceptance criterion in your spec and won't stop until all are implemented, tested, and screenshot-verified
- Accumulates platform-specific solutions in a shared pitfalls gist so hard-won fixes are never lost

## Installation

Requires Claude Code 1.0.33 or later.

### Option 1: Install via marketplace

```bash
/plugin marketplace add sunfmin/autocraft
/plugin install autocraft
```

### Option 2: Install from local clone

```bash
git clone https://github.com/sunfmin/autocraft.git
claude --plugin-dir ./autocraft/plugins/autocraft
```

## Skills

Once installed, skills are available under the `autocraft:` namespace:

| Skill | Command | When to use |
|-------|---------|-------------|
| `preflight-permissions` | `/autocraft:preflight-permissions` | **Run once first.** Sets up code signing, grants macOS TCC permissions, runs a smoke test. |
| `journey-builder` | `/autocraft:journey-builder` | Build and test the next uncovered user journey from `spec.md`. |
| `refine-journey` | `/autocraft:refine-journey` | Evaluate the last journey-builder run, score it, and improve `AGENTS.md`. |
| `journey-loop` | `/autocraft:journey-loop [spec.md]` | Run the full automated loop until all spec requirements are covered. |

## Quick start

1. Add a `spec.md` to your project root describing your product's requirements and acceptance criteria.

2. Run preflight once to set up permissions:
   ```
   /autocraft:preflight-permissions
   ```

3. Start the automated loop:
   ```
   /autocraft:journey-loop
   ```

   The loop runs until every acceptance criterion in your spec has a real implementation, a test step, and a screenshot proving it works. It stops only when the overall score reaches 95% **and** all criteria are covered.

4. Or build journeys one at a time:
   ```
   /autocraft:journey-builder
   ```

## Project layout

After running, your project will contain:

```
spec.md                        # Your product spec (read-only)
journey-state.md               # Status of each journey (in-progress / needs-extension / polished)
journey-loop-state.md          # Orchestrator history and acceptance-criteria master list
journey-refinement-log.md      # Scoring history across refinement runs
AGENTS.md                      # Project-specific overrides written by the refiner
journeys/
  001-first-launch-setup/
    journey.md                 # Steps, spec coverage mapping, acceptance criteria
    screenshots/               # One PNG per step
    screenshot-timing.jsonl    # Gap timing per screenshot
    testability_review_*.md
    ui_review_*.md
  002-.../
```

## Requirements

- **macOS apps:** Xcode + XcodeGen (`brew install xcodegen`), `gh` CLI for pitfalls gist access
- **Web apps:** Node.js + Playwright (`npm i -D @playwright/test`)
- A `spec.md` in the project root with requirements and acceptance criteria
