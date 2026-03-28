---
name: preflight-permissions
description: >
  Pre-flight check for macOS app UI testing permissions. Sets up a self-signed code signing
  certificate (via macos-codesign), builds the app, detects required TCC permissions
  (Screen Recording, Microphone, Accessibility, Automation), guides the user to grant them,
  and verifies everything works before automated tests run. Use before running journey-builder
  or any XCUITest suite to prevent permission blockers during AI-driven development.
---

# Preflight Permissions

Ensure all macOS system permissions are granted before automated UI tests run. This prevents
XCUITests from hanging on permission dialogs or failing silently when TCC blocks access.

## When to Use

Run this skill **once** when starting a new project, after cloning, or whenever tests fail
with permission-related errors. It is a prerequisite for `journey-builder` and `journey-loop`.

## What It Does

1. Sets up a self-signed code signing certificate (so permissions persist across rebuilds)
2. Builds the app and test runner with that certificate
3. Detects which TCC permissions the app needs
4. Guides the user to grant each permission in System Settings
5. Runs a smoke XCUITest to verify permissions work
6. Reports pass/fail for each permission

---

## Step 1: Detect Project Configuration

Read `project.yml` (XcodeGen) or scan `*.xcodeproj` for:
- **App bundle ID** (e.g., `com.percev.app`)
- **UI test target name** (e.g., `PercevUITests`)
- **App target name** (e.g., `Percev`)
- **Existing `CODE_SIGN_IDENTITY`** — if already set to something other than `"-"`, skip certificate creation
- **Entitlements file** — check for existing entitlements

Report what was found before proceeding.

---

## Step 2: Create Self-Signed Certificate

Use the `/macos-codesign` skill approach. The certificate name MUST be `"{AppName} Dev"` (e.g., `"Percev Dev"`).

```bash
CERT_NAME="{AppName} Dev"

# Check if it already exists
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
  echo "Certificate '$CERT_NAME' already exists. Skipping creation."
else
  echo "Creating self-signed code signing certificate '$CERT_NAME'..."
  echo ">>> You may see a Keychain Access dialog — approve it once. <<<"

  cat > /tmp/cert.cfg <<CERT_EOF
[ req ]
distinguished_name = req_dn
[ req_dn ]
CN = $CERT_NAME
[ extensions ]
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
CERT_EOF

  openssl req -x509 -newkey rsa:2048 \
    -keyout /tmp/dev.key -out /tmp/dev.crt \
    -days 3650 -nodes \
    -config /tmp/cert.cfg -extensions extensions \
    -subj "/CN=$CERT_NAME" 2>/dev/null

  security import /tmp/dev.crt -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign 2>/dev/null
  security import /tmp/dev.key -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign 2>/dev/null
  security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db /tmp/dev.crt 2>/dev/null

  rm -f /tmp/cert.cfg /tmp/dev.key /tmp/dev.crt
  echo "Certificate '$CERT_NAME' created and trusted."
fi

# Verify it exists
security find-identity -v -p codesigning | grep "$CERT_NAME"
```

If the certificate was just created or `CODE_SIGN_IDENTITY` is `"-"`, update the project:

**If `project.yml` exists (XcodeGen):**
- Change `CODE_SIGN_IDENTITY: "-"` to `CODE_SIGN_IDENTITY: "{AppName} Dev"`
- Run `xcodegen generate` to regenerate the Xcode project

**If no `project.yml` (raw Xcode project):**
- Use `sed` or manual edit on the `.pbxproj` to set `CODE_SIGN_IDENTITY` to the certificate name

---

## Step 3: Build the App

Build the app target to produce a signed binary:

```bash
xcodebuild build \
  -project {Project}.xcodeproj \
  -scheme {AppName} \
  -destination 'platform=macOS' \
  -quiet \
  2>&1
```

If the build fails, diagnose and fix before continuing. Common issues:
- Certificate not trusted → re-run `security add-trusted-cert`
- Keychain locked → `security unlock-keychain ~/Library/Keychains/login.keychain-db`

---

## Step 4: Detect Required Permissions

Read the app's entitlements file and source code to determine which TCC permissions are needed:

| Permission | How to Detect | System Settings Path |
|-----------|--------------|---------------------|
| **Screen Recording** | Entitlement `com.apple.security.screen-capture` OR uses `ScreenCaptureKit`/`CGWindowList` | Privacy & Security > Screen Recording |
| **Microphone** | Entitlement `com.apple.security.device.audio-input` OR uses `AVCaptureDevice` for audio | Privacy & Security > Microphone |
| **Accessibility** | Uses `AXIsProcessTrusted()` or Accessibility APIs | Privacy & Security > Accessibility |
| **Automation** | XCUITest needs Accessibility access to control the app | Privacy & Security > Accessibility |

