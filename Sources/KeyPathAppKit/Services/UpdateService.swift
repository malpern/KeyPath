import Foundation
import KeyPathCore
import Sparkle

public enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable = "Stable"
    case beta = "Beta"

    public var id: String {
        rawValue
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
@MainActor
public final class UpdateService: NSObject, ObservableObject {
    // MARK: - Singleton

    public static let shared = UpdateService()

    // MARK: - Properties

    private var updaterController: SPUStandardUpdaterController?
    private let channelDefaultsKey = "keypath.update.channel"

    @Published public private(set) var canCheckForUpdates = false
    @Published public private(set) var lastUpdateCheckDate: Date?
    @Published public private(set) var automaticallyChecksForUpdates = true
    @Published public private(set) var updateChannel: UpdateChannel = .stable
    @Published public private(set) var currentFeedURL: String?

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
            let persistedChannel = loadPersistedChannel()
            setUpdateChannel(persistedChannel)

            AppLogger.shared.log(
                "✅ [UpdateService] Sparkle initialized - autoCheck: \(automaticallyChecksForUpdates), channel: \(updateChannel.rawValue)"
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
        AppLogger.shared.log("⚙️ [UpdateService] Automatic checks set to: \(enabled)")
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

    /// Called before an update is about to be installed
    /// We use this to stop kanata and helper services before Sparkle replaces the app bundle
    public nonisolated func updater(
        _: SPUUpdater,
        willInstallUpdate item: SUAppcastItem
    ) {
        // Extract version string before crossing isolation boundary
        let version = item.displayVersionString
        Task { @MainActor in
            await prepareForUpdate(version: version)
        }
    }

    /// Provide custom appcast item comparison if needed
    public nonisolated func updater(
        _: SPUUpdater,
        shouldPostponeRelaunchForUpdate _: SUAppcastItem,
        untilInvokingBlock _: @escaping () -> Void
    ) -> Bool {
        // Don't postpone - let Sparkle handle the relaunch timing
        false
    }

    public nonisolated func updater(_: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        Task { @MainActor in
            let feedURL = updaterController?.updater.feedURL?.absoluteString
                ?? (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "(missing)")
            AppLogger.shared.error(
                "❌ [UpdateService] Sparkle aborted update cycle: \(nsError.domain) \(nsError.code) - \(nsError.localizedDescription) | feed=\(feedURL)"
            )
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
                AppLogger.shared.error(
                    "⚠️ [UpdateService] Sparkle finished update cycle with error (\(updateCheck.rawValue)): \(nsError.domain) \(nsError.code) - \(nsError.localizedDescription) | feed=\(feedURL)"
                )
            } else {
                AppLogger.shared.log(
                    "✅ [UpdateService] Sparkle finished update cycle (\(updateCheck.rawValue)) | feed=\(feedURL)"
                )
            }
        }
    }
}

// MARK: - Post-Relaunch Handler (separate extension to silence spurious warning)

extension UpdateService {
    /// Called after the app relaunches following an update
    /// We use this to re-register and restart services
    public nonisolated func updaterDidRelaunchApplication(_: SPUUpdater) {
        Task { @MainActor in
            await finalizeUpdate()
        }
    }

    // MARK: - Update Lifecycle

    @MainActor
    private func prepareForUpdate(version: String) async {
        AppLogger.shared.log("⏸️ [UpdateService] Preparing for update to v\(version) - stopping services")

        // Stop kanata + helper via InstallerEngine (per AGENTS.md)
        let engine = InstallerEngine()
        let broker = PrivilegeBroker()

        // Inspect current state
        let context = await engine.inspectSystem()
        AppLogger.shared.log(
            "📊 [UpdateService] Current state - kanata: \(context.services.kanataRunning), helper: \(context.helper.isInstalled)"
        )

        // Run repair intent which will stop services cleanly
        let report = await engine.run(intent: .repair, using: broker)
        AppLogger.shared.log(
            "✅ [UpdateService] Services prepared for update - success: \(report.success)"
        )
    }

    @MainActor
    private func finalizeUpdate() async {
        AppLogger.shared.log("🔄 [UpdateService] Post-update - repairing services")

        // Re-install/repair services after update
        let engine = InstallerEngine()
        let broker = PrivilegeBroker()

        // Run repair to re-register helper and restart kanata
        let report = await engine.run(intent: .repair, using: broker)

        if report.success {
            AppLogger.shared.log("✅ [UpdateService] Services repaired after update")
        } else {
            AppLogger.shared.error(
                "⚠️ [UpdateService] Service repair had issues - user may see wizard"
            )
            // User will see wizard on next interaction if services need attention
        }
    }
}
