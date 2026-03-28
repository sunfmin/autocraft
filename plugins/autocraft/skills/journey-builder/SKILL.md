---
name: journey-builder
description: Build and test the longest uncovered user journey from spec.md. Reads the product spec, checks existing journeys, picks the longest untested path, writes a UI test with screenshots at every step, then runs 3 polish rounds (testability → test refactor → UI review) until everything is clean. Use when the user says "next journey", "add journey", "test the next flow", "journey builder", or "cover more user paths".
---

# Journey Builder

Build one user journey at a time. Each journey is a realistic path through the app tested like a real user — with screenshots at every step. Each journey MUST take at least 10 minutes to run end-to-end.

**Depth-chain principle:** A journey is a chain of actions where each step produces an outcome that the next step consumes or verifies. Example: setup → create a recording → verify it appears in library → play it back → check transcript syncs → search for it → delete it → verify it's gone. Every step must exercise something NEW. If you've already clicked a button and verified it works, do not click it again.

## Prerequisites

- `spec.md` in project root
- `journeys/` folder (created if missing)
- Testable app (XCUITest for macOS, Playwright for web)

## Step 0: Load Pitfalls (MANDATORY — do this FIRST)

Before ANY other work, fetch and read ALL pitfall files from the shared pitfalls gist:

```bash
# List all files in the pitfalls gist
gh gist view 84a5c108d5742c850704a5088a3f4cbf --files
```

Then read EVERY file:
```bash
gh gist view 84a5c108d5742c850704a5088a3f4cbf -f <filename>
```

Read each file completely. These contain hard-won solutions to blockers that WILL recur.
Apply every relevant pitfall to your work in this session. Do NOT skip this step.

### Adding New Pitfalls

When you encounter a blocker and find the solution, create a new pitfall file in the gist:

```bash
gh gist edit 84a5c108d5742c850704a5088a3f4cbf -a <category>-<short-name>.md <<'EOF'
# <Title>

## Problem
<What went wrong — exact error message if possible>

## Root Cause
<Why it happened>

## Solution
<Exact fix — code, config, or command>

## Prevention
<How to avoid this in future journeys>
EOF
```

Name files by category: `xcodegen-*.md`, `xcuitest-*.md`, `codesign-*.md`, `swiftui-*.md`, etc.

## Step 1: Check Journey State

Read `journey-state.md` in the project root (create if missing). This file tracks which journeys are complete:

```markdown
# Journey State

| Journey | Status | Test Duration | Last Updated |
|---------|--------|---------------|--------------|
| 001-first-launch-setup | polished | 12m30s | 2026-03-28 |
| 002-settings-model | in-progress | 3m15s | 2026-03-28 |
```

**Decision logic:**
1. Find the first journey where status is `in-progress`, `needs-extension`, OR duration is blank/estimated (`~`)/under 10 minutes — work on that one
2. Only if ALL existing journeys are `polished` with real measured durations >= 10 minutes, pick the next uncovered path from the spec
3. A journey is `polished` ONLY when: all tests pass, all 3 polish rounds done, AND test duration >= 10 minutes (actual measured wall-clock time, not estimated)

## Step 2: Read spec + existing journeys

Read `spec.md`. Read every `journeys/*/journey.md` to know what's covered.

## Step 3: Pick or extend a journey

**If extending an existing journey** (status is `in-progress` or `needs-extension`):
- Read the existing `journey.md` and test file
- Run the test and measure duration
- If under 10 minutes, extend the workflow chain deeper — add steps that produce NEW outcomes: create data, modify it, verify persistence, test edge cases, trigger error states and recover
- Update `journey.md` with the new steps

**If creating a new journey:**
- Find the longest uncovered user path
- Create numbered folder: `journeys/{NNN}-{name}/`
- Write `journey.md` as a depth-chain: each step produces output the next step uses
- Include: complete workflow (create → use → modify → verify → clean up), edge cases, error recovery, data persistence checks

**Anti-repetition rule (HARD):** Before finalizing, scan the test for repeated interactions. If the same element is clicked more than twice, or the same navigation path is traversed more than once, it is padding — remove it. The 10-minute target must be hit through feature depth (more features tested end-to-end), NEVER through repeating interactions already performed. Clicking through 5 model cards once is testing; clicking through them 3 times is waste.

