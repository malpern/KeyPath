import AppKit
import Foundation
import KeyPathCore
import KeyPathInstallationWizard
import KeyPathWizardCore
import Observation
import ServiceManagement

@MainActor
@Observable
public final class UninstallCoordinator {
    private(set) var logLines: [String] = []
    private(set) var isRunning = false
    private(set) var didSucceed = false
    private(set) var lastError: String?
    private(set) var recommendedRecovery: WizardUninstallRecoveryAction?

    @ObservationIgnored private let resolveUninstallerURLClosure: () -> URL?
    @ObservationIgnored private let runWithAdminPrivilegesClosure: (URL, Bool, Bool) async -> AppleScriptResult
    @ObservationIgnored private let uninstallPostconditionsSatisfiedClosure: (Bool) -> Bool
    @ObservationIgnored private let helperInstalledClosure: () async -> Bool
    @ObservationIgnored private let helperFunctionalClosure: () async -> Bool
    @ObservationIgnored private let repairHelperClosure: () async -> Bool
    @ObservationIgnored private let uninstallViaHelperClosure: (Bool) async throws -> Void
    @ObservationIgnored private let unregisterHelperClosure: () async -> Bool
    @ObservationIgnored private var unregisterRuntimeServicesClosure: () async -> Void
    @ObservationIgnored private let uninstallVirtualHIDClosure: () async throws -> Void
    @ObservationIgnored private let virtualHIDRemovedClosure: () async -> Bool

    init(
        resolveUninstallerURL: @escaping () -> URL?,
        runWithAdminPrivileges: @escaping (URL, Bool, Bool) async -> AppleScriptResult,
        uninstallPostconditionsSatisfied: ((Bool) -> Bool)? = nil,
        helperInstalled: (() async -> Bool)? = nil,
        helperFunctional: (() async -> Bool)? = nil,
        repairHelper: (() async -> Bool)? = nil,
        uninstallViaHelper: ((Bool) async throws -> Void)? = nil,
        unregisterHelper: (() async -> Bool)? = nil,
        unregisterRuntimeServices: (() async -> Void)? = nil,
        uninstallVirtualHID: (() async throws -> Void)? = nil,
        virtualHIDRemoved: (() async -> Bool)? = nil
    ) {
        resolveUninstallerURLClosure = resolveUninstallerURL
        runWithAdminPrivilegesClosure = runWithAdminPrivileges
        uninstallPostconditionsSatisfiedClosure = uninstallPostconditionsSatisfied ?? { deleteConfig in
            UninstallCoordinator.defaultUninstallPostconditionsSatisfied(deleteConfig: deleteConfig)
        }
        helperInstalledClosure = helperInstalled ?? {
            await HelperManager.shared.isHelperInstalled()
        }
        helperFunctionalClosure = helperFunctional ?? {
            await HelperManager.shared.testHelperFunctionality()
        }
        repairHelperClosure = repairHelper ?? {
            await HelperMaintenance.shared.runCleanupAndRepair(
                useAppleScriptFallback: false,
                forceFullRepair: true
            )
        }
        uninstallViaHelperClosure = uninstallViaHelper ?? { deleteConfig in
            try await HelperManager.shared.uninstallKeyPath(deleteConfig: deleteConfig)
        }
        unregisterHelperClosure = unregisterHelper ?? {
            await UninstallCoordinator.defaultUnregisterHelperService()
        }
        unregisterRuntimeServicesClosure = unregisterRuntimeServices ?? {}
        uninstallVirtualHIDClosure = uninstallVirtualHID ?? {
            try await InstallerEngine().uninstallVirtualHIDDrivers(using: PrivilegeBroker())
        }
        virtualHIDRemovedClosure = virtualHIDRemoved ?? {
            await ServiceHealthChecker.shared.vhidDriverExtensionStatus() == .missing
        }
    }

    convenience init() {
        let helperService = HelperManager.smServiceFactory(HelperManager.helperPlistName)
        self.init(
            resolveUninstallerURL: Self.defaultResolveUninstallerURL,
            runWithAdminPrivileges: Self.defaultRunWithAdminPrivileges,
            unregisterHelper: {
                await UninstallCoordinator.defaultUnregisterHelperService(helperService)
            },
            unregisterRuntimeServices: nil
        )
        unregisterRuntimeServicesClosure = { [weak self] in
            await self?.unregisterSMAppServiceDaemons()
        }
    }

