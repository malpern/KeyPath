import Foundation
import KeyPathCore
import KeyPathInstallationWizard
import Observation
import Sparkle

public enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable = "Stable"
    case beta = "Beta"

    public var id: String {
        rawValue
    }
}

/// Sparkle supplies its continuation as an Objective-C block without Sendable
/// annotations. The updater invokes it exactly once on the main actor after
/// runtime preparation, so this narrow wrapper documents that ownership
/// transfer for Swift 6 concurrency checking.
private final class SparkleInstallHandler: @unchecked Sendable {
    private let block: () -> Void

    init(_ block: @escaping () -> Void) {
        self.block = block
    }

    func invoke() {
        block()
    }
}

/// Manages application updates via Sparkle framework
///
/// This service handles:
/// - Automatic update checks (every 24 hours)
/// - Manual "Check for Updates" menu action
/// - Pre/post-install hooks to properly stop/restart KeyPath services
///
/// Per AGENTS.md, all service stop/restart operations go through InstallerEngine.
@Observable
@MainActor
public final class UpdateService: NSObject {
    // MARK: - Singleton

    public static let shared = UpdateService()

    // MARK: - Properties

    @ObservationIgnored private var updaterController: SPUStandardUpdaterController?
    @ObservationIgnored private let channelDefaultsKey = "keypath.update.channel"

    public private(set) var canCheckForUpdates = false
    public private(set) var lastUpdateCheckDate: Date?
    public private(set) var automaticallyChecksForUpdates = true
    public private(set) var automaticallyDownloadsUpdates = true
    public private(set) var allowsAutomaticUpdates = true
    public private(set) var updateChannel: UpdateChannel = .stable
    public private(set) var currentFeedURL: String?

    // MARK: - Initialization

    override private init() {
        super.init()
    }

    // MARK: - Public API

    /// Initialize the updater. Call once at app startup.
    public func initialize() {
        guard updaterController == nil else { return }

        // Skip initialization in test environment
        if TestEnvironment.isRunningTests {
            AppLogger.shared.debug("🧪 [UpdateService] Skipping Sparkle init in test mode")
            return
        }

        AppLogger.shared.log("🔄 [UpdateService] Initializing Sparkle updater")

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        // Bind to updater properties
        if let updater = updaterController?.updater {
            // Clear legacy feed URL overrides from UserDefaults in case older builds used setFeedURL.
            updater.clearFeedURLFromUserDefaults()
            canCheckForUpdates = updater.canCheckForUpdates
            lastUpdateCheckDate = updater.lastUpdateCheckDate
            automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
            automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
            allowsAutomaticUpdates = updater.allowsAutomaticUpdates
            let persistedChannel = loadPersistedChannel()
            setUpdateChannel(persistedChannel)

            AppLogger.shared.log(
                "✅ [UpdateService] Sparkle initialized - autoCheck: \(automaticallyChecksForUpdates), autoInstall: \(automaticallyDownloadsUpdates), channel: \(updateChannel.rawValue)"
            )
        }
    }

    /// Manually trigger an update check (called from menu item)
    public func checkForUpdates() {
        AppLogger.shared.log("🔍 [UpdateService] Manual update check requested")
        updaterController?.checkForUpdates(nil)
    }

    /// Enable or disable automatic update checks
    public func setAutomaticChecks(enabled: Bool) {
        updaterController?.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = enabled
        allowsAutomaticUpdates = updaterController?.updater.allowsAutomaticUpdates ?? false
        automaticallyDownloadsUpdates = updaterController?.updater.automaticallyDownloadsUpdates ?? false
        AppLogger.shared.log("⚙️ [UpdateService] Automatic checks set to: \(enabled)")
    }

    /// Enable or disable Sparkle's automatic background download/install path.
    /// This is a user preference; Info.plist supplies only the initial default.
    public func setAutomaticDownloads(enabled: Bool) {
        guard let updater = updaterController?.updater, updater.allowsAutomaticUpdates else {
            AppLogger.shared.warn("⚠️ [UpdateService] Automatic updates are unavailable while automatic checks are disabled")
            automaticallyDownloadsUpdates = false
            allowsAutomaticUpdates = false
            return
        }

        updater.automaticallyDownloadsUpdates = enabled
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        allowsAutomaticUpdates = updater.allowsAutomaticUpdates
        AppLogger.shared.log("⚙️ [UpdateService] Automatic download/install set to: \(automaticallyDownloadsUpdates)")
    }

    public func setUpdateChannel(_ channel: UpdateChannel) {
        updateChannel = channel
        UserDefaults.standard.set(channel.rawValue, forKey: channelDefaultsKey)
        currentFeedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        AppLogger.shared.log(
            "🛰️ [UpdateService] Update channel set to \(channel.rawValue) via Sparkle channels"
        )
    }

    /// Get the underlying updater for SwiftUI bindings
    public var updater: SPUUpdater? {
        updaterController?.updater
    }