## Step 4: Write the test

One test file. Act like a real user. Screenshot after every meaningful step via XCTAttachment (macOS) or Playwright locator screenshot (web). Name: `{journey}-{NNN}-{step}.png`. The extract script adds elapsed-time prefixes (`T00m05s_`) automatically — you do NOT add timestamps in code.

### Snap helper with built-in timing measurement (MANDATORY)

Every journey test MUST use a `snap()` helper that measures the gap since the last screenshot and writes it to a timing file in real-time. This is the enforcer — no gap > 3s goes unnoticed.

**macOS — required snap helper pattern:**
```swift
// Properties on the test class:
var screenshotIndex = 0
var lastSnapTime: CFAbsoluteTime = 0

// journeyDir must point to the journey folder, e.g.:
// "\(Self.projectRoot)/journeys/001-first-launch-setup"

/// Takes a screenshot, writes it to disk, and logs timing.
/// Pass `slowOK: "reason"` for steps with unavoidable delays > 3s.
private func snap(_ name: String, slowOK: String? = nil) {
    screenshotIndex += 1
    let now = CFAbsoluteTimeGetCurrent()
    let gap = lastSnapTime == 0 ? 0 : now - lastSnapTime
    lastSnapTime = now

    // Determine timing status
    let status: String
    if gap <= 3 {
        status = "ok"
    } else if let reason = slowOK {
        status = "SLOW-OK: \(reason)"
    } else {
        status = "SLOW"
    }

    // 1. Capture screenshot
    let screenshot = app.windows.firstMatch.screenshot()

    // 2. Attach to xcresult (for CI / Xcode results)
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = "journey-name-\(name)"
    attachment.lifetime = .keepAlways
    add(attachment)

    // 3. Write screenshot PNG to disk immediately
    let screenshotsDir = "\(journeyDir)/screenshots"
    try? FileManager.default.createDirectory(
        atPath: screenshotsDir,
        withIntermediateDirectories: true
    )
    let pngPath = "\(screenshotsDir)/\(name).png"
    try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: pngPath))

    // 4. Append timing measurement to JSONL (real-time, one line per snap)
    let timingPath = "\(journeyDir)/screenshot-timing.jsonl"
    let escapedStatus = status.replacingOccurrences(of: "\"", with: "\\\"")
    let line = "{\"index\":\(screenshotIndex),\"name\":\"\(name)\",\"gap_seconds\":\(String(format: "%.1f", gap)),\"status\":\"\(escapedStatus)\"}\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: timingPath) {
            if let handle = FileHandle(forWritingAtPath: timingPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: timingPath, contents: data)
        }
    }
}
```

The `snap()` helper does three things on every call:
1. **Writes the .png file** to `journeys/{NNN}-{name}/screenshots/` immediately
2. **Attaches to xcresult** for Xcode/CI visibility
3. **Appends timing data** to `screenshot-timing.jsonl` — the gap since the last snap, flagged SLOW if > 3s

**In `setUpWithError()`**, clear the timing file so each run starts fresh:
```swift
// Clear previous timing data
let timingPath = "\(journeyDir)/screenshot-timing.jsonl"
try? FileManager.default.removeItem(atPath: timingPath)
```

The key: `screenshot-timing.jsonl` is written DURING the test, one line per screenshot. After the test finishes, the builder reads this file to find violations.

**Web (Playwright) — equivalent pattern:**
```typescript
let lastSnapTime = 0;
let snapIndex = 0;

async function snap(page: Page, name: string, journeyDir: string) {
  snapIndex++;
  const now = Date.now();
  const gap = lastSnapTime ? (now - lastSnapTime) / 1000 : 0;
  lastSnapTime = now;
  const status = gap > 3 ? 'SLOW' : 'ok';

  // 1. Write screenshot to disk
  const dir = `${journeyDir}/screenshots`;
  fs.mkdirSync(dir, { recursive: true });
  await page.locator('#app').screenshot({ path: `${dir}/${name}.png` });

  // 2. Append timing to JSONL
  const line = JSON.stringify({ index: snapIndex, name, gap_seconds: +gap.toFixed(1), status });
  fs.appendFileSync(`${journeyDir}/screenshot-timing.jsonl`, line + '\n');
}
```

