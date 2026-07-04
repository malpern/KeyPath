import Foundation

/// Resolves user-scoped KeyPath directories for diagnostics and support data.
///
/// During unit tests every directory is redirected into a per-process sandbox
/// under the system temporary directory so tests never pollute or delete real
/// diagnostic data (crash logs, incident snapshots, telemetry). Production
/// paths are unchanged. Services should resolve user-home paths through this
/// type instead of hand-rolling `TestEnvironment.isRunningTests` checks.
public enum AppPaths {
    /// Per-process sandbox root used in place of the real home directory while tests run.
    public static let testSandboxDirectory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "keypath-tests-\(ProcessInfo.processInfo.processIdentifier)",
            isDirectory: true
        )

    /// `~/Library/Logs/KeyPath` (sandboxed during tests).
    public static var logsDirectory: URL {
        userDirectory("Library/Logs/KeyPath")
    }

    /// `~/Library/Application Support/KeyPath` (sandboxed during tests).
    public static var applicationSupportDirectory: URL {
        userDirectory("Library/Application Support/KeyPath")
    }

    /// `~/.config/keypath` (sandboxed during tests) — user keyboard config,
    /// RuleCollections.json, installed-packs.json, and the generated
    /// keypath.kbd. Under test this resolves into the per-process sandbox so
    /// concurrent test processes (parallel CI PRs, or multiple local sessions)
    /// never race the same real files.
    public static var configDirectory: URL {
        userDirectory(".config/keypath")
    }

    /// Append-only crash/service-failure log shared by the app-state and
    /// daemon monitors: `<logsDirectory>/crashes.log`.
    public static var crashLogFile: URL {
        logsDirectory.appendingPathComponent("crashes.log")
    }

    /// Cached: isRunningTests scans Bundle.allBundles on every call and its
    /// result cannot change within a process. The mutable
    /// TestEnvironment.forceTestMode is intentionally excluded — flipping it
    /// mid-process must not make early- and late-resolved paths disagree.
    private static let isSandboxed = TestEnvironment.isRunningTests

    private static func userDirectory(_ relativePath: String) -> URL {
        let root = isSandboxed
            ? testSandboxDirectory
            : FileManager.default.homeDirectoryForCurrentUser
        return root.appendingPathComponent(relativePath, isDirectory: true)
    }
}