Also check:
- `grep -r "SCShareableContent\|SCStreamConfiguration\|CGWindowListCreate" {SourceDir}/` for Screen Recording
- `grep -r "AVCaptureDevice\|AVAudioSession\|microphone" {SourceDir}/` for Microphone
- `grep -r "AXIsProcessTrusted\|AXUIElement" {SourceDir}/` for Accessibility

Build a checklist of required permissions.

---

## Step 5: Guide User to Grant Permissions

For each required permission, tell the user exactly what to do:

```
=== PERMISSIONS NEEDED ===

The following permissions must be granted ONCE in System Settings.
After granting, they will persist across rebuilds (thanks to the code signing certificate).

1. [ ] Screen Recording
   → System Settings > Privacy & Security > Screen Recording
   → Add: {AppName} (find it in the app list or use "+")

2. [ ] Microphone
   → System Settings > Privacy & Security > Microphone
   → Toggle ON for {AppName}

3. [ ] Accessibility (for XCUITest automation)
   → System Settings > Privacy & Security > Accessibility
   → Add: Xcode (if not already present)
   → Add: {AppName}

Open System Settings now:
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
```

**IMPORTANT:** Open each relevant System Settings pane automatically using `open` commands. Wait for the user to confirm they've granted permissions before proceeding.

Launch the app once so it appears in the TCC permission lists:

```bash
# Find and launch the built app briefly so macOS registers it
APP_PATH=$(xcodebuild -scheme {AppName} -showBuildSettings 2>/dev/null | \
  grep ' BUILT_PRODUCTS_DIR' | xargs | cut -d= -f2)/{AppName}.app
open "$APP_PATH"
sleep 3
osascript -e 'tell application "{AppName}" to quit'
```

---

## Step 6: Verify with Smoke Test

Write a minimal XCUITest that exercises permission-dependent features:

```swift
import XCTest

final class PermissionSmokeTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func testAppLaunchesAndWindowExists() throws {
        // Verify the app launches without permission dialogs blocking it
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10),
                      "App window should appear — if stuck, check Accessibility permission")

        // Take a screenshot to verify no permission dialog is blocking
        let screenshot = window.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "preflight-001-app-launched"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNoPermissionDialogsOnScreen() throws {
        // Check that no system dialog is blocking the app
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        // If a permission dialog appears, it means permissions weren't granted
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        XCTAssertFalse(alert.waitForExistence(timeout: 3),
                       "Permission dialog detected — grant the permission in System Settings first")
    }
}
```

Place this test in the UI test target if it doesn't already exist. Run it:

```bash
xcodebuild test \
  -project {Project}.xcodeproj \
  -scheme {UITestScheme} \
  -destination 'platform=macOS' \
  -only-testing:{UITestTarget}/PermissionSmokeTests \
  -resultBundlePath /tmp/preflight-results.xcresult \
  -quiet \
  2>&1
```

---

## Step 7: Report

Output a clear status report:

```
=== PREFLIGHT PERMISSIONS REPORT ===

Certificate:      ✅ {AppName} Dev (persists across rebuilds)
Build:            ✅ Signed with {AppName} Dev
Screen Recording: ✅ Granted  (or ❌ NOT granted — tests will hang)
Microphone:       ✅ Granted  (or ⚠️ Not needed / ❌ NOT granted)
Accessibility:    ✅ Granted  (or ❌ NOT granted — XCUITest will fail)
Smoke Test:       ✅ Passed   (or ❌ Failed — see errors above)

Status: READY FOR AUTOMATED TESTING
  (or: BLOCKED — fix the items marked ❌ above)
```

If all checks pass, the project is ready for `journey-builder` and `journey-loop`.

---

## Rules

- NEVER skip the certificate step — ad-hoc signing causes permission revocation on every rebuild
- NEVER try to programmatically grant TCC permissions — only the user can do this in System Settings
- ALWAYS open the relevant System Settings pane automatically for the user
- ALWAYS launch the app once before asking the user to grant permissions (so it appears in TCC lists)
- ALWAYS run the smoke test to verify — don't trust "I granted it" without a passing test
- If the smoke test fails, diagnose whether it's a permission issue or a build issue before asking the user to re-grant
- This skill modifies `project.yml` and/or build settings — commit these changes so the team benefits