    // MARK: - Channels

    private func loadPersistedChannel() -> UpdateChannel {
        let storedValue = UserDefaults.standard.string(forKey: channelDefaultsKey) ?? UpdateChannel.stable.rawValue
        return UpdateChannel(rawValue: storedValue) ?? .stable
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateService: SPUUpdaterDelegate {
    public nonisolated func feedURLString(for _: SPUUpdater) -> String? {
        // Keep the feed static via SUFeedURL; channel selection is controlled by allowedChannels(for:).
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    }

    public nonisolated func allowedChannels(for _: SPUUpdater) -> Set<String> {
        let selected = UserDefaults.standard.string(forKey: channelDefaultsKey) ?? UpdateChannel.stable.rawValue
        let channel = UpdateChannel(rawValue: selected) ?? .stable

        return channel == .beta ? ["beta"] : []
    }

    /// Called immediately before Sparkle begins installation. Runtime shutdown
    /// is completed by `shouldPostponeRelaunchForUpdate` before Sparkle reaches
    /// this callback; do not launch asynchronous preparation from here because
    /// Sparkle does not wait for this method to return.
    public nonisolated func updater(
        _: SPUUpdater,
        willInstallUpdate item: SUAppcastItem
    ) {
        let version = item.displayVersionString
        Task { @MainActor in
            AppLogger.shared.log("📦 [UpdateService] Installing prepared KeyPath update v\(version)")
        }
    }

    /// Hold Sparkle at its supported pre-install boundary while KeyPath stops
    /// the app-bundled Kanata runtime. The handler is invoked even when shutdown
    /// cannot be proven so an update never remains permanently wedged; the
    /// failure is surfaced and the normal post-relaunch validation remains the
    /// authority for recovery.
    public nonisolated func updater(
        _: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        let version = item.displayVersionString
        let handler = SparkleInstallHandler(installHandler)
        Task { @MainActor in
            defer {
                AppLogger.shared.log("▶️ [UpdateService] Runtime preparation finished; releasing Sparkle installer")
                handler.invoke()
            }
            await prepareForUpdate(version: version)
        }
        return true
    }

    public nonisolated func updater(_: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        Task { @MainActor in
            let feedURL = updaterController?.updater.feedURL?.absoluteString
                ?? (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "(missing)")
            if Self.isCosmeticSparkleOutcome(nsError) {
                AppLogger.shared.info(
                    "ℹ️ [UpdateService] Sparkle update check finished with no update available: \(nsError.localizedDescription) | feed=\(feedURL)"
                )
            } else {
                AppLogger.shared.error(
                    "❌ [UpdateService] Sparkle aborted update cycle: \(nsError.domain) \(nsError.code) - \(nsError.localizedDescription) | feed=\(feedURL)"
                )
            }
        }
    }

    public nonisolated func updater(
        _: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        let nsError = (error as NSError?)
        Task { @MainActor in
            let feedURL = updaterController?.updater.feedURL?.absoluteString
                ?? (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "(missing)")
            if let nsError {
                if Self.isCosmeticSparkleOutcome(nsError) {
                    // "You're up to date!" surfaces through this delegate callback as an
                    // NSError (SUNoUpdateError) even though it's the expected, healthy
                    // outcome of a check — not a real failure. Log at info, not error.
                    AppLogger.shared.info(
                        "ℹ️ [UpdateService] Sparkle finished update cycle (\(updateCheck.rawValue)) - up to date | feed=\(feedURL)"
                    )
                } else {
                    AppLogger.shared.error(
                        "⚠️ [UpdateService] Sparkle finished update cycle with error (\(updateCheck.rawValue)): \(nsError.domain) \(nsError.code) - \(nsError.localizedDescription) | feed=\(feedURL)"
                    )
                }
            } else {
                AppLogger.shared.log(
                    "✅ [UpdateService] Sparkle finished update cycle (\(updateCheck.rawValue)) | feed=\(feedURL)"
                )
            }
        }
    }

    /// Sparkle's `SUNoUpdateError` code (see Sparkle/SUErrors.h). Sparkle reports
    /// "You're up to date!" through the delegate's error path using this code —
    /// referenced by raw value since the generated Swift name for this ObjC
    /// NS_ENUM case isn't reliably importable here.
    private static let sparkleNoUpdateErrorCode = 1001

    /// Whether a Sparkle-reported "error" is actually a cosmetic, expected
    /// outcome (e.g. "You're up to date!" is delivered via the delegate's
    /// error path as `SUNoUpdateError`) rather than a genuine failure.
    static func isCosmeticSparkleOutcome(_ error: NSError) -> Bool {
        error.domain == SUSparkleErrorDomain && error.code == sparkleNoUpdateErrorCode
    }
}

// MARK: - Post-Relaunch Handler (separate extension to silence spurious warning)

extension UpdateService {
    enum UpdateRepairDecision: Equatable {
        case silentContinue(reason: String)
        case runtimeShutdownRequired(reason: String)
        case userRepairRequired(reason: String)
        case manualAttentionRequired(reason: String)
    }

    /// Called after the app relaunches following an update.
    /// Post-update detection must be passive: surface degraded state through
    /// the normal status/wizard path and let the user start repair explicitly.
    public nonisolated func updaterDidRelaunchApplication(_: SPUUpdater) {
        Task { @MainActor in
            await finalizeUpdate()
        }
    }

    // MARK: - Update Lifecycle

    @MainActor
    private func prepareForUpdate(version: String) async {
        AppLogger.shared.log("⏸️ [UpdateService] Preparing for update to v\(version) - stopping services")

        let engine = InstallerEngine()
        let broker = PrivilegeBroker()

        let context = await engine.inspectSystem()
        AppLogger.shared.log(
            "📊 [UpdateService] Current state - kanata: \(context.services.kanataRunning), helper: \(context.helper.isInstalled)"
        )

        switch Self.preUpdateDecision(for: context) {
        case let .silentContinue(reason):
            AppLogger.shared.log("✅ [UpdateService] Pre-update: no preparation needed (\(reason))")
        case let .runtimeShutdownRequired(reason):
            AppLogger.shared.log("⏸️ [UpdateService] Pre-update: stopping bundled Kanata runtime (\(reason))")
            let report = await engine.runSingleAction(.terminateConflictingProcesses, using: broker)
            if report.success {
                AppLogger.shared.log("✅ [UpdateService] Bundled Kanata runtime stopped before update")
            } else {
                AppLogger.shared.error(
                    "⚠️ [UpdateService] Could not prove Kanata stopped before update: \(report.failureReason ?? "unknown error")"
                )
            }
        case let .userRepairRequired(reason), let .manualAttentionRequired(reason):
            AppLogger.shared.error(
                "⚠️ [UpdateService] Pre-update repair not allowed for decision \(reason); continuing without mutation"
            )
        }
    }

    @MainActor
    private func finalizeUpdate() async {
        let engine = InstallerEngine()
        let context = await engine.inspectSystem()

        switch Self.postUpdateDecision(for: context) {
        case let .silentContinue(reason):
            AppLogger.shared.log("✅ [UpdateService] Post-update: system healthy, skipping repair (\(reason))")
        case let .userRepairRequired(reason):
            AppLogger.shared.warn(
                "⚠️ [UpdateService] Post-update repair required (\(reason)); surfacing status for user-initiated repair"
            )
            MainAppStateController.shared.invalidateValidationCooldown()
            await MainAppStateController.shared.revalidate()
        case let .manualAttentionRequired(reason):
            AppLogger.shared.error(
                "⚠️ [UpdateService] Post-update requires manual attention (\(reason)); surfacing status and skipping automatic repair"
            )
            MainAppStateController.shared.invalidateValidationCooldown()
            await MainAppStateController.shared.revalidate()
        case let .runtimeShutdownRequired(reason):
            AppLogger.shared.error(
                "⚠️ [UpdateService] Unexpected post-update shutdown decision (\(reason)); surfacing status instead"
            )
            MainAppStateController.shared.invalidateValidationCooldown()
            await MainAppStateController.shared.revalidate()
        }
    }

    nonisolated static func preUpdateDecision(for context: SystemContext) -> UpdateRepairDecision {
        if context.services.kanataRunning || context.services.karabinerDaemonRunning || context.helper.isInstalled {
            return .runtimeShutdownRequired(reason: "reason_code=services_or_helper_present")
        }
        return .silentContinue(reason: "reason_code=nothing_running")
    }

    nonisolated static func postUpdateDecision(for context: SystemContext) -> UpdateRepairDecision {
        // KeyPath's own Input Monitoring is soft (overlay/record only, not
        // remapping — see PermissionOracle.blockingIssue / isSystemReady), so it
        // must not force a hard post-update repair now that IOHIDCheckAccess makes
        // it authoritatively .denied (#931). KeyPath's Accessibility is required.
        if context.permissions.keyPath.accessibility.isBlocking {
            return .manualAttentionRequired(reason: "reason_code=keypath_permissions_blocking")
        }
        if context.permissions.kanata.inputMonitoring.isBlocking || context.permissions.kanata.accessibility.isBlocking {
            return .manualAttentionRequired(reason: "reason_code=kanata_permissions_blocking")
        }

        if !context.helper.isReady {
            return .userRepairRequired(reason: "reason_code=helper_not_ready")
        }
        if !context.components.hasAllRequired {
            return .userRepairRequired(reason: "reason_code=components_not_ready")
        }
        if !context.services.backgroundServicesHealthy || !context.services.kanataRunning {
            return .userRepairRequired(reason: "reason_code=services_not_ready")
        }

        return .silentContinue(reason: "reason_code=healthy")
    }
}
