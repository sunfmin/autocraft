import XCTest

/// Base class for journey UI tests. Provides:
/// - `snap()` helper with dedup, timing measurement, and disk-write
/// - Setup: clears timing, creates dirs, launches app, ensures window
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
///     }
/// }
/// ```
class JourneyTestCase: XCTestCase {

    let app = XCUIApplication()
    var screenshotIndex = 0
    var lastSnapTime: CFAbsoluteTime = 0
    private var lastPngData: Data?

    /// Override this in subclasses to set the journey folder name.
    var journeyName: String { fatalError("Subclass must override journeyName") }

    /// Computed project root from #file at compile time.
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

        let timingPath = "\(journeyDir)/screenshot-timing.jsonl"
        try? FileManager.default.removeItem(atPath: timingPath)

        let screenshotsDir = "\(journeyDir)/screenshots"
        try? FileManager.default.createDirectory(
            atPath: screenshotsDir,
            withIntermediateDirectories: true
        )

        app.launch()

        // macOS may not auto-show the window
        if app.windows.count == 0 {
            app.typeKey("n", modifierFlags: .command)
        }
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - Snap helper

    /// Takes a screenshot, writes it to disk, and logs timing.
    /// Skips writing if the screenshot is identical to the previous one.
    /// Pass `slowOK: "reason"` for steps with unavoidable delays > 3s.
    func snap(_ name: String, slowOK: String? = nil) {
        let now = CFAbsoluteTimeGetCurrent()
        let gap = lastSnapTime == 0 ? 0 : now - lastSnapTime

        let screenshot = app.windows.firstMatch.screenshot()
        let pngData = screenshot.pngRepresentation

        // Skip if identical to previous screenshot
        if let last = lastPngData, last == pngData {
            return
        }
        lastPngData = pngData

        screenshotIndex += 1
        lastSnapTime = now

        let status: String
        if gap <= 3 {
            status = "ok"
        } else if let reason = slowOK {
            status = "SLOW-OK: \(reason)"
        } else {
            status = "SLOW"
        }

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
        try? pngData.write(to: URL(fileURLWithPath: pngPath))

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
