import Foundation
import KeyPathCore
import KeyPathWizardCore

// MARK: - What KeyPath 1.0.1 left behind

/// The privileged runtime public KeyPath 1.0.1 installed, as seen from the
/// session-runtime build that replaces it (ADR-045, issue #1353).
///
/// This is migration code, not a backend: it only stops and removes these
/// items. Nothing here installs, registers, or repairs them.
public enum LegacyPrivilegedRuntime {
    /// Launchd labels 1.0.1 used. Each is checked in the system domain and in the
    /// signed-in user's GUI domain, as the refusal's own detector does.
    public static let serviceLabels = [
        "com.keypath.kanata",
        "com.keypath.helper",
        "com.keypath.karabiner-vhiddaemon",
        "com.keypath.karabiner-vhidmanager",
        "com.keypath.logrotate"
    ]

    /// Root-owned files that only KeyPath creates. Each is removed with `rm -f`.
    public static let systemFiles = [
        "/Library/LaunchDaemons/com.keypath.kanata.plist",
        "/Library/LaunchDaemons/com.keypath.helper.plist",
        "/Library/LaunchDaemons/com.keypath.karabiner-vhiddaemon.plist",
        "/Library/LaunchDaemons/com.keypath.karabiner-vhidmanager.plist",
        "/Library/LaunchDaemons/com.keypath.logrotate.plist",
        "/Library/PrivilegedHelperTools/com.keypath.helper",
        "/Library/KeyPath/bin/kanata",
        "/etc/newsyslog.d/com.keypath.conf",
        "/usr/local/bin/keypath-logrotate.sh",
        "/var/log/com.keypath.kanata.stdout.log",
        "/var/log/com.keypath.kanata.stderr.log",
        "/var/log/com.keypath.helper.stdout.log",
        "/var/log/com.keypath.helper.stderr.log",
        "/var/log/com.keypath.output-bridge.stdout.log",
        "/var/log/com.keypath.output-bridge.stderr.log",
        "/var/log/karabiner-vhid-daemon.log",
        "/var/log/karabiner-vhid-manager.log",
        "/var/log/keypath-logrotate.log"
    ]

    /// Matches only KeyPath executables: the 1.0.1 kanata launcher and kanata
    /// inside `KeyPath.app` or `/Library/KeyPath/bin`, the bundled helper, and the
    /// SMJobBless helper copy. Never a bare `HelperTools/`, which other vendors use.
    /// `pgrep -f` and `grep -E` both take this extended regular expression.
    public static let processPattern =
        #"KeyPath\.app/Contents/Library/(KeyPath|HelperTools)/|/Library/KeyPath/bin/|/Library/PrivilegedHelperTools/com\.keypath\.helper"#

    /// Every launchd target to check and boot out, for the user who runs the app.
    public static func launchdTargets(userID: uid_t) -> [String] {
        serviceLabels.flatMap { ["system/\($0)", "gui/\(userID)/\($0)"] }
    }

    /// The Karabiner driver is shared with Karabiner-Elements, so KeyPath never
    /// removes it. These paths only decide what to tell the user.
    public static let driverManagerApp = "/Applications/.Karabiner-VirtualHIDDevice-Manager.app"
    public static let driverSupportDirectory = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice"
    public static let karabinerElementsApp = "/Applications/Karabiner-Elements.app"
}

// MARK: - Evidence

/// What remains of the Karabiner VirtualHID driver after the cleanup.
public struct LegacyVirtualHIDRemnants: Equatable, Sendable {
    public var driverInstalled: Bool
    public var karabinerElementsInstalled: Bool

    public init(driverInstalled: Bool, karabinerElementsInstalled: Bool) {
        self.driverInstalled = driverInstalled
        self.karabinerElementsInstalled = karabinerElementsInstalled
    }

    public static let none = LegacyVirtualHIDRemnants(driverInstalled: false, karabinerElementsInstalled: false)

