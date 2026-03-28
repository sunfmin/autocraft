---
name: journey-builder
description: Build and test the longest uncovered user journey from spec.md. Reads the product spec, checks existing journeys, picks the longest untested path, writes a UI test with screenshots at every step, then runs 3 polish rounds (testability → test refactor → UI review) until everything is clean. Use when the user says "next journey", "add journey", "test the next flow", "journey builder", or "cover more user paths".
---

# Journey Builder

Build one user journey at a time. Each journey is a realistic path through the app tested like a real user — with screenshots at every step.

## Prerequisites

- `spec.md` in project root
- `journeys/` folder (created if missing)
- Testable app (XCUITest for macOS, Playwright for web)

## Steps

### 1. Read spec + existing journeys

Read `spec.md`. Read every `journeys/*/journey.md` to know what's covered.

### 2. Pick the next journey

Find the longest uncovered user path. Create a numbered folder: `journeys/{NNN}-{name}/` where `{NNN}` is the next sequence number (e.g., `001-first-launch-setup`, `002-settings-model-management`, `003-recording-flow`). Write `journey.md` inside it describing each step: what the user does, what they should see.

### 3. Write the test

One test file. Act like a real user. Screenshot after every meaningful step via XCTAttachment (macOS) or Playwright locator screenshot (web). Name: `{journey}-{NNN}-{step}.png`.

**macOS:**
```swift
let screenshot = app.windows.firstMatch.screenshot()
let attachment = XCTAttachment(screenshot: screenshot)
attachment.name = "journey-name-001-step-name"
attachment.lifetime = .keepAlways
add(attachment)
```

**Web:**
```typescript
await page.locator('#app').screenshot({
  path: 'journeys/001-journey-name/screenshots/journey-name-001-step-name.png'
});
```

### 4. Run the test

Run only this test. Fix failures. Extract screenshots into the `screenshots/` subfolder:

```bash
{skill-base-dir}/scripts/extract-screenshots.sh /tmp/test-results.xcresult journeys/{NNN}-{name}/screenshots
```

### 5. Polish loop (3 rounds)

Run this loop 3 times (round 1, 2, 3). Each round does all three phases in order. Each phase produces a NEW timestamped file — never overwrite previous rounds.

#### Phase A: Testability Review

Review app code touched by this journey. Check:
- ViewModels accept protocol dependencies via initializer injection
- Use Cases are framework-free (no UIKit/SwiftUI/AppKit imports)
- Side effects (network, disk, permissions) behind protocols
- DependencyContainer has a test factory with all-fake deps
- No shared mutable singletons
- State transitions are testable (given/when/then)

Fix issues: extract protocols, add DI, move logic out of Views. Write fast unit tests (< 1s total). Run them.

Write `journeys/{NNN}-{name}/testability_review_round{N}_{YYYY-MM-DD}_{HHMMSS}.md`.

#### Phase B: Refactor UI test

Clean up the journey test code:
- Readable steps with helpers/page objects where needed
- Proper waits (no sleeps), stable selectors
- Accessibility identifiers on every interactive element

#### Phase C: UI Review — Design-Driven

Read every screenshot in `journeys/{NNN}-{name}/screenshots/`. Review with both platform convention AND design quality lenses.

**Platform Conventions:**
- macOS: HIG compliance — toolbar, sidebar, window chrome, system colors
- Web: Responsive layout, standard navigation patterns, accessibility

**Design Quality:** Apply the `frontend-design` skill principles when reviewing. Evaluate typography, color, spatial composition, visual details, motion, and overall polish level. Flag anti-patterns like generic fonts, flat backgrounds, missing hover states, and unstyled empty states.

Fix all issues in the view code. Re-run the test. Extract fresh screenshots to `screenshots/`.

Write `journeys/{NNN}-{name}/ui_review_round{N}_{YYYY-MM-DD}_{HHMMSS}.md`.

**Round 3 is the final gate** — every screenshot must Pass or have issues explicitly deferred with justification.

### 6. Final verification

Run unit tests + this journey's UI test one last time. Both must pass.

### 7. Commit

New commit (never amend). Include: `journey.md`, all review files, all screenshots. Message summarizes journey, fixes, features covered.

### 8. Report

Tell the user: which journey, how many steps, features covered, issues fixed across rounds, unit tests added, and what journey to build next.

## Rules

- One journey at a time
- Real user behavior only — no internal APIs
- Every step gets a screenshot (app window only)
- Screenshots always go in `journeys/{NNN}-{name}/screenshots/`
- Journey folders are numbered sequentially: `001-`, `002-`, `003-`, etc.
- Fix before moving on
- Each round produces NEW timestamped files — never overwrite
- Unit tests must run in < 1 second total
- Only run this journey's tests, not the full suite
- Use the extract script for screenshots from xcresult