### 3-second gap rule

Every gap between consecutive screenshots MUST be <= 3 seconds. The `snap()` helper writes each gap to `screenshot-timing.jsonl` in real-time. The journey-loop's **timing watcher** monitors this file and will **kill the test** if a SLOW entry is detected.

If the watcher kills your test, you will be restarted after the orchestrator investigates and fixes the slow gap. To avoid being killed:
- Keep all `waitForExistence` timeouts <= 3s unless the operation genuinely requires longer
- For unavoidable long waits (async downloads, app launch), pass `slowOK:` to the snap call: `snap("042-download-done", slowOK: "simulated download requires async completion")`. The watcher ignores `SLOW-OK` entries.
- Add intermediate screenshots inside long wait loops so no single gap exceeds 3s:
  ```swift
  // Break a 30s download wait into 3s chunks with progress screenshots
  for i in 0..<10 {
      if doneButton.waitForExistence(timeout: 3) { break }
      snap("042-download-progress-\(i)")
  }
  snap("043-download-done")
  ```

## Step 5: Run the test and enforce timing

Run only this test. Fix failures. Measure wall-clock time. Extract screenshots:

```bash
rm -rf /tmp/test-results.xcresult
time xcodebuild test \
  -project {Project}.xcodeproj \
  -scheme {UITestScheme} \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  -only-testing:{UITestTarget}/{TestClassName} \
  -resultBundlePath /tmp/test-results.xcresult \
  -quiet 2>&1
```

```bash
{skill-base-dir}/scripts/extract-screenshots.sh /tmp/test-results.xcresult journeys/{NNN}-{name}/screenshots
```

**Duration check:** If the test completes in under 10 minutes, go back to Step 3 and add more depth (new features, not repetition). Do NOT proceed to polish until the journey is substantial enough.

**Timing:** The journey-loop's watcher enforces the 3-second gap rule by monitoring `screenshot-timing.jsonl` in real-time. If your test is killed by the watcher, you'll be restarted after the gap is fixed. See the 3-second gap rule in Step 4.

## Step 6: Polish loop (3 rounds)

Run this loop 3 times (round 1, 2, 3). Each round does all three phases in order. Each phase produces a NEW timestamped file — never overwrite previous rounds.

### Phase A: Testability Review

Review app code touched by this journey. Check:
- ViewModels accept protocol dependencies via initializer injection
- Use Cases are framework-free (no UIKit/SwiftUI/AppKit imports)
- Side effects (network, disk, permissions) behind protocols
- DependencyContainer has a test factory with all-fake deps
- No shared mutable singletons
- State transitions are testable (given/when/then)

Fix issues: extract protocols, add DI, move logic out of Views. Write fast unit tests (< 1s total). Run them.

Write `journeys/{NNN}-{name}/testability_review_round{N}_{YYYY-MM-DD}_{HHMMSS}.md`.

### Phase B: Refactor UI test

Clean up the journey test code:
- Readable steps with helpers/page objects where needed
- **NEVER use `sleep()` or fixed-time waits to simulate user reading/thinking time.** Tests MUST complete as fast as possible. Always wait for elements (`waitForExistence(timeout:)`) or conditions instead. The only acceptable fixed wait is when no element/condition can be checked (e.g., animation with no completion signal), and even then keep it under 1 second.
- Accessibility identifiers on every interactive element

### Phase C: UI Review — Design-Driven

Read every screenshot in `journeys/{NNN}-{name}/screenshots/`. Review with both platform convention AND design quality lenses.

**Platform Conventions:**
- macOS: HIG compliance — toolbar, sidebar, window chrome, system colors
- Web: Responsive layout, standard navigation patterns, accessibility

**Design Quality:** Apply the `frontend-design` skill principles when reviewing. Evaluate typography, color, spatial composition, visual details, motion, and overall polish level. Flag anti-patterns like generic fonts, flat backgrounds, missing hover states, and unstyled empty states.