    @discardableResult
    public func uninstall(deleteConfig: Bool = false) async -> Bool {
        await performUninstall(
            deleteConfig: deleteConfig,
            removeVirtualHID: false,
            allowAdminFallback: false
        ).success
    }

    public func performUninstall(
        deleteConfig: Bool = false,
        removeVirtualHID: Bool = false,
        allowAdminFallback: Bool = false
    ) async -> WizardUninstallResult {
        guard !isRunning else {
            return WizardUninstallResult(
                success: false,
                failureReason: "An uninstall is already in progress."
            )
        }

        isRunning = true
        didSucceed = false
        lastError = nil
        recommendedRecovery = nil
        logLines = ["🗑️ Starting KeyPath uninstall..."]
        var steps: [WizardUninstallStepResult] = []

        defer { isRunning = false }

        // IMPORTANT: Unregister SMAppService daemons BEFORE helper/script cleanup
        // This clears the internal registration database that helper/script can't access
        await unregisterRuntimeServicesClosure()

        if uninstallPostconditionsSatisfiedClosure(deleteConfig) {
            if removeVirtualHID, await !virtualHIDRemovedClosure() {
                let message = "KeyPath is removed, but the virtual keyboard driver remains registered with macOS."
                steps.append(WizardUninstallStepResult(
                    id: "uninstall-virtual-hid-driver",
                    success: false,
                    error: message
                ))
                return finish(WizardUninstallResult(
                    success: false,
                    failureReason: message,
                    steps: steps,
                    logs: logLines
                ))
            }
            steps.append(WizardUninstallStepResult(id: "verify-uninstall", success: true))
            await resetForTestingIfEnabled()
            logLines.append("✅ Uninstall completed; cleanup already satisfied")
            return finish(
                WizardUninstallResult(success: true, steps: steps, logs: logLines)
            )
        }

        let helperInstalled = await helperInstalledClosure()
        var helperReady = helperInstalled
        if helperReady {
            helperReady = await helperFunctionalClosure()
        }
        if !helperReady {
            logLines.append("ℹ️ System helper is unavailable; attempting SMAppService repair")
            let repaired = await repairHelperClosure()
            steps.append(WizardUninstallStepResult(
                id: "repair-uninstall-helper",
                success: repaired,
                error: repaired ? nil : "The system helper could not be repaired."
            ))
            helperReady = repaired
            if helperReady {
                helperReady = await helperFunctionalClosure()
            }
        }

        var helperFailure: String?
        var helperReplyFailed = false
        var virtualHIDFailure: String?
        if helperReady {
            logLines.append("🔧 Using the system helper for uninstall...")
            logLines.append(deleteConfig
                ? "🗑️ User configuration will be deleted"
                : "💾 User configuration will be preserved")

            if removeVirtualHID {
                do {
                    try await uninstallVirtualHIDClosure()
                    let removed = await waitForVirtualHIDRemoval()
                    virtualHIDFailure = removed
                        ? nil
                        : "The virtual keyboard driver is still registered with macOS."
                    steps.append(WizardUninstallStepResult(
                        id: "uninstall-virtual-hid-driver",
                        success: removed,
                        error: virtualHIDFailure
                    ))
                } catch {
                    virtualHIDFailure = "Virtual keyboard driver removal failed: \(error.localizedDescription)"
                    steps.append(WizardUninstallStepResult(
                        id: "uninstall-virtual-hid-driver",
                        success: false,
                        error: virtualHIDFailure
                    ))
                }

                if let virtualHIDFailure {
                    let message = "The virtual keyboard driver could not be removed. \(virtualHIDFailure) Uncheck driver removal to uninstall KeyPath without removing the shared driver."
                    logLines.append("⚠️ \(message)")
                    return finish(WizardUninstallResult(
                        success: false,
                        failureReason: message,
                        steps: steps,
                        logs: logLines
                    ))
                }
            }

            do {
                try await uninstallViaHelperClosure(deleteConfig)
                steps.append(WizardUninstallStepResult(id: "uninstall-via-helper", success: true))

                let helperUnregistered = await unregisterHelperClosure()
                steps.append(WizardUninstallStepResult(
                    id: "unregister-uninstall-helper",
                    success: helperUnregistered,
                    error: helperUnregistered ? nil : "The system helper registration remains active."
                ))

                let verified = await waitForUninstallPostconditions(deleteConfig: deleteConfig)
                steps.append(WizardUninstallStepResult(
                    id: "verify-uninstall",
                    success: verified,
                    error: verified ? nil : "Some KeyPath system components remain installed."
                ))
                if verified, helperUnregistered {
                    await resetForTestingIfEnabled()
                    logLines.append("✅ Uninstall completed and verified")
                    return finish(
                        WizardUninstallResult(success: true, steps: steps, logs: logLines)
                    )
                }
                helperFailure = helperUnregistered
                    ? "Some KeyPath system components remain installed."
                    : "The system helper registration could not be removed."
            } catch {
                helperReplyFailed = true
                helperFailure = error.localizedDescription
                steps.append(WizardUninstallStepResult(
                    id: "uninstall-via-helper",
                    success: false,
                    error: helperFailure
                ))
                logLines.append("❌ System helper uninstall failed: \(error.localizedDescription)")
            }
        } else {
            helperFailure = "The system helper is unavailable and could not be repaired."
            logLines.append("⚠️ \(helperFailure!)")
        }

        // A timeout or interrupted helper reply is ambiguous. Before invoking
        // Emergency Cleanup, verify whether the helper already removed the
        // requested components. Only tear down helper registration after the
        // filesystem postcondition proves the uninstall completed.
        let filesRemovedAfterHelperError = helperReplyFailed
            ? await waitForUninstallPostconditions(deleteConfig: deleteConfig)
            : false
        if filesRemovedAfterHelperError {
            let driverRemoved: Bool = if removeVirtualHID {
                await waitForVirtualHIDRemoval()
            } else {
                true
            }
            if driverRemoved {
                let helperUnregistered = await unregisterHelperClosure()
                steps.append(WizardUninstallStepResult(
                    id: "unregister-uninstall-helper",
                    success: helperUnregistered,
                    error: helperUnregistered ? nil : "The system helper registration remains active."
                ))
                steps.append(WizardUninstallStepResult(
                    id: "verify-uninstall",
                    success: helperUnregistered,
                    error: helperUnregistered ? nil : "The system helper registration remains active."
                ))
                if helperUnregistered {
                    await resetForTestingIfEnabled()
                    logLines.append(
                        "✅ System helper reply failed, but uninstall postconditions are satisfied; skipping Emergency Cleanup"
                    )
                    return finish(WizardUninstallResult(
                        success: true,
                        steps: steps,
                        logs: logLines
                    ))
                }
            }
        }

        if allowAdminFallback {
            return await performEmergencyCleanup(
                deleteConfig: deleteConfig,
                removeVirtualHID: removeVirtualHID,
                previousSteps: steps
            )
        }

        let message = helperFailure ?? "KeyPath could not prepare its system helper."
        logLines.append("ℹ️ Emergency Cleanup is available as an explicit administrator-authorized fallback")
        return finish(WizardUninstallResult(
            success: false,
            failureReason: message,
            recommendedRecovery: .emergencyCleanup,
            steps: steps,
            logs: logLines
        ))
    }