    /// What to tell the user, or nil when there is nothing left to mention.
    public var notice: String? {
        guard driverInstalled else { return nil }
        if karabinerElementsInstalled {
            return "The Karabiner virtual keyboard driver is still installed. Karabiner-Elements uses it, so KeyPath left it in place."
        }
        return "The Karabiner virtual keyboard driver from KeyPath 1.0.1 is still installed. KeyPath no longer needs it. "
            + "To remove it, see “Upgrading from KeyPath 1.0.1” in KeyPath Help."
    }
}

/// Read-only observation of the 1.0.1 stack. Taken without administrator rights.
public struct LegacyPrivilegedRuntimeEvidence: Equatable, Sendable {
    /// Launchd targets (`system/…` or `gui/<uid>/…`) reported as loaded.
    public var loadedServices: [String]
    /// Labels whose state could not be read. Never treated as absent.
    public var unreadableServices: [String]
    /// Live KeyPath processes owned by root. Another user's session is never included.
    public var rootProcesses: [SystemProcessMatch]
    public var leftoverFiles: [String]
    public var virtualHID: LegacyVirtualHIDRemnants

    public init(
        loadedServices: [String] = [],
        unreadableServices: [String] = [],
        rootProcesses: [SystemProcessMatch] = [],
        leftoverFiles: [String] = [],
        virtualHID: LegacyVirtualHIDRemnants = .none
    ) {
        self.loadedServices = loadedServices
        self.unreadableServices = unreadableServices
        self.rootProcesses = rootProcesses
        self.leftoverFiles = leftoverFiles
        self.virtualHID = virtualHID
    }

    /// Nothing of the privileged stack is left, and every service state was read.
    public var isClean: Bool {
        loadedServices.isEmpty && unreadableServices.isEmpty && rootProcesses.isEmpty && leftoverFiles.isEmpty
    }

    /// A summary of what is still present, for failure messages.
    public var remainingDescription: String {
        var parts: [String] = []
        if !loadedServices.isEmpty {
            parts.append("still loaded: \(loadedServices.joined(separator: ", "))")
        }
        if !unreadableServices.isEmpty {
            parts.append("could not check: \(unreadableServices.joined(separator: ", "))")
        }
        if !rootProcesses.isEmpty {
            parts.append("still running: \(rootProcesses.map { "PID \($0.pid)" }.joined(separator: ", "))")
        }
        if !leftoverFiles.isEmpty {
            parts.append("files remain: \(leftoverFiles.joined(separator: ", "))")
        }
        return parts.joined(separator: "; ")
    }
}

// MARK: - Cleanup

/// Removes the KeyPath 1.0.1 privileged stack with one administrator prompt and
/// reports success only after a fresh observation finds none of it left.
///
/// One root batch boots out every legacy label, stops any root KeyPath process
/// (which the app cannot signal itself, ADR-040), and deletes KeyPath's own
/// system files. The VirtualHID driver is reported, never removed.
///
/// 1.0.1's ServiceManagement records are not unregistered: release builds no
/// longer ship those plists, so `SMAppService` cannot resolve them. The record
/// cannot load a job once the bundle lacks its plist and program; at worst a
/// stale Login Items entry remains until macOS drops it.
@MainActor
public struct LegacyPrivilegedRuntimeCleanup {
    public struct Dependencies {
        public var inspect: () async -> LegacyPrivilegedRuntimeEvidence
        public var executeBatch: (PrivilegedCommandRunner.Batch) async throws -> (exitCode: Int32, output: String)
        public var sleep: (Duration) async -> Void