Fix all issues in the view code. Re-run the test. Extract fresh screenshots to `screenshots/`.

Write `journeys/{NNN}-{name}/ui_review_round{N}_{YYYY-MM-DD}_{HHMMSS}.md`.

**Round 3 is the final gate** — every screenshot must Pass or have issues explicitly deferred with justification.

## Step 7: Final verification + duration check

Run unit tests + this journey's UI test one last time. Both must pass.

Measure the final test duration. If still under 10 minutes after all polish rounds, add more steps and re-run.

## Step 8: Update journey state

Update `journey-state.md`:
- Set status to `polished` if test duration >= 10 minutes AND all tests pass
- Set status to `needs-extension` if test duration < 10 minutes
- **Record the ACTUAL measured wall-clock time** from the `xcodebuild test` run (e.g., `12m30s`). NEVER write estimated durations like `~5m`. If you didn't measure it, write `unmeasured` and treat status as `needs-extension`.
- Record the current date

## Step 9: Commit

New commit (never amend). Include: `journey.md`, all review files, all screenshots, updated `journey-state.md`. Message summarizes journey, fixes, features covered.

## Step 10: Report

Tell the user: which journey, how many steps, test duration, features covered, issues fixed across rounds, unit tests added, and what journey to work on next.

If any blockers were solved during this run, confirm that new pitfall files were added to the gist.

## Rules

- **Load pitfalls first** — Step 0 is not optional. Every session starts by reading the gist.
- **Add pitfalls for every blocker** — When you find a solution to a non-obvious problem, add it to the gist immediately via `gh gist edit`.
- **No sleep waits** — NEVER use `sleep()`, `Thread.sleep()`, or fixed-time waits to simulate user reading/thinking time. Use `waitForExistence(timeout:)` or condition-based waits. Tests must finish interactions as fast as possible. Only use a fixed wait (< 1s) when absolutely no element or condition can be checked.
- **3-second gap enforcement** — Every gap between consecutive screenshots must be <= 3s. The `snap()` helper writes `screenshot-timing.jsonl` in real-time. The journey-loop watcher monitors this file and kills the test on violations. Mark unavoidable long gaps with `// SLOW-OK: reason` before the snap call.
- **10-minute minimum** — A journey under 10 minutes is not done. Extend it by going deeper into the feature chain (new outcomes, new verifications), NEVER by repeating actions already tested. This is a HARD limit.
- **No repetitive padding** — NEVER repeat an interaction already performed to pad time. No cycling through the same cards multiple times. No navigating between the same tabs repeatedly. No typing multiple search queries that all produce the same result. Each interaction must test something the previous interactions didn't. If you catch yourself writing "round 2" or "again" in a comment, you are padding.
- **Actual durations only** — Never write estimated durations (e.g., `~5m`) to `journey-state.md`. Always measure from the real `xcodebuild test` run.
- **Work on existing journeys first** — Check `journey-state.md` before creating new ones.
- **NEVER mock test data in /tmp or anywhere** — Do NOT create fake fixture data programmatically in test `setUp()` methods (e.g., writing JSON files to `/tmp/` or `NSTemporaryDirectory()`). Instead:
  1. **Use earlier journeys to generate data.** Journey tests run in sequence. Earlier journeys (e.g., first-launch-setup, recording) should create real data through UI operations that later journeys can use.
  2. **Generate data like a real user would.** If a journey needs a recording to exist, a prior journey must have created it through the app's actual recording flow via the UI.
  3. **If UI-generated data is truly impossible** (e.g., the feature isn't built yet), you MAY add data programmatically BUT you MUST: (a) document it clearly in `journey.md` under a `## Programmatic Test Data` section explaining what was added and why UI generation wasn't possible, and (b) add a TODO to replace it with UI-generated data once the feature is available.
  4. **Journey ordering matters.** Design journey sequences so that data-producing journeys come before data-consuming journeys. The numbering (001, 002, 003...) defines execution order.
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
- **NEVER edit .xcodeproj manually** — always update `project.yml` and run `xcodegen generate`
