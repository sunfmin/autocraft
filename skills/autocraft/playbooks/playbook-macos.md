# macOS Playbook — Xcode, SwiftUI, XCUITest, ScreenCaptureKit

All rules in this file are non-negotiable. Violating them causes the Orchestrator to reject your work and re-launch you.

---

# Table of Contents

1. [XcodeGen Pitfalls](#xcodegen-pitfalls)
2. [Code Signing](#code-signing)
3. [SwiftUI Pitfalls](#swiftui-pitfalls)
4. [macOS UI Testing Approach](#macos-ui-testing-approach)
5. [Never Simulate App Features](#never-simulate-app-features)
6. [Inspector: ANSI Garbage](#inspector-ansi-garbage)
7. [Architecture Guide](#architecture-guide)
8. [Architecture Reference](#architecture-reference)
9. [Role: Builder (macOS)](#role-builder-macos)
10. [Role: Tester (macOS)](#role-tester-macos)
11. [Role: Inspector (macOS)](#role-inspector-macos)
12. [Role: Orchestrator (macOS)](#role-orchestrator-macos)

---

# XcodeGen Pitfalls

## Never Edit .xcodeproj Manually

### Problem
Manual edits to Xcode project settings get lost or cause conflicts.

### Solution
ALL build settings must go through `project.yml`:

```bash
# Edit project.yml, then:
xcodegen generate
```

### Why
When using XcodeGen, `.xcodeproj` is a generated artifact. Running `xcodegen generate` overwrites all manual changes. Never use Xcode GUI to change Build Settings, never use `sed`/`awk` on `.pbxproj` files.

## UI Test Target: BUNDLE_LOADER Must Be Empty

### Problem
`codesign` fails with "bundle format unrecognized, invalid, or unsuitable" pointing at `.../PlugIns/Tests.xctest`.

### Solution
Override both settings to empty in `project.yml` for UI test targets:

```yaml
  MyAppUITests:
    type: bundle.ui-testing
    dependencies:
      - target: MyApp
    settings:
      base:
        BUNDLE_LOADER: ""
        TEST_HOST: ""
        CODE_SIGN_IDENTITY: "MyApp Dev"
        CODE_SIGNING_ALLOWED: "YES"
        CODE_SIGN_STYLE: "Manual"
```

Then: `xcodegen generate` and clean DerivedData if stale:
`rm -rf ~/Library/Developer/Xcode/DerivedData/MyApp-*`

### Why
XcodeGen auto-adds `BUNDLE_LOADER = "$(TEST_HOST)"` to UI test targets (`bundle.ui-testing`) when they depend on an app target. This is WRONG — `BUNDLE_LOADER`/`TEST_HOST` are for unit tests only.

---

# Code Signing

## Self-Signed Certificate & Hardened Runtime

### Problem
macOS revokes Screen Recording, Microphone, and Accessibility permissions after every rebuild.

### Solution

#### Create a Self-Signed Certificate

```bash
CERT_NAME="MyApp Dev"

if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
  cat > /tmp/cert.cfg <<EOF
[ req ]
distinguished_name = req_dn
[ req_dn ]
CN = $CERT_NAME
[ extensions ]
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
EOF

  openssl req -x509 -newkey rsa:2048 \
    -keyout /tmp/dev.key -out /tmp/dev.crt \
    -days 3650 -nodes \
    -config /tmp/cert.cfg -extensions extensions \
    -subj "/CN=$CERT_NAME" 2>/dev/null

  security import /tmp/dev.crt -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign 2>/dev/null
  security import /tmp/dev.key -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign 2>/dev/null
  security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db /tmp/dev.crt 2>/dev/null
  rm -f /tmp/cert.cfg /tmp/dev.key /tmp/dev.crt
fi
```

#### Configure project.yml

```yaml
settings:
  base:
    CODE_SIGN_IDENTITY: "MyApp Dev"
    CODE_SIGNING_ALLOWED: "YES"
    CODE_SIGN_STYLE: "Manual"
    ENABLE_HARDENED_RUNTIME: "NO"
```

Then: `xcodegen generate`. Launch app once, grant permissions — they persist across rebuilds.

### Why
Ad-hoc signing produces a different signature hash on every build. A persistent self-signed certificate keeps the same identity. Hardened runtime enforces strict validation that self-signed certs cannot satisfy.

---

# SwiftUI Pitfalls

## Use Button, Not onTapGesture

XCUITest cannot reliably click views using `.onTapGesture`. Wrap every tappable element in a `Button` with `.buttonStyle(.plain)`.

## Never Put .accessibilityIdentifier on Container Views

SwiftUI propagates a container's identifier to ALL children, replacing their individual identifiers. Only add `.accessibilityIdentifier()` to LEAF elements: Text, Button, Image, TextField, Toggle.

## Accessibility Identifier Naming Convention

| Element Type | Pattern | Example |
|-------------|---------|---------|
| TextField | `{purpose}TextField` | `terminalInputTextField` |
| Button | `{action}Button` | `startRecordingButton` |
| Toggle | `{feature}Toggle` | `autoSaveToggle` |
| Preview | `{content}Preview` | `videoPreview` |

Use `app.descendants(matching: .any)["myId"]` for element lookup.

---

# macOS UI Testing Approach

macOS UI acceptance criteria go through **Mode B journeys** — natural-language `journey.md` executed by a separate Claude instance with vision via the `driving-macos-with-wda-vision` skill (WebDriverAgentMac + Appium + `mac2.sh`). There is no XCUITest UI test target, no in-process test harness.

Only pure-Swift integration tests (service layer, repositories, value logic) run as XCTest — these do not launch or drive the UI.

---

# Never Simulate App Features

Never create `Simulated{Feature}Repository`, `Fake{Feature}`, or `Mock{Feature}` in production code. Every service must use real framework APIs:
- Window enumeration → ScreenCaptureKit (not hardcoded window list)
- Model inference → real ML framework (not `Thread.sleep()` + canned output)
- Media playback → AVPlayer (not a static image)

If a real API requires permissions or hardware that blocks progress, use `/attack-blocker`. The only acceptable test doubles are in unit tests (never in the running app).

Scan for `Simulated*`, `Fake*`, `Mock*` (outside test targets) as a red flag.

---

# Inspector: ANSI Garbage

For any screenshot containing terminal/console output:
1. Look for patterns like `[0m`, `[1m`, `[27m`, `[K`, `[?2004h`, `[38;5;`
2. If found: **FAIL** — "Terminal output contains raw escape codes."
3. Automatic FAIL regardless of acceptance criteria

When reviewing screenshots, ask "does this look like something a user would ship?" — not just "does this satisfy the checklist."

---

# Architecture Guide

## When to Use Which Repository

| Category | When to Use | Examples |
|----------|-------------|---------|
| **OpenAPI Repositories** | Data that may sync with a remote server | Notes, Folders, Users |
| **Direct CoreData Repositories** | Local-only data | Settings, Cache, Drafts |

## Swift Concurrency Rules

| Type | @MainActor? | async throws? |
|------|-------------|---------------|
| ViewModels | YES | Methods use `Task { }` |
| DependencyContainer | YES | N/A |
| Use Cases | NO | YES |
| Repositories | NO | YES |

## Layer Dependency Rule

```
Presentation → Data → Domain → Entities
```

Inner layers MUST NOT import outer layers. All boundaries are Swift protocols.

---

# Architecture Reference

## 4-Layer Structure

```
Presentation (SwiftUI Views, ViewModels, Coordinators)
    ↓
Data (Repositories, Network, Database, DTOs)
    ↓
Domain (Use Cases, Repository Protocols, Domain Services)
    ↓
Entities (Business Objects, Value Objects, Pure Swift)
```

### SOLID Principles
- **Single Responsibility**: Each Use Case = one operation. Each ViewModel = one screen.
- **Open-Closed**: Extend through new conformances, not modification.
- **Interface Segregation**: Small, focused protocols.
- **Dependency Inversion**: High-level modules depend on abstractions.

## SwiftUI API Availability

| API | iOS | macOS |
|-----|-----|-------|
| `NavigationStack` | 16.0 | 13.0 |
| `navigationDestination(item:)` | 17.0 | 14.0 |
| `@Observable` | 17.0 | 14.0 |
| `TextEditor` | 14.0 | 11.0 |
| `.searchable` | 15.0 | 12.0 |
| `Inspector` | 17.0 | 14.0 |
| `ContentUnavailableView` | 17.0 | 14.0 |

---

# Role: Builder (macOS)

## Dependency Integration
- **SPM** — preferred for Swift libraries
- **Carthage** — for frameworks without SPM
- **Vendored** — for C libraries (whisper.cpp, etc.)

Always verify with `xcodebuild build`.

## Artifact Verification

```bash
# Audio must be non-trivial (>1KB)
find ~/<AppName> -name "audio.m4a" -size +1k 2>/dev/null | head -3

# Transcript must have content
find ~/<AppName> -name "transcript.jsonl" ! -empty 2>/dev/null | head -3

# Video must have content
find ~/<AppName> -name "video.mp4" -size +10k 2>/dev/null | head -3
```

## Logging
Use `os_log` with `%{public}@`, never `print()`.

---

# Role: Tester (macOS)

## UI Criteria → Mode B Journeys (No XCTest Code)

Mode B criteria are verified by running `journey.md` through the `driving-macos-with-wda-vision` skill (spawn a fresh Claude instance with `claude -p`). Do NOT write XCTest / XCUITest code for UI verification. The journey markdown IS the test.

## Integration Criteria → XCTest

Mode A criteria for pure-Swift code (service layer, repositories, parsers, value logic) run as XCTest unit/integration tests that do not launch the UI. Subclass `XCTestCase` directly.

## Forbidden Guard Patterns (Swift)

**FORBIDDEN** (silently skip):
```swift
guard let result = action() else { return }
if let dir = findDirectory() { XCTAssertTrue(...) }
```

**ALLOWED** (fail loudly):
```swift
guard let result = action() else { XCTFail("action() returned nil"); return }
let dir = findDirectory()
XCTAssertFalse(dir.isEmpty, "findDirectory() must return a non-empty path")
```

## Behavioral Assertion Pattern (Mode A, before/after)

```swift
let before = service.currentState()
service.performAction(input)
let after = service.currentState()
XCTAssertNotEqual(before, after, "AC2: state must change after performAction")
XCTAssertTrue(after.contains(expectedToken), "AC2: new state must contain expected token")
```

A change check alone is insufficient (passes for errors too). A content check without a change check does not prove the action caused it. Both are required for `behavioral` assertions.

## Real Test Content

| Feature | How |
|---------|-----|
| Audio processing | `say "test content"` to generate real audio files |
| Transcription | `say` known text → feed to service → assert contains |

## Bypass Flag Ban

BANNED: `-generateTestTranscript`, `-useTestDownloads`, `-useFakeData`. Only state config flags allowed (e.g., `-hasCompletedSetup YES`).

## Adding New Test Files

When adding a new `.swift` file to a test target, run `xcodegen generate` to regenerate the `.xcodeproj`. The `sources:` directive in `project.yml` auto-discovers all `.swift` files in that directory, but only after regeneration.

---

# Role: Inspector (macOS)

## Scan 1 — Output Artifacts

```bash
echo "=== Empty audio files ==="
find ~/<AppName> -name "audio.m4a" -size -1k 2>/dev/null
echo "=== Empty transcripts ==="
find ~/<AppName> -name "transcript.jsonl" -empty 2>/dev/null
echo "=== Empty video files ==="
find ~/<AppName> -name "video.mp4" -size -10k 2>/dev/null
```

ANY result = **FAIL**.

## Scan 2 — Bypass Flags

```bash
grep -rn "generateTestTranscript\|useTestDownloads\|useFakeData" . --include="*.swift"
```

## Scan 3 — Stub Functions

```bash
grep -rn 'return ""$\|return \[\]$' . --include="*.swift" | grep -v "Tests\|guard\|else\|catch\|//"
```

## Scan 4 — Vacuous Assertions

```bash
grep -rn "XCTAssertTrue.*||" . --include="*.swift" | grep "Tests"
```

## Platform-Specific Visual Defects

Watch for ANSI escape codes, SwiftUI rendering artifacts, macOS permission dialogs.

---

# Role: Orchestrator (macOS)

## Pre-Build Simulation Scan

```bash
echo "=== Bypass flags in tests ==="
grep -rn "generateTestTranscript\|useTestDownloads\|useFakeData" . --include="*.swift" || echo "CLEAN"

echo "=== Stub functions in production ==="
grep -rn 'return ""$\|return \[\]$' . --include="*.swift" | grep -v "Tests\|test\|guard\|else\|catch" || echo "CLEAN"

echo "=== Test data generators in production ==="
grep -rn "testSentences\|generateTest\|hardcodedSegments" . --include="*.swift" | grep -v "Tests" || echo "CLEAN"
```

## Contract Compliance Validation (Mode A XCTest files)

```bash
TEST_FILE="<path/to/IntegrationTestFile>.swift"

echo "=== Silent Skips ==="
grep -n 'if let.*= .*{' "$TEST_FILE" | grep -v "// optional\|cleanup\|Cleanup\|delete\|Delete" || echo "CLEAN"

echo "=== Tautological Assertions ==="
grep -n 'XCTAssert.*||' "$TEST_FILE" || echo "CLEAN"

echo "=== Architecture Claims ==="
grep -n 'architectur' "$TEST_FILE" || echo "CLEAN"
```

## Test Contract: Platform Mappings

| Generic concept | Swift / XCTest equivalent |
|----------------|--------------------------|
| `FAIL(message)` | `XCTFail(message)` |
| Content assertion | `XCTAssertTrue(value.contains(...))` |
| Change detection | `XCTAssertNotEqual(before, after)` |
| Test file extension | `.swift` |
| Test directory pattern | `*Tests/` |