        public init(
            inspect: @escaping () async -> LegacyPrivilegedRuntimeEvidence,
            executeBatch: @escaping (PrivilegedCommandRunner.Batch) async throws -> (exitCode: Int32, output: String),
            sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }
        ) {
            self.inspect = inspect
            self.executeBatch = executeBatch
            self.sleep = sleep
        }
    }

    public struct Outcome: Sendable {
        public let success: Bool
        /// False when nothing was found and no administrator prompt was shown.
        public let requestedAuthorization: Bool
        /// The administrator batch ran and exited 0 (or was not needed).
        public let operationSucceeded: Bool
        public let before: LegacyPrivilegedRuntimeEvidence
        public let after: LegacyPrivilegedRuntimeEvidence
        public let failureReason: String?
        public let logs: [String]

        public var virtualHIDNotice: String? {
            after.virtualHID.notice
        }
    }

    /// launchd tears a booted-out job down asynchronously; give it this long.
    static let verificationAttempts = 10
    static let verificationInterval: Duration = .milliseconds(500)

    private let dependencies: Dependencies
    /// The signed-in user whose GUI domain is also cleaned.
    private let userID: uid_t

    public init(dependencies: Dependencies, userID: uid_t = getuid()) {
        self.dependencies = dependencies
        self.userID = userID
    }

    public func run() async -> Outcome {
        var logs: [String] = []
        let before = await dependencies.inspect()
        logs.append("[legacy-cleanup] Found: \(before.isClean ? "nothing" : before.remainingDescription)")
        guard !before.isClean else {
            return Outcome(success: true, requestedAuthorization: false, operationSucceeded: true,
                           before: before, after: before,
                           failureReason: nil, logs: logs)
        }

        let batch = Self.batch(stopping: before.rootProcesses.map(\.pid), userID: userID)
        var operationFailure: String?
        do {
            let result = try await dependencies.executeBatch(batch)
            if result.exitCode != 0 {
                operationFailure = Self.describeBatchFailure(exitCode: result.exitCode, output: result.output)
            }
            logs.append("[legacy-cleanup] Administrator batch exited \(result.exitCode)")
        } catch {
            operationFailure = "Could not run the cleanup as administrator: \(error.localizedDescription)"
        }
        if let operationFailure {
            logs.append("[legacy-cleanup] \(operationFailure)")
        }

        var after = await dependencies.inspect()
        if operationFailure == nil {
            var attempt = 1
            while !after.isClean, attempt < Self.verificationAttempts {
                await dependencies.sleep(Self.verificationInterval)
                after = await dependencies.inspect()
                attempt += 1
            }
        }

        let verificationFailure = after.isClean ? nil : "Old KeyPath service was not fully removed (\(after.remainingDescription))."
        logs.append("[legacy-cleanup] Verified: \(after.isClean ? "nothing left" : after.remainingDescription)")
        let failureReason: String? = switch (operationFailure, verificationFailure) {
        case (nil, nil): nil
        case let (operation?, nil): operation
        case let (nil, verification?): verification
        case let (operation?, verification?): "\(operation) \(verification)"
        }
        // A failed batch is never reported as success, even if a later look finds
        // nothing: the user cancelled or something went wrong, and they should know.
        return Outcome(success: failureReason == nil, requestedAuthorization: true,
                       operationSucceeded: operationFailure == nil, before: before, after: after,
                       failureReason: failureReason, logs: logs)
    }

    /// The single root script. Every step tolerates an already-absent item so a
    /// partial earlier run, or a Mac that never had one of them, still succeeds.
    static func batch(stopping pids: [pid_t], userID: uid_t) -> PrivilegedCommandRunner.Batch {
        var commands = LegacyPrivilegedRuntime.launchdTargets(userID: userID).map {
            // `bootout` can block on a job that will not exit (#927); bound it.
            "kp_timeout 15 /bin/launchctl bootout \($0) 2>/dev/null || true"
        }
        let positive = pids.filter { $0 > 0 }
        if !positive.isEmpty {
            // Re-check owner and command line as root before every signal, so a
            // PID recycled since the read-only probe is never killed. TERM first;
            // whatever is still a root KeyPath process 2s later gets KILL.
            let list = positive.map(String.init).joined(separator: " ")
            commands.append("""
            kp_is_legacy() {
              [ "$(/bin/ps -o uid= -p "$1" 2>/dev/null | /usr/bin/tr -d ' ')" = "0" ] \\
                && /bin/ps -o command= -p "$1" 2>/dev/null | /usr/bin/grep -qE '\(LegacyPrivilegedRuntime.processPattern)'
            }
            for kp_pid in \(list); do
              if kp_is_legacy "$kp_pid"; then /bin/kill -TERM "$kp_pid" 2>/dev/null || true; fi
            done
            /bin/sleep 2
            for kp_pid in \(list); do
              if kp_is_legacy "$kp_pid"; then /bin/kill -KILL "$kp_pid" 2>/dev/null || true; fi
            done
            """)
        }
        commands += LegacyPrivilegedRuntime.systemFiles.map { "/bin/rm -f \(shellQuoted($0))" }
        commands.append("/bin/rmdir /Library/KeyPath/bin /Library/KeyPath 2>/dev/null || true")
        return PrivilegedCommandRunner.Batch(
            label: "Remove the old KeyPath keyboard service",
            commands: commands,
            prompt: "KeyPath needs to remove the keyboard service installed by KeyPath 1.0.1."
        )
    }

    static func describeBatchFailure(exitCode: Int32, output: String) -> String {
        if output.contains("-128") || output.localizedCaseInsensitiveContains("user canceled") {
            return "Administrator authorization was cancelled."
        }
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty
            ? "The cleanup exited with status \(exitCode)."
            : "The cleanup exited with status \(exitCode): \(detail.prefix(300))"
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

// MARK: - Live probes

public extension LegacyPrivilegedRuntimeCleanup {
    /// launchd's "Could not find service" status for `launchctl print`.
    static let launchctlServiceNotFound: Int32 = 113

    /// Live dependencies. The admin batch comes from the app via
    /// `WizardDependencies`; without it the cleanup fails.
    static var live: Self {
        Self(dependencies: Dependencies(
            inspect: { await inspectLive() },
            executeBatch: { batch in
                guard let execute = WizardDependencies.executePrivilegedBatch else {
                    throw InstallerError.unknownRecipe("Administrator commands are not configured")
                }
                return try await execute(batch)
            }
        ))
    }

    static func inspectLive(
        provider: SystemStateProvider = .shared,
        userID: uid_t = getuid(),
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        isAlive: @escaping (pid_t) -> Bool = { SystemStateProvider.isProcessAlive(pid: $0) },
        ownerUID: @escaping (pid_t) -> uid_t? = { processOwnerUID($0) }
    ) async -> LegacyPrivilegedRuntimeEvidence {
        var loaded: [String] = []
        var unreadable: [String] = []
        for target in LegacyPrivilegedRuntime.launchdTargets(userID: userID) {
            let evidence = await provider.launchctlPrint(target: target)
            switch evidence.exitCode {
            case 0: loaded.append(target)
            case launchctlServiceNotFound: break
            default: unreadable.append(target)
            }
        }
        let matches = await provider.processMatches(matching: LegacyPrivilegedRuntime.processPattern)
        return LegacyPrivilegedRuntimeEvidence(
            loadedServices: loaded,
            unreadableServices: unreadable,
            rootProcesses: rootProcesses(in: matches, isAlive: isAlive, ownerUID: ownerUID),
            leftoverFiles: LegacyPrivilegedRuntime.systemFiles.filter(fileExists),
            virtualHID: LegacyVirtualHIDRemnants(
                driverInstalled: fileExists(LegacyPrivilegedRuntime.driverManagerApp)
                    || fileExists(LegacyPrivilegedRuntime.driverSupportDirectory),
                karabinerElementsInstalled: fileExists(LegacyPrivilegedRuntime.karabinerElementsApp)
            )
        )
    }

    /// Root-owned and alive. Liveness admits EPERM (ADR-040: only ESRCH means
    /// gone), but EPERM alone also matches another signed-in user's KeyPath, so
    /// the owner is read explicitly. An unreadable owner is not root.
    static func rootProcesses(
        in matches: [SystemProcessMatch],
        isAlive: (pid_t) -> Bool,
        ownerUID: (pid_t) -> uid_t?
    ) -> [SystemProcessMatch] {
        matches.filter { $0.pid > 0 && isAlive($0.pid) && ownerUID($0.pid) == 0 }
    }

    /// The real user ID of a process, readable for any process without privileges.
    static func processOwnerUID(_ pid: pid_t) -> uid_t? {
        guard pid > 0 else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_pcred.p_ruid
    }
}