    private func finish(_ result: WizardUninstallResult) -> WizardUninstallResult {
        didSucceed = result.success
        lastError = result.failureReason
        recommendedRecovery = result.recommendedRecovery
        return result
    }

    private func waitForUninstallPostconditions(deleteConfig: Bool) async -> Bool {
        let clock = ContinuousClock()
        for attempt in 1 ... 8 {
            if uninstallPostconditionsSatisfiedClosure(deleteConfig) {
                return true
            }
            if attempt < 8 {
                try? await clock.sleep(for: .milliseconds(250))
            }
        }
        return false
    }

    private func waitForVirtualHIDRemoval() async -> Bool {
        let clock = ContinuousClock()
        for attempt in 1 ... 8 {
            if await virtualHIDRemovedClosure() {
                return true
            }
            if attempt < 8 {
                try? await clock.sleep(for: .milliseconds(250))
            }
        }
        return false
    }

    /// Fallback uninstall using the shell script with admin privileges
    private func performEmergencyCleanup(
        deleteConfig: Bool,
        removeVirtualHID: Bool,
        previousSteps: [WizardUninstallStepResult]
    ) async -> WizardUninstallResult {
        var steps = previousSteps
        logLines.append("⚠️ Starting Emergency Cleanup with administrator authorization")
        guard let scriptURL = resolveUninstallerURLClosure() else {
            let message = "Uninstaller script wasn't found in this build."
            logLines.append("❌ \(message)")
            steps.append(WizardUninstallStepResult(
                id: "emergency-admin-cleanup",
                success: false,
                error: message
            ))
            return finish(WizardUninstallResult(
                success: false,
                failureReason: message,
                steps: steps,
                logs: logLines
            ))
        }

        logLines.append("📄 Using uninstaller at: \(scriptURL.path)")
        if deleteConfig {
            logLines.append("🗑️ User configuration will be deleted")
        } else {
            logLines.append("💾 User configuration will be preserved")
        }

        let result = await runWithAdminPrivilegesClosure(
            scriptURL,
            deleteConfig,
            removeVirtualHID
        )

        if result.success {
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !output.isEmpty {
                logLines.append(contentsOf: output.components(separatedBy: "\n"))
            }

            let filesRemoved = await waitForUninstallPostconditions(deleteConfig: deleteConfig)
            var driverRemoved = !removeVirtualHID
            if removeVirtualHID {
                driverRemoved = await waitForVirtualHIDRemoval()
            }
            let verified = filesRemoved && driverRemoved
            steps.append(WizardUninstallStepResult(
                id: "emergency-admin-cleanup",
                success: verified,
                error: verified ? nil : "Emergency Cleanup finished, but some requested system components remain installed."
            ))
            if verified {
                await resetForTestingIfEnabled()
                logLines.append("✅ Emergency Cleanup completed and verified")
                return finish(WizardUninstallResult(success: true, steps: steps, logs: logLines))
            }

            let message = "Emergency Cleanup finished, but some requested system components remain installed."
            logLines.append("❌ \(message)")
            return finish(WizardUninstallResult(
                success: false,
                failureReason: message,
                steps: steps,
                logs: logLines
            ))
        }

        let trimmed = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = trimmed.isEmpty
            ? "Emergency Cleanup failed with error code \(result.exitStatus)."
            : trimmed
        logLines.append("❌ \(message)")
        steps.append(WizardUninstallStepResult(
            id: "emergency-admin-cleanup",
            success: false,
            error: message
        ))
        return finish(WizardUninstallResult(
            success: false,
            failureReason: message,
            steps: steps,
            logs: logLines
        ))
    }

