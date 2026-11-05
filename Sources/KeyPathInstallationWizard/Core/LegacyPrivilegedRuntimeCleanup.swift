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
    /// Launchd labels 1.0.1 loaded into the system domain.
    public static let serviceLabels = [
        "com.keypath.kanata",
        "com.keypath.helper",
        "com.keypath.karabiner-vhiddaemon",
        "com.keypath.karabiner-vhidmanager",
        "com.keypath.logrotate"
    ]

    /// Only these two keep the session runtime from starting. The others are
    /// removed because they are KeyPath's own, not because they conflict.
    public static let blockingServiceLabels: Set<String> = ["com.keypath.kanata", "com.keypath.helper"]

    /// SMAppService plist names 1.0.1 registered from its app bundle.
    public static let serviceManagementPlists = ["com.keypath.kanata.plist", "com.keypath.helper.plist"]

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
        "/var/log/com.keypath.kanata.stderr.log"
    ]

    /// Matches the 1.0.1 kanata launcher, kanata, and the helper, by bundle path.
    /// `pgrep -f` takes extended regular expressions.
    public static let processPattern = "Library/(KeyPath|HelperTools)/"

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
    /// Labels launchd reports as loaded in the system domain.
    public var loadedServices: [String]
    /// Labels whose state could not be read. Never treated as absent.
    public var unreadableServices: [String]
    /// KeyPath processes that are alive but that this user cannot signal: root (ADR-040).
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
/// Order: best-effort SMAppService unregistration (no prompt), then a single
/// root batch that boots out every legacy label, stops any root KeyPath process
/// the app cannot signal itself (ADR-040), and deletes KeyPath's own system
/// files. The VirtualHID driver is reported, never removed.
@MainActor
public struct LegacyPrivilegedRuntimeCleanup {
    public struct Dependencies {
        public var inspect: () async -> LegacyPrivilegedRuntimeEvidence
        /// Asks ServiceManagement to drop 1.0.1's registrations. Returns log lines.
        public var unregisterRegistrations: () async -> [String]
        public var executeBatch: (PrivilegedCommandRunner.Batch) async throws -> (exitCode: Int32, output: String)
        public var sleep: (Duration) async -> Void

        public init(
            inspect: @escaping () async -> LegacyPrivilegedRuntimeEvidence,
            unregisterRegistrations: @escaping () async -> [String],
            executeBatch: @escaping (PrivilegedCommandRunner.Batch) async throws -> (exitCode: Int32, output: String),
            sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }
        ) {
            self.inspect = inspect
            self.unregisterRegistrations = unregisterRegistrations
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

    public init(dependencies: Dependencies) {
        self.dependencies = dependencies
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

        logs += await dependencies.unregisterRegistrations()

        let batch = Self.batch(stopping: before.rootProcesses.map(\.pid))
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
    static func batch(stopping pids: [pid_t]) -> PrivilegedCommandRunner.Batch {
        var commands = LegacyPrivilegedRuntime.serviceLabels.map {
            "/bin/launchctl bootout system/\($0) 2>/dev/null || true"
        }
        let positive = pids.filter { $0 > 0 }
        if !positive.isEmpty {
            // Re-check the command line as root before signalling, so a PID that
            // was recycled since the read-only probe is never killed.
            commands.append("""
            for kp_pid in \(positive.map(String.init).joined(separator: " ")); do
              if /bin/ps -o command= -p "$kp_pid" 2>/dev/null | /usr/bin/grep -qE '\(LegacyPrivilegedRuntime.processPattern)'; then
                /bin/kill -TERM "$kp_pid" 2>/dev/null || true
              fi
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

    /// Live dependencies. Unregistration and the admin batch come from the app
    /// via `WizardDependencies`; without them the cleanup fails rather than
    /// silently skipping work.
    static var live: Self {
        Self(dependencies: Dependencies(
            inspect: { await inspectLive() },
            unregisterRegistrations: {
                await WizardDependencies.unregisterLegacyServiceRegistrations?()
                    ?? ["[legacy-cleanup] ServiceManagement unregistration not configured"]
            },
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
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        isAlive: @escaping (pid_t) -> Bool = { SystemStateProvider.isProcessAlive(pid: $0) },
        canSignal: @escaping (pid_t) -> Bool = { SystemStateProvider.canSignalProcess(pid: $0) }
    ) async -> LegacyPrivilegedRuntimeEvidence {
        var loaded: [String] = []
        var unreadable: [String] = []
        for label in LegacyPrivilegedRuntime.serviceLabels {
            let evidence = await provider.launchctlPrint(target: "system/\(label)")
            switch evidence.exitCode {
            case 0: loaded.append(label)
            case launchctlServiceNotFound: break
            default: unreadable.append(label)
            }
        }
        let matches = await provider.processMatches(matching: LegacyPrivilegedRuntime.processPattern)
        return LegacyPrivilegedRuntimeEvidence(
            loadedServices: loaded,
            unreadableServices: unreadable,
            rootProcesses: rootProcesses(in: matches, isAlive: isAlive, canSignal: canSignal),
            leftoverFiles: LegacyPrivilegedRuntime.systemFiles.filter(fileExists),
            virtualHID: LegacyVirtualHIDRemnants(
                driverInstalled: fileExists(LegacyPrivilegedRuntime.driverManagerApp)
                    || fileExists(LegacyPrivilegedRuntime.driverSupportDirectory),
                karabinerElementsInstalled: fileExists(LegacyPrivilegedRuntime.karabinerElementsApp)
            )
        )
    }

    /// Alive but not signalable means another user, in practice root (ADR-040:
    /// only ESRCH means gone; EPERM means alive). The app's own session worker
    /// is signalable and so never counted.
    static func rootProcesses(
        in matches: [SystemProcessMatch],
        isAlive: (pid_t) -> Bool,
        canSignal: (pid_t) -> Bool
    ) -> [SystemProcessMatch] {
        matches.filter { $0.pid > 0 && isAlive($0.pid) && !canSignal($0.pid) }
    }
}
