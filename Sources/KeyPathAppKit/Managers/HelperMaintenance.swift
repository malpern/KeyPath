import Foundation
import KeyPathCore
import Observation
import ServiceManagement

/// A focused utility for maintaining the privileged helper registration and artifacts.
///
/// Responsibilities:
/// - Stop/unregister helper via SMAppService and launchctl (best effort)
/// - Remove stale helper artifacts from /Library paths when present
/// - Detect duplicate KeyPath.app copies that can confuse Background Items approval
/// - Re-register helper from the canonical /Applications/KeyPath.app bundle
/// - Verify XPC connectivity as a health check
///
/// Notes:
/// - All steps are idempotent and best-effort; failures are logged and surfaced.
/// - Uses AppleScript `do shell script … with administrator privileges` as a fallback
///   when the helper cannot perform privileged operations.
@MainActor
@Observable
public final class HelperMaintenance {
    /// Shared instance for UI integration
    static let shared = HelperMaintenance()

    /// Log lines for UI to present progress
    public private(set) var logLines: [String] = []

    /// The most recent failure line from the current (or most recently completed) run.
    /// Scans `logLines` from newest to oldest for an explicit failure marker.
    /// Skips the "🧹 Cleanup & Repair finished"/"started" bookend lines emitted
    /// by `runCleanupAndRepair` so UI callers don't surface them as error text.
    public var lastErrorLine: String? {
        for line in logLines.reversed() {
            if line.hasPrefix("🧹 Cleanup & Repair") { continue }
            if line.hasPrefix("❌") || line.hasPrefix("⚠️") {
                return line
            }
        }
        return nil
    }

    /// Whether a cleanup run is currently in progress
    private(set) var isRunning: Bool = false

    @ObservationIgnored private var testHooks: TestHooks?

    private init() {}

    // MARK: - Public API

    /// Perform a complete cleanup and repair flow.
    /// - Returns: true on success (helper registered and responding), false otherwise.
    public func runCleanupAndRepair(useAppleScriptFallback: Bool = true) async -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        logLines.removeAll()
        log("🧹 Cleanup & Repair started")

        defer {
            isRunning = false
            log("🧹 Cleanup & Repair finished")
        }

        // Step 0: Duplicate app detection
        let copies = detectDuplicateAppCopies()
        if copies.filter({ !$0.hasPrefix("/Applications/KeyPath.app") }).count > 0 {
            log("⚠️ Multiple KeyPath.app copies detected:")
            for c in copies {
                log("   - \(c)")
            }
            log("❗ Background Item approval may point at a non-/Applications copy.")
        } else {
            log("✅ App copy check: OK (\(copies.first ?? "unknown"))")
        }

        // Step 1: Try to refresh/register the helper in-place first.
        //
        // If the helper is already healthy, tearing it down first can introduce its own
        // SMAppService failure modes and makes fast iteration harder. Prefer an idempotent
        // register/refresh attempt, then fall back to full unregister/cleanup only if needed.
        if await registerHelper() {
            log("✅ Helper registered via SMAppService on first attempt")
        } else {
            log("⚠️ Direct helper refresh failed; attempting cleanup then retry")

            // Step 2: Best-effort unregister via SMAppService
            await unregisterHelperIfPresent()

            // Step 3: Stop/bootout any launchd job remnants
            await bootoutHelperJob()

            // Step 4: Remove residual files (legacy paths) – AppleScript fallback optional
            let cleanupResult = await removeLegacyHelperArtifacts(
                useAppleScriptFallback: useAppleScriptFallback
            )
            switch cleanupResult {
            case .removed:
                break
            case .skipped:
                log("ℹ️ No legacy helper artifacts removed or operation skipped")
            case .failed:
                log("❌ Legacy helper cleanup failed; aborting repair")
                isRunning = false
                return false
            }

            // Step 5: Retry registration after cleanup
            let registered = await registerHelper()
            if !registered {
                log("❌ Register failed after cleanup – see logs above")
                isRunning = false
                return false
            }
        }

