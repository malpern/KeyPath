import Foundation
import KeyPathCore

/// Finds other copies of KeyPath.app on this Mac.
///
/// Extra copies confuse macOS (Login Items and privacy grants can attach to the
/// wrong copy), so Settings lists them and offers to remove them.
enum DuplicateAppDetector {
    // Async and time-boxed on purpose: Spotlight can stall for minutes (for example
    // while it wakes a sleeping external volume that holds an indexed KeyPath.app),
    // and this used to run `mdfind` with an unbounded `waitUntilExit()` on the main
    // actor, freezing Settings and the wizard behind a spinner. A slow or failed
    // scan now falls back to the canonical install locations instead.
    #if DEBUG
        nonisolated(unsafe) static var testDuplicateAppPathsOverride: (() -> [String]?)?
        nonisolated(unsafe) static var testDuplicateScanRunner: (any SubprocessRunning)?
        nonisolated(unsafe) static var testReadOnlyVolumeOverride: ((String) -> Bool)?
    #endif
    static let duplicateScanTimeout: TimeInterval = 2
    static let duplicateScanExcludedPathFragments = [
        "/dist/", "/.build/", "/build/", "/DerivedData/", "/Sparkle_generate_appcast/"
    ]

    /// All KeyPath.app copies visible to Spotlight, with `/Applications/KeyPath.app`
    /// first when present. Build and Sparkle staging directories are excluded.
    static func detectDuplicateAppCopies() async -> [String] {
        var paths: [String]
        #if DEBUG
            if let override = testDuplicateAppPathsOverride?() {
                paths = override
            } else {
                paths = await spotlightAppCopies()
            }
        #else
            paths = await spotlightAppCopies()
        #endif

        // Filter out build/staging directories to avoid flagging artifacts as duplicates
        paths = paths.filter { path in
            !duplicateScanExcludedPathFragments.contains { path.contains($0) }
        }

        // A mounted installer image is not an installation and cannot be trashed.
        paths = paths.filter { !isOnReadOnlyVolume($0) }

        paths = Array(Set(paths)) // unique
        paths.sort { lhs, rhs in
            if lhs == "/Applications/KeyPath.app" {
                return true
            }
            if rhs == "/Applications/KeyPath.app" {
                return false
            }
            return lhs < rhs
        }
        return paths
    }

    private static func spotlightAppCopies() async -> [String] {
        var runner: any SubprocessRunning = SubprocessRunner.shared
        #if DEBUG
            if let override = testDuplicateScanRunner {
                runner = override
            }
        #endif
        do {
            let result = try await runner.run(
                "/usr/bin/mdfind",
                args: ["kMDItemFSName == 'KeyPath.app'c"],
                timeout: duplicateScanTimeout
            )
            let paths = result.stdout.split(separator: "\n").map(String.init)
            if result.exitCode == 0, !paths.isEmpty {
                return paths
            }
            AppLogger.shared.log(
                "⚠️ [DuplicateAppDetector] Spotlight scan exited \(result.exitCode) with \(paths.count) result(s); using canonical locations"
            )
        } catch {
            AppLogger.shared.log(
                "⚠️ [DuplicateAppDetector] Spotlight scan failed; using canonical locations: \(error)"
            )
        }
        return canonicalAppCandidates()
    }

    static func isOnReadOnlyVolume(_ path: String) -> Bool {
        #if DEBUG
            if let override = testReadOnlyVolumeOverride { return override(path) }
        #endif
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeIsReadOnlyKey])
        return values?.volumeIsReadOnly ?? false
    }

    /// A short, readable location for a copy of the app: the folder that holds it,
    /// with the home folder and iCloud Drive named the way Finder names them.
    static func displayLocation(forAppAt path: String, home: String = NSHomeDirectory()) -> String {
        var folder = (path as NSString).deletingLastPathComponent
        let iCloud = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        if folder == iCloud || folder.hasPrefix(iCloud + "/") {
            folder = "iCloud Drive" + folder.dropFirst(iCloud.count)
        } else if folder == home || folder.hasPrefix(home + "/") {
            folder = "Home" + folder.dropFirst(home.count)
        }
        return folder.split(separator: "/").joined(separator: " \u{203A} ")
    }

    private static func canonicalAppCandidates() -> [String] {
        let defaults = [
            "/Applications/KeyPath.app",
            NSHomeDirectory() + "/Applications/KeyPath.app",
            NSHomeDirectory() + "/Downloads/KeyPath.app"
        ]
        // Only locations that exist: returning the hardcoded defaults when none do
        // reported phantom "multiple copies" whenever the Spotlight scan fell back.
        return defaults.filter { Foundation.FileManager().fileExists(atPath: $0) }
    }
}
