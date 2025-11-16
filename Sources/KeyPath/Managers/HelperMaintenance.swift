import Foundation
import KeyPathCore
import ServiceManagement
import SwiftUI

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
final class HelperMaintenance: ObservableObject {
    /// Shared instance for UI integration
    static let shared = HelperMaintenance()

    /// Log lines for UI to present progress
    @Published private(set) var logLines: [String] = []

    /// Whether a cleanup run is currently in progress
    @Published private(set) var isRunning: Bool = false

    private var testHooks: TestHooks?

    private init() {}

    // MARK: - Public API

    /// Perform a complete cleanup and repair flow.
    /// - Returns: true on success (helper registered and responding), false otherwise.
    func runCleanupAndRepair(useAppleScriptFallback: Bool = true) async -> Bool {
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

        // Step 1: Best-effort unregister via SMAppService
        await unregisterHelperIfPresent()

        // Step 2: Stop/bootout any launchd job remnants
        await bootoutHelperJob()

        // Step 3: Remove residual files (legacy paths)
        let removed = await removeLegacyHelperArtifacts(useAppleScriptFallback: useAppleScriptFallback)
        if !removed { log("ℹ️ No legacy helper artifacts removed or operation skipped") }

        // Step 4: Register helper again from canonical bundle
        let registered = await registerHelper()
        if !registered {
            log("❌ Register failed – see logs above")
            return false
        }

        // Step 5: Health check (XPC hello/version)
        let healthy = await HelperManager.shared.testHelperFunctionality()
        log(healthy ? "✅ Helper responding via XPC" : "❌ Helper still not responding via XPC")

        return healthy
    }

    /// Find all KeyPath.app copies visible to Spotlight (fast, robust in practice).
    /// Results are sorted with `/Applications/KeyPath.app` first if present.
    /// Excludes build directories (dist/, .build/, build/) to avoid flagging build artifacts.
    nonisolated(unsafe) static var testDuplicateAppPathsOverride: (() -> [String]?)?
    nonisolated func detectDuplicateAppCopies() -> [String] {
        var paths: [String] = []
        let process = Process()
        process.launchPath = "/usr/bin/mdfind"
        process.arguments = ["kMDItemFSName == 'KeyPath.app'c"]
        let out = Pipe(); process.standardOutput = out; process.standardError = Pipe()
        do { try process.run() } catch {
            return canonicalAppCandidates()
        }
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
        let svc = ServiceManagement.SMAppService.daemon(plistName: HelperManager.helperPlistName)
        log("🔎 SMAppService status: \(svc.status.rawValue) (0=notRegistered,1=enabled,2=requiresApproval,3=notFound)")
        if svc.status == .enabled || svc.status == .notRegistered || svc.status == .requiresApproval {
            do {
                try await svc.unregister()
                log("✅ SMAppService unregister succeeded")
            } catch {
                log("⚠️ SMAppService unregister failed: \(error.localizedDescription)")
            }
        } else {
            log("ℹ️ SMAppService status=\(svc.status.rawValue) – unregister skipped")
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
            let err = Pipe(); p.standardError = err; p.standardOutput = Pipe()
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
            log("⚠️ launchctl bootout status: \(status) \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    private func removeLegacyHelperArtifacts(useAppleScriptFallback: Bool) async -> Bool {
        if let override = testHooks?.removeLegacyHelperArtifacts {
            return await override(useAppleScriptFallback)
        }
        let (removedDirectly, _) = await Task.detached { () -> (Bool, Bool) in
            let fm = FileManager.default
            let legacyBin = "/Library/PrivilegedHelperTools/com.keypath.helper"
            let legacyPlist = "/Library/LaunchDaemons/com.keypath.helper.plist"

            func tryRemove(_ path: String) -> Bool {
                if fm.fileExists(atPath: path) {
                    do { try fm.removeItem(atPath: path); return true } catch { return false }
                }
                return false
            }
            let a = tryRemove(legacyBin)
            let b = tryRemove(legacyPlist)
            return (a || b, !(a || b))
        }.value

        if removedDirectly {
            log("✅ Removed legacy helper artifacts directly")
            return true
        }

        guard useAppleScriptFallback else { return false }
        let legacyBin = "/Library/PrivilegedHelperTools/com.keypath.helper"
        let legacyPlist = "/Library/LaunchDaemons/com.keypath.helper.plist"
        let script = """
        do shell script "launchctl bootout system/com.keypath.helper || true; rm -f \(legacyBin); rm -f \(legacyPlist)" with administrator privileges
        """
        let (applescriptOk, applescriptErr) = testHooks?.runAppleScript?(script) ?? runAppleScript(script)
        if applescriptOk {
            log("✅ AppleScript cleanup removed legacy artifacts")
            return true
        } else {
            if !applescriptErr.isEmpty { log("⚠️ AppleScript error: \(applescriptErr)") }
            log("⚠️ AppleScript cleanup failed or was cancelled")
            return false
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
            let msg = error.localizedDescription
            log("❌ Register failed: \(msg)")
            if msg.localizedCaseInsensitiveContains("approval required") {
                log("➡︎ Open System Settings → Login Items and enable KeyPath background item, then try again.")
            }
            return false
        }
    }

    // MARK: - Utilities

    private func runAppleScript(_ source: String) -> (Bool, String) {
        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", source]
        process.standardOutput = Pipe()
        let err = Pipe(); process.standardError = err
        do { try process.run() } catch { return (false, "osascript launch failed: \(error.localizedDescription)") }
        process.waitUntilExit()
        if process.terminationStatus == 0 { return (true, "") }
        let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (false, e.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private nonisolated func canonicalAppCandidates() -> [String] {
        var candidates: [String] = []
        let defaults = [
            "/Applications/KeyPath.app",
            NSHomeDirectory() + "/Applications/KeyPath.app",
            NSHomeDirectory() + "/Downloads/KeyPath.app"
        ]
        for p in defaults where FileManager.default.fileExists(atPath: p) {
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
        let removeLegacyHelperArtifacts: ((Bool) async -> Bool)?
        let registerHelper: (() async -> Bool)?
        let runAppleScript: ((String) -> (Bool, String))?

        init(
            unregisterHelper: (() async -> Void)? = nil,
            bootoutHelperJob: (() async -> Void)? = nil,
            removeLegacyHelperArtifacts: ((Bool) async -> Bool)? = nil,
            registerHelper: (() async -> Bool)? = nil,
            runAppleScript: ((String) -> (Bool, String))? = nil
        ) {
            self.unregisterHelper = unregisterHelper
            self.bootoutHelperJob = bootoutHelperJob
            self.removeLegacyHelperArtifacts = removeLegacyHelperArtifacts
            self.registerHelper = registerHelper
            self.runAppleScript = runAppleScript
        }
    }

    func applyTestHooks(_ hooks: TestHooks?) {
        testHooks = hooks
    }
}
