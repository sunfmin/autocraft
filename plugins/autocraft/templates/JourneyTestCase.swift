import XCTest

/// Base class for journey UI tests. Provides:
/// - `snap()` helper with timing measurement and disk-write
/// - `setUpJourney()` for common setup (clear timing, create dirs, launch app, ensure window)
/// - Snapshot-based batch element checking via `takeSnapshot()`
///
/// Usage:
/// ```swift
/// final class MyJourneyTests: JourneyTestCase {
///     override var journeyName: String { "001-first-launch-setup" }
///
///     override func setUpWithError() throws {
///         app.launchArguments = ["-hasCompletedSetup", "NO"]
///         try super.setUpWithError()
///     }
///
///     func test_MyJourney() throws {
///         let icon = app.images["myIcon"]
///         XCTAssertTrue(icon.waitForExistence(timeout: 10))
///         snap("001-initial", slowOK: "app launch")
///
///         // Batch-check elements without repeated tree fetches
///         let s = takeSnapshot()
///         if s.hasDescendant(id: "title") { snap("002-title") }
///         if s.hasDescendant(id: "button") { snap("003-button") }
///     }
/// }
/// ```
class JourneyTestCase: XCTestCase {

    let app = XCUIApplication()
    var screenshotIndex = 0
    var lastSnapTime: CFAbsoluteTime = 0

    /// Override this in subclasses to set the journey folder name.
    var journeyName: String { fatalError("Subclass must override journeyName") }

    /// Computed project root from #file at compile time.
    /// Override if your test file is not in the standard PercevUITests/ location.
    class var projectRoot: String {
        let filePath = URL(fileURLWithPath: #file)
        return filePath.deletingLastPathComponent().deletingLastPathComponent().path
    }

    var journeyDir: String {
        "\(Self.projectRoot)/journeys/\(journeyName)"
    }

    // MARK: - Setup

    override func setUpWithError() throws {
        continueAfterFailure = false

        // Clear timing file from previous runs
        let timingPath = "\(journeyDir)/screenshot-timing.jsonl"
        try? FileManager.default.removeItem(atPath: timingPath)

        // Create screenshots directory
        let screenshotsDir = "\(journeyDir)/screenshots"
        try? FileManager.default.createDirectory(
            atPath: screenshotsDir,
            withIntermediateDirectories: true
        )

        app.launch()

        // Ensure the app window is open — macOS may not auto-show the window
        if app.windows.count == 0 {
            app.typeKey("n", modifierFlags: .command)
        }
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - Snapshot (batch element checking)

    /// Take a snapshot of the current window for fast, batch element existence checks.
    /// Use `snapshot.hasDescendant(id:)` to check elements without additional tree fetches.
    ///
    /// ```swift
    /// let s = takeSnapshot()
    /// if s.hasDescendant(id: "title") { snap("010-title") }
    /// if s.hasDescendant(id: "subtitle") { snap("011-subtitle") }
    /// // ^ Both checks use the same snapshot — 1 tree fetch instead of 2
    /// ```
    func takeSnapshot() -> XCUIElementSnapshot {
        // swiftlint:disable:next force_try
        try! app.windows.firstMatch.snapshot()
    }

    // MARK: - Snap helper

    /// Takes a screenshot, writes it to disk, and logs timing.
    /// Pass `slowOK: "reason"` for steps with unavoidable delays > 3s.
    func snap(_ name: String, slowOK: String? = nil) {
        screenshotIndex += 1
        let now = CFAbsoluteTimeGetCurrent()
        let gap = lastSnapTime == 0 ? 0 : now - lastSnapTime
        lastSnapTime = now

        let status: String
        if gap <= 3 {
            status = "ok"
        } else if let reason = slowOK {
            status = "SLOW-OK: \(reason)"
        } else {
            status = "SLOW"
        }

        let screenshot = app.windows.firstMatch.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(journeyName)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let screenshotsDir = "\(journeyDir)/screenshots"
        try? FileManager.default.createDirectory(
            atPath: screenshotsDir,
            withIntermediateDirectories: true
        )
        let pngPath = "\(screenshotsDir)/\(name).png"
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: pngPath))

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
}
