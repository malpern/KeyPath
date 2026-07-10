import AppKit
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

/// Standard sizes for documentation screenshots. All include consistent
/// 20px padding via `assertDocScreenshot`.
enum DocSize {
    /// Settings subpanel (sliders, toggles, pickers) — 650×320
    static let subpanel = CGSize(width: 650, height: 320)
    /// Taller subpanel (per-finger sliders, expanded settings) — 650×500
    static let subpanelTall = CGSize(width: 650, height: 500)
    /// Pack detail dialog — use pack.preferredDetailWidth × 800
    static func packDetail(width: CGFloat) -> CGSize {
        CGSize(width: width, height: 800)
    }

    /// Settings tab (Rules, General, etc.) — 680×700
    static let settingsTab = CGSize(width: 680, height: 700)
    /// Full overlay + inspector composite — 1400×800
    static let fullWindow = CGSize(width: 1400, height: 800)
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
    let standardDefaults = Foundation.UserDefaults()
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
    standardDefaults.removePersistentDomain(forName: suiteName + ".standard")
    for (key, value) in baseDefaults.merging(defaults, uniquingKeysWith: { _, new in new }) {
        standardDefaults.set(value, forKey: key)
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
    colorScheme: ColorScheme = .light,
    defaults: UserDefaults
) -> NSView {
    let hosted = NSHostingView(
        rootView: view
            .environment(\.colorScheme, colorScheme)
            .defaultAppStorage(defaults)
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
    /// Render snapshots at retina-like density for crisper UI text.
    /// This avoids soft 1x offscreen AppKit rendering.
    private let snapshotScale: CGFloat = 2.0

    /// Upper bound so generated assets stay practical for docs/web payload size.
    private let maxSnapshotPixelsWide = 1800
    private nonisolated(unsafe) var originalHomeEnv: String?
    private nonisolated(unsafe) var originalFixedHomeEnv: String?
    private nonisolated(unsafe) var isolatedHomeDirectory: URL?
    private nonisolated(unsafe) var snapshotDefaults: UserDefaults?
    private nonisolated(unsafe) var snapshotDefaultsSuiteName: String?

    /// Rasterize a hosted view into an NSImage at explicit scale.
    private func rasterizedImage(from view: NSView, size: CGSize) -> NSImage {
        let effectiveScale = min(snapshotScale, CGFloat(maxSnapshotPixelsWide) / max(1, size.width))
        let pixelsWide = max(1, Int((size.width * effectiveScale).rounded()))
        let pixelsHigh = max(1, Int((size.height * effectiveScale).rounded()))

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = size

        view.frame = CGRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        view.cacheDisplay(in: view.bounds, to: rep)

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard snapshotsEnabled || isRecordingMode else {
            throw XCTSkip("Snapshot tests disabled. Set KEYPATH_SNAPSHOTS=1 to enable.")
        }
        originalHomeEnv = ProcessInfo.processInfo.environment["HOME"]
        originalFixedHomeEnv = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"]
        let isolatedHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("keypath-snapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: isolatedHome, withIntermediateDirectories: true)
        isolatedHomeDirectory = isolatedHome
        setenv("HOME", isolatedHome.path, 1)
        setenv("CFFIXED_USER_HOME", isolatedHome.path, 1)

        // Give every test its own @AppStorage domain. Mutating
        // UserDefaults.standard after SwiftUI has initialized is not sufficient:
        // @AppStorage may retain the process-wide standard store and leak the
        // developer's real preferences into reference images.
        let suiteName = "com.keypath.snapshot-tests.\(UUID().uuidString)"
        let defaultsStore = UserDefaults(suiteName: suiteName)!
        snapshotDefaults = defaultsStore
        snapshotDefaultsSuiteName = suiteName

        let defaults: [String: Any] = [
            "selectedKeymapId": "qwerty-us",
            "keymapIncludePunctuation": "true",
            "selectedLayoutId": "ansi-100",
            "overlayColorwayId": "default",
            "KeyPath.Overlay.UnmappedLayerKeyStyle": "baseLayer",
            "inspectorSettingsSection": "keymaps",
            "launcherWelcomeSeenForBuild": "999",
        ]
        for (key, value) in defaults {
            defaultsStore.set(value, forKey: key)
        }
    }

    override func tearDown() {
        if let snapshotDefaultsSuiteName {
            snapshotDefaults?.removePersistentDomain(forName: snapshotDefaultsSuiteName)
        }
        if let originalHomeEnv {
            setenv("HOME", originalHomeEnv, 1)
        } else {
            unsetenv("HOME")
        }
        if let originalFixedHomeEnv {
            setenv("CFFIXED_USER_HOME", originalFixedHomeEnv, 1)
        } else {
            unsetenv("CFFIXED_USER_HOME")
        }
        if let isolatedHomeDirectory {
            try? FileManager.default.removeItem(at: isolatedHomeDirectory)
        }
        originalHomeEnv = nil
        originalFixedHomeEnv = nil
        isolatedHomeDirectory = nil
        snapshotDefaults = nil
        snapshotDefaultsSuiteName = nil
        super.tearDown()
    }

    /// Assert a documentation screenshot with consistent dark mode styling.
    /// Wraps the view in 20px padding + windowBackgroundColor, renders in dark mode.
    /// Height auto-sizes to content (capped at `size.height`). A single hosting
    /// view is used for both measurement and capture so `onAppear` state settles.
    func assertDocScreenshot(
        of view: some View,
        size: CGSize,
        named name: String,
        precision: Float = 0.98,
        perceptualPrecision: Float = 0.98,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let wrapped = view
            .fixedSize(horizontal: false, vertical: true)
            .padding(20)
            .frame(maxWidth: size.width)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
            .defaultAppStorage(requiredSnapshotDefaults)

        let host = NSHostingView(rootView: wrapped)
        host.frame = CGRect(origin: .zero, size: CGSize(width: size.width, height: 10000))
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        host.layoutSubtreeIfNeeded()

        let fittingHeight = min(host.fittingSize.height, size.height)
        let renderSize = CGSize(width: size.width, height: max(fittingHeight, 100))

        let rendered = rasterizedImage(from: host, size: renderSize)
        let strategy = appKitPNGStrategy(
            precision: precision,
            perceptualPrecision: perceptualPrecision
        )

        if isRecordingMode {
            assertSnapshot(of: rendered, as: strategy, named: name, record: true,
                           file: file, testName: testName, line: line)
        } else {
            assertSnapshot(of: rendered, as: strategy, named: name,
                           file: file, testName: testName, line: line)
        }
    }

    /// Assert snapshot with standard configuration.
    /// In recording mode (SNAPSHOT_RECORD=1), generates new reference images.
    /// Use `precision` < 1.0 for views with non-deterministic content (e.g., app icons).
    func assertScreenshot(
        of view: some View,
        size: CGSize,
        named name: String,
        precision: Float = 0.98,
        perceptualPrecision: Float = 0.98,
        colorScheme: ColorScheme = .light,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let hosted = hostView(
            view,
            size: size,
            colorScheme: colorScheme,
            defaults: requiredSnapshotDefaults
        )
        hosted.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        hosted.layoutSubtreeIfNeeded()
        let rendered = rasterizedImage(from: hosted, size: size)
        let strategy = appKitPNGStrategy(
            precision: precision,
            perceptualPrecision: perceptualPrecision
        )

        if isRecordingMode {
            assertSnapshot(
                of: rendered,
                as: strategy,
                named: name,
                record: true,
                file: file,
                testName: testName,
                line: line
            )
        } else {
            assertSnapshot(
                of: rendered,
                as: strategy,
                named: name,
                file: file,
                testName: testName,
                line: line
            )
        }
    }

    private var requiredSnapshotDefaults: UserDefaults {
        guard let snapshotDefaults else {
            preconditionFailure("Snapshot defaults accessed before test setup")
        }
        return snapshotDefaults
    }
}

// MARK: - Stable AppKit PNG Diffing

/// SnapshotTesting's tolerant NSImage strategy uses Core Image's CILabDeltaE
/// filter. On current macOS/Xcode that filter can raise an Objective-C exception
/// (`CGRectValue` sent to NSConcreteValue) and crash xctest. Keep rendering in
/// AppKit, but compare decoded RGBA pixels without Core Image.
private func appKitPNGStrategy(
    precision: Float,
    perceptualPrecision: Float
) -> Snapshotting<NSImage, Data> {
    Snapshotting<NSImage, Data>(
        pathExtension: "png",
        diffing: .diff(
            toData: { $0 },
            fromData: { $0 }
        ) { reference, candidate in
            guard let old = rgbaPixels(fromPNG: reference),
                  let new = rgbaPixels(fromPNG: candidate)
            else {
                return ("Snapshot PNG could not be decoded.", [])
            }
            guard old.width == new.width, old.height == new.height else {
                return (
                    "New snapshot size \(new.width)x\(new.height) does not match reference \(old.width)x\(old.height).",
                    []
                )
            }

            let channelTolerance = UInt8(
                min(255, max(0, ((1 - perceptualPrecision) * 255).rounded(.up)))
            )
            var differentPixels = 0
            for pixelOffset in stride(from: 0, to: old.bytes.count, by: 4) {
                let differs = (0 ..< 4).contains { channel in
                    abs(Int(old.bytes[pixelOffset + channel]) - Int(new.bytes[pixelOffset + channel]))
                        > Int(channelTolerance)
                }
                if differs { differentPixels += 1 }
            }

            let totalPixels = max(1, old.width * old.height)
            let actualPrecision = 1 - Float(differentPixels) / Float(totalPixels)
            guard actualPrecision < precision else { return nil }
            return (
                "Actual pixel precision \(actualPrecision) is less than required \(precision) (channel tolerance \(channelTolerance)/255).",
                []
            )
        },
        snapshot: { image in
            pngData(from: image) ?? Data()
        }
    )
}

private func pngData(from image: NSImage) -> Data? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }
    let representation = NSBitmapImageRep(cgImage: cgImage)
    representation.size = image.size
    return representation.representation(using: .png, properties: [:])
}

private func rgbaPixels(fromPNG data: Data) -> (width: Int, height: Int, bytes: [UInt8])? {
    guard let image = NSImage(data: data),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        return nil
    }

    let width = cgImage.width
    let height = cgImage.height
    let bytesPerRow = width * 4
    var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
    let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let baseAddress = buffer.baseAddress,
              let context = CGContext(
                  data: baseAddress,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            return false
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return rendered ? (width, height, bytes) : nil
}