        // Step 6: Health check (XPC hello/version)
        let healthy = await HelperManager.shared.testHelperFunctionality()
        log(healthy ? "✅ Helper responding via XPC" : "❌ Helper still not responding via XPC")

        return healthy
    }

    // Find all KeyPath.app copies visible to Spotlight (fast, robust in practice).
    // Results are sorted with `/Applications/KeyPath.app` first if present.
    // Excludes build directories (dist/, .build/, build/) to avoid flagging build artifacts.
    #if DEBUG
        nonisolated(unsafe) static var testDuplicateAppPathsOverride: (() -> [String]?)?
    #endif
    public nonisolated func detectDuplicateAppCopies() -> [String] {
        var paths: [String] = []
        let process = Process()
        process.launchPath = "/usr/bin/mdfind"
        process.arguments = ["kMDItemFSName == 'KeyPath.app'c"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch {
            return canonicalAppCandidates()
        }
        #if DEBUG
            if let override = Self.testDuplicateAppPathsOverride?() {
                paths = override
            } else {
                process.waitUntilExit()
                let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                paths = s.split(separator: "\n").map(String.init)
                if paths.isEmpty {
                    paths = canonicalAppCandidates()
                }
            }
        #else
            process.waitUntilExit()
            let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            paths = s.split(separator: "\n").map(String.init)
            if paths.isEmpty {
                paths = canonicalAppCandidates()
            }
        #endif

        // Filter out build directories to avoid flagging build artifacts as duplicates
        let buildDirPatterns = ["/dist/", "/.build/", "/build/", "/DerivedData/"]
        paths = paths.filter { path in
            !buildDirPatterns.contains { pattern in path.contains(pattern) }
        }

        paths = Array(Set(paths)) // unique
        paths.sort { lhs, rhs in
            if lhs == "/Applications/KeyPath.app" { return true }
            if rhs == "/Applications/KeyPath.app" { return false }
            return lhs < rhs
        }
        return paths
    }

    // MARK: - Private steps

    private func unregisterHelperIfPresent() async {
        if let override = testHooks?.unregisterHelper {
            await override()
            return
        }
        let svc = HelperManager.smServiceFactory(HelperManager.helperPlistName)
        let status = svc.status
        log(
            "🔎 SMAppService status: \(status.rawValue) (0=notRegistered,1=enabled,2=requiresApproval,3=notFound)"
        )
        if status == .enabled || status == .notRegistered || status == .requiresApproval {
            do {
                try await svc.unregister()
                log("✅ SMAppService unregister succeeded")
            } catch {
                log("⚠️ SMAppService unregister failed: \(error.localizedDescription)")
            }
        } else {
            log("ℹ️ SMAppService status=\(status.rawValue) – unregister skipped")
        }
    }

    private func bootoutHelperJob() async {
        if let override = testHooks?.bootoutHelperJob {
            await override()
            return
        }
        let result = await Task.detached { () -> (Int32, String) in
            let p = Process()
            p.launchPath = "/bin/launchctl"
            p.arguments = ["bootout", "system/com.keypath.helper"]
            let err = Pipe()
            p.standardError = err
            p.standardOutput = Pipe()
            do { try p.run() } catch {
                return (-1, "launchctl bootout error: \(error.localizedDescription)")
            }
            p.waitUntilExit()
            let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (p.terminationStatus, e)
        }.value
        let (status, stderr) = result
        if status == 0 {
            log("✅ launchctl bootout succeeded")
        } else if stderr.contains("Could not find service") || stderr.contains("Bad request") {
            log("ℹ️ Helper job not found (already stopped)")
        } else if status == -1 {
            log("⚠️ \(stderr)")
        } else {
            log(
                "⚠️ launchctl bootout status: \(status) \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
    }

    enum LegacyCleanupResult {
        case removed
        case skipped
        case failed
    }

    private func removeLegacyHelperArtifacts(useAppleScriptFallback: Bool) async
        -> LegacyCleanupResult
    {
        if let override = testHooks?.removeLegacyHelperArtifacts {
            return await override(useAppleScriptFallback)
        }
        let (removedDirectly, _) = await Task.detached { () -> (Bool, Bool) in
            let fm = Foundation.FileManager()
            let legacyBin = "/Library/PrivilegedHelperTools/com.keypath.helper"
            let legacyPlist = "/Library/LaunchDaemons/com.keypath.helper.plist"

            func tryRemove(_ path: String) -> Bool {
                if fm.fileExists(atPath: path) {
                    do {
                        try fm.removeItem(atPath: path)
                        return true
                    } catch { return false }
                }
                return false
            }
            let a = tryRemove(legacyBin)
            let b = tryRemove(legacyPlist)
            return (a || b, !(a || b))
        }.value

        if removedDirectly {
            log("✅ Removed legacy helper artifacts directly")
            return .removed
        }

        guard useAppleScriptFallback else { return .skipped }
        let legacyBin = "/Library/PrivilegedHelperTools/com.keypath.helper"
        let legacyPlist = "/Library/LaunchDaemons/com.keypath.helper.plist"
        let command = """
        /bin/launchctl bootout system/com.keypath.helper || true && \
        /bin/rm -f '\(legacyBin)' && \
        /bin/rm -f '\(legacyPlist)'
        """
        do {
            let result = try await AdminCommandExecutorHolder.shared.execute(
                command: command,
                description: "Remove legacy helper artifacts"
            )
            if result.exitCode == 0 {
                log("✅ Admin cleanup removed legacy helper artifacts")
                return .removed
            } else {
                let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                log("⚠️ Admin cleanup failed (exit \(result.exitCode)): \(output)")
                return .failed
            }
        } catch {
            log("⚠️ Admin cleanup error: \(error.localizedDescription)")
            return .failed
        }
    }

    private func registerHelper() async -> Bool {
        if let override = testHooks?.registerHelper {
            return await override()
        }
        do {
            try await HelperManager.shared.installHelper()
            log("✅ Helper registered via SMAppService")
            return true
        } catch {
            let msg = HelperManager.formatSMError(error)
            log("❌ Register failed: \(msg)")
            if msg.localizedCaseInsensitiveContains("approval required") {
                log(
                    "➡︎ Open System Settings → Login Items and enable KeyPath background item, then try again."
                )
            }
            return false
        }
    }

    // MARK: - Utilities

    private nonisolated func canonicalAppCandidates() -> [String] {
        var candidates: [String] = []
        let defaults = [
            "/Applications/KeyPath.app",
            NSHomeDirectory() + "/Applications/KeyPath.app",
            NSHomeDirectory() + "/Downloads/KeyPath.app"
        ]
        for p in defaults where Foundation.FileManager().fileExists(atPath: p) {
            candidates.append(p)
        }
        return candidates.isEmpty ? defaults : candidates
    }

    private func log(_ line: String) {
        AppLogger.shared.log(line)
        logLines.append(line)
    }
}

extension HelperMaintenance {
    struct TestHooks {
        let unregisterHelper: (() async -> Void)?
        let bootoutHelperJob: (() async -> Void)?
        let removeLegacyHelperArtifacts: ((Bool) async -> LegacyCleanupResult)?
        let registerHelper: (() async -> Bool)?

        init(
            unregisterHelper: (() async -> Void)? = nil,
            bootoutHelperJob: (() async -> Void)? = nil,
            removeLegacyHelperArtifacts: ((Bool) async -> LegacyCleanupResult)? = nil,
            registerHelper: (() async -> Bool)? = nil
        ) {
            self.unregisterHelper = unregisterHelper
            self.bootoutHelperJob = bootoutHelperJob
            self.removeLegacyHelperArtifacts = removeLegacyHelperArtifacts
            self.registerHelper = registerHelper
        }
    }

    func applyTestHooks(_ hooks: TestHooks?) {
        testHooks = hooks
    }
}
