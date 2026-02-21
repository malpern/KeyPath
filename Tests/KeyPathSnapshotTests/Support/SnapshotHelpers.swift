@testable import KeyPathAppKit
import SnapshotTesting
import SwiftUI
import XCTest

// MARK: - Snapshot Configuration

/// Standard frame sizes for different view categories.
enum SnapshotSize {
    /// Small card components (KeymapCard, AppRuleCard)
    static let card = CGSize(width: 420, height: 300)
    /// Medium panels (HomeRowTimingSection, CustomRulesInlineEditor)
    static let panel = CGSize(width: 600, height: 525)
    /// Large panels (OverlayInspectorPanel, OverlayLaunchersSection)
    static let inspector = CGSize(width: 750, height: 900)
    /// Full overlay header
    static let header = CGSize(width: 900, height: 60)
    /// Launcher drawer
    static let drawer = CGSize(width: 450, height: 750)
    /// Layout picker grid
    static let grid = CGSize(width: 750, height: 1050)
}

// MARK: - Isolated UserDefaults

/// Creates an isolated UserDefaults suite for @AppStorage testing.
/// Prevents snapshot tests from reading/writing the real user defaults.
func withIsolatedDefaults(
    suiteName: String = "com.keypath.snapshot-tests",
    defaults: [String: Any] = [:],
    body: () throws -> Void
) rethrows {
    let suite = UserDefaults(suiteName: suiteName)!
    suite.removePersistentDomain(forName: suiteName)

    // Set known defaults for @AppStorage keys
    let baseDefaults: [String: Any] = [
        "selectedKeymapId": "qwerty-us",
        "keymapIncludePunctuation": "true",
        "selectedLayoutId": "ansi-100",
        "overlayColorwayId": "default",
        "inspectorSettingsSection": "keymaps",
        "launcherWelcomeSeenForBuild": "999",
    ]

    for (key, value) in baseDefaults.merging(defaults, uniquingKeysWith: { _, new in new }) {
        suite.set(value, forKey: key)
    }

    // Swap standard defaults
    UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
    for (key, value) in baseDefaults.merging(defaults, uniquingKeysWith: { _, new in new }) {
        UserDefaults.standard.set(value, forKey: key)
    }

    defer {
        suite.removePersistentDomain(forName: suiteName)
    }

    try body()
}

// MARK: - View Hosting

/// Wraps a SwiftUI view in a fixed-size NSHostingView for snapshot capture.
@MainActor
func hostView(
    _ view: some View,
    size: CGSize,
    colorScheme: ColorScheme = .light
) -> NSView {
    let hosted = NSHostingView(
        rootView: view
            .environment(\.colorScheme, colorScheme)
            .frame(width: size.width, height: size.height)
    )
    hosted.frame = CGRect(origin: .zero, size: size)
    return hosted
}

// MARK: - Screenshot Output

/// Whether snapshot tests are enabled.
/// Set `KEYPATH_SNAPSHOTS=1` to run. Skipped by default during normal `swift test`.
var snapshotsEnabled: Bool {
    ProcessInfo.processInfo.environment["KEYPATH_SNAPSHOTS"] == "1"
}

/// Whether we're in recording mode (regenerating reference images).
/// Set `SNAPSHOT_RECORD=1` environment variable to enable.
/// Implies KEYPATH_SNAPSHOTS=1 (recording always enables tests).
var isRecordingMode: Bool {
    ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
}

/// Base class for screenshot snapshot tests.
/// Skips all tests unless KEYPATH_SNAPSHOTS=1 or SNAPSHOT_RECORD=1 is set.
/// Provides common setup including UserDefaults isolation.
@MainActor
class ScreenshotTestCase: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        guard snapshotsEnabled || isRecordingMode else {
            throw XCTSkip("Snapshot tests disabled. Set KEYPATH_SNAPSHOTS=1 to enable.")
        }
        // Ensure deterministic @AppStorage state
        let defaults: [String: Any] = [
            "selectedKeymapId": "qwerty-us",
            "keymapIncludePunctuation": "true",
            "selectedLayoutId": "ansi-100",
            "overlayColorwayId": "default",
            "inspectorSettingsSection": "keymaps",
            "launcherWelcomeSeenForBuild": "999",
        ]
        for (key, value) in defaults {
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    override func tearDown() {
        // Clean up test defaults
        let keys = [
            "selectedKeymapId",
            "keymapIncludePunctuation",
            "selectedLayoutId",
            "overlayColorwayId",
            "inspectorSettingsSection",
            "launcherWelcomeSeenForBuild",
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    /// Assert snapshot with standard configuration.
    /// In recording mode (SNAPSHOT_RECORD=1), generates new reference images.
    /// Use `precision` < 1.0 for views with non-deterministic content (e.g., app icons).
    func assertScreenshot(
        of view: some View,
        size: CGSize,
        named name: String,
        precision: Float = 1.0,
        perceptualPrecision: Float = 1.0,
        colorScheme: ColorScheme = .light,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let hosted = hostView(view, size: size, colorScheme: colorScheme)
        let strategy: Snapshotting<NSView, NSImage> = .image(
            precision: precision,
            perceptualPrecision: perceptualPrecision
        )

        if isRecordingMode {
            assertSnapshot(
                of: hosted,
                as: strategy,
                named: name,
                record: true,
                file: file,
                testName: testName,
                line: line
            )
        } else {
            assertSnapshot(
                of: hosted,
                as: strategy,
                named: name,
                file: file,
                testName: testName,
                line: line
            )
        }
    }
}