    func copyTerminalCommand() {
        guard let scriptURL = resolveUninstallerURLClosure() else { return }
        let command = "sudo \"\(scriptURL.path)\""
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        logLines.append("📋 Copied command: \(command)")
    }

    func revealUninstallerInFinder() {
        guard let scriptURL = resolveUninstallerURLClosure() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([scriptURL])
    }

    // MARK: - Testing Reset

    /// Reset TCC permissions and preferences for fresh install testing.
    /// Only runs when FeatureFlags.uninstallForTesting is enabled.
    private func resetForTestingIfEnabled() async {
        guard FeatureFlags.uninstallForTesting else {
            logLines.append("ℹ️ TCC reset skipped (uninstallForTesting disabled)")
            return
        }

        logLines.append("🧪 Resetting for fresh install testing...")

        let bundleId = "com.keypath.KeyPath"
        let kanataBinary = WizardSystemPaths.bundledKanataPath
        let legacyKanataBinary = "/Library/KeyPath/bin/kanata"

        // Reset TCC permissions (these don't require admin)
        // Include legacy system path so existing grants from pre-bundled-only installs are cleared too
        let tccResets: [(service: String, target: String)] = [
            ("Accessibility", bundleId),
            ("ListenEvent", bundleId), // Input Monitoring
            ("ListenEvent", kanataBinary), // Input Monitoring for kanata (bundled)
            ("ListenEvent", legacyKanataBinary), // Input Monitoring for kanata (legacy system path)
            ("SystemPolicyAllFiles", bundleId) // Full Disk Access
        ]

        for (service, target) in tccResets {
            do {
                let result = try await SubprocessRunner.shared.run("/usr/bin/tccutil", args: ["reset", service, target])
                if result.exitCode == 0 {
                    logLines.append("  ✓ Reset \(service) for \(target)")
                } else {
                    logLines.append("  ⚠️ Failed to reset \(service) for \(target)")
                }
            } catch {
                logLines.append("  ⚠️ tccutil error: \(error.localizedDescription)")
            }
        }

        do {
            let result = try await SubprocessRunner.shared.run("/usr/bin/defaults", args: ["delete", bundleId])
            if result.exitCode == 0 {
                logLines.append("  ✓ Cleared UserDefaults")
            } else {
                logLines.append("  ⚠️ No UserDefaults to clear (or already cleared)")
            }
        } catch {
            logLines.append("  ⚠️ defaults error: \(error.localizedDescription)")
        }

        logLines.append("🧪 Testing reset complete")
    }

    // MARK: - SMAppService Cleanup

    /// Unregister all KeyPath daemons via SMAppService API before helper/script cleanup.
    /// This is necessary because helper and shell script can only use launchctl/rm,
    /// which leaves stale entries in SMAppService's internal registration database.
    private func unregisterSMAppServiceDaemons() async {
        let daemonPlists = [
            "com.keypath.kanata.plist"
            // Note: Karabiner VirtualHID daemons are managed separately and don't use SMAppService
        ]

        for plistName in daemonPlists {
            let service = HelperManager.smServiceFactory(plistName)
            let status = await SystemStateProvider.shared.freshSMAppServiceStatus(for: plistName)
            guard status == .enabled || status == .requiresApproval else {
                logLines.append("ℹ️ SMAppService \(plistName): not registered, skipping")
                continue
            }

            do {
                try await service.unregister()
                await SystemStateProvider.shared.invalidateSMAppServiceStatus(plistName: plistName)
                logLines.append("✅ SMAppService \(plistName): unregistered")
            } catch {
                // Log but continue - the helper/script will still clean up files
                logLines.append("⚠️ SMAppService \(plistName): unregister failed - \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    private static func defaultResolveUninstallerURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "uninstall", withExtension: "sh") {
            return bundled
        }

        let workingDirectory = Foundation.ProcessInfo.processInfo.environment["PWD"] ?? "."
        let repoPath = URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent("Sources/KeyPath/Resources/uninstall.sh")
        if Foundation.FileManager().isExecutableFile(atPath: repoPath.path) {
            return repoPath
        }

        return nil
    }

    private static func defaultUninstallPostconditionsSatisfied(deleteConfig: Bool) -> Bool {
        var paths = [
            "/Applications/KeyPath.app",
            "/Library/PrivilegedHelperTools/com.keypath.helper",
            "/Library/LaunchDaemons/com.keypath.kanata.plist",
            "/Library/LaunchDaemons/com.keypath.karabiner-vhiddaemon.plist",
            "/Library/LaunchDaemons/com.keypath.karabiner-vhidmanager.plist",
            "/Library/LaunchDaemons/com.keypath.helper.plist"
        ]
        if deleteConfig {
            paths.append(FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/keypath").path)
        }
        return paths.allSatisfy { !FileManager.default.fileExists(atPath: $0) }
    }

    private static func defaultUnregisterHelperService(
        _ service: any SMAppServiceProtocol = HelperManager.smServiceFactory(HelperManager.helperPlistName)
    ) async -> Bool {
        let plistName = HelperManager.helperPlistName
        let provider = SystemStateProvider.shared
        let initialStatus = await provider.freshSMAppServiceStatus(for: plistName)
        if initialStatus == .notFound || initialStatus == .notRegistered {
            return true
        }

        do {
            try await service.unregister()
            await provider.invalidateSMAppServiceStatus(plistName: plistName)
            return true
        } catch {
            let finalStatus = await provider.freshSMAppServiceStatus(for: plistName)
            AppLogger.shared.log(
                "⚠️ [UninstallCoordinator] Helper unregister failed: \(error.localizedDescription); final status=\(finalStatus.rawValue)"
            )
            return finalStatus == .notFound || finalStatus == .notRegistered
        }
    }

    private static func defaultRunWithAdminPrivileges(
        scriptURL: URL,
        deleteConfig: Bool,
        removeVirtualHID: Bool
    ) async
        -> AppleScriptResult
    {
        // Use PrivilegedCommandRunner which respects TestEnvironment.useSudoForPrivilegedOps
        let configFlag = deleteConfig ? " --delete-config" : ""
        let driverFlag = removeVirtualHID ? " --remove-virtual-hid" : ""
        let command = "KEYPATH_UNINSTALL_ASSUME_YES=1 '\(scriptURL.path)' --assume-yes\(configFlag)\(driverFlag)"
        let result = PrivilegedCommandRunner.execute(
            command: command,
            prompt: "KeyPath needs to uninstall system services."
        )
        return AppleScriptResult(
            success: result.success,
            output: result.output,
            error: result.success ? "" : result.output,
            exitStatus: result.exitCode
        )
    }

    private static func escapeForAppleScript(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

struct AppleScriptResult {
    let success: Bool
    let output: String
    let error: String
    let exitStatus: Int32
}

// NOTE: AppleScriptRunner was removed - now using PrivilegedCommandRunner which respects
// TestEnvironment.useSudoForPrivilegedOps for sudo-based execution in test environments.
