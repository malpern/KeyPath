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

/// Records delegate evidence inline, before an asynchronous main-actor hop can
/// lose a race with AppKit termination. Sparkle may finish a successful check
/// while its external installer remains staged for Quit.
final class UpdateTerminationExpectation: @unchecked Sendable {
    private let lock = NSLock()
    private var expected = false
    private var staged = false

    var isExpected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return expected
    }

    func willExtract() {
        lock.lock()
        defer { lock.unlock() }
        expected = true
    }

    func willInstall() {
        lock.lock()
        defer { lock.unlock() }
        expected = true
        staged = true
    }

    func didFinishCycle(errorOccurred: Bool) {
        // Successful cycle completion is not installer cancellation.
        if errorOccurred { didAbort() }
    }

    func didAbort() {
        lock.lock()
        defer { lock.unlock() }
        // An error during a later update check does not prove that a previously
        // staged external installer has gone away. Keep that evidence.
        if !staged { expected = false }
    }
}

/// Manages application updates via Sparkle framework
///
/// This service handles:
/// - Automatic update checks (every 24 hours)
/// - Manual "Check for Updates" menu action
/// - Pre/post-install hooks to properly stop/restart KeyPath services
///
/// Runtime shutdown uses the existing admitted lifecycle owner.
@Observable
@MainActor
public final class UpdateService: NSObject {
    // MARK: - Singleton

    public static let shared = UpdateService()

    // MARK: - Properties

    @ObservationIgnored private nonisolated let terminationExpectation = UpdateTerminationExpectation()

    var isUpdateTerminationExpected: Bool {
        terminationExpectation.isExpected
    }

    @ObservationIgnored private var updaterController: SPUStandardUpdaterController?
    @ObservationIgnored private let channelDefaultsKey = "keypath.update.channel"

    @ObservationIgnored private var stopRuntime: (@MainActor () async -> Bool)?
    @ObservationIgnored private var setUpdatePreparation: (@MainActor (Bool) -> Void)?
    @ObservationIgnored private var pendingInstallHandler: SparkleInstallHandler?
    @ObservationIgnored private var pendingInstallVersion: String?
    @ObservationIgnored private var isPreparingInstallation = false
    public private(set) var preparationError: String?

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

    func configureRuntimeStop(_ stop: @escaping @MainActor () async -> Bool) {
        stopRuntime = stop
    }

    func configureUpdatePreparation(_ setPreparation: @escaping @MainActor (Bool) -> Void) {
        setUpdatePreparation = setPreparation
    }

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
        if pendingInstallHandler != nil {
            Task { @MainActor in await resumePreparedUpdate() }
        } else {
            updaterController?.checkForUpdates(nil)
        }
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

    /// Observed synchronously before Sparkle launches its installer for the
    /// downloaded archive. This is evidence, not a universal postponement hook.
    public nonisolated func updater(_: SPUUpdater, willExtractUpdate _: SUAppcastItem) {
        terminationExpectation.willExtract()
    }

    public nonisolated func updater(
        _: SPUUpdater,
        willInstallUpdateOnQuit _: SUAppcastItem,
        immediateInstallationBlock _: @escaping () -> Void
    ) -> Bool {
        terminationExpectation.willInstall()
        // Sparkle always attempts installation on termination, with either
        // return value. Observe it without taking over its scheduler.
        return false
    }

    /// Notification only: Sparkle does not await asynchronous work here, and
    /// its relaunch postponement callback is not guaranteed on every path.
    public nonisolated func updater(
        _: SPUUpdater,
        willInstallUpdate item: SUAppcastItem
    ) {
        terminationExpectation.willInstall()
        let version = item.displayVersionString
        Task { @MainActor in
            AppLogger.shared.log("📦 [UpdateService] Installing KeyPath update v\(version)")
        }
    }

    /// Delay Sparkle's relaunch until owned runtime and Caps cleanup succeeds.
    /// Failure remains paused; an explicit Check for Updates retries preparation.
    public nonisolated func updater(
        _: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        terminationExpectation.willInstall()
        let version = item.displayVersionString
        let handler = SparkleInstallHandler(installHandler)
        Task { @MainActor in
            await postponeInstallation(version: version, handler: handler)
        }
        return true
    }

    public nonisolated func updater(_: SPUUpdater, didAbortWithError error: Error) {
        terminationExpectation.didAbort()
        let nsError = error as NSError
        Task { @MainActor in
            cancelPreparedUpdate()
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
        // A nil-error completion can leave the external installer staged for
        // Quit. It must not clear the synchronously observed expectation.
        terminationExpectation.didFinishCycle(errorOccurred: nsError != nil)
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
    /// Called after the app relaunches following an update.
    /// Post-update detection must be passive: surface degraded state through
    /// the normal status/wizard path and let the user start repair explicitly.
    public nonisolated func updaterDidRelaunchApplication(_: SPUUpdater) {
        Task { @MainActor in
            await finalizeUpdate()
        }
    }

    // MARK: - Update Lifecycle

    #if DEBUG
        static func testService() -> UpdateService { UpdateService() }
    #endif

    private func postponeInstallation(version: String, handler: SparkleInstallHandler) async {
        pendingInstallHandler = handler
        pendingInstallVersion = version
        if isPreparingInstallation { setUpdatePreparation?(true) }
        await resumePreparedUpdate()
    }

    func postponeInstallation(version: String, install: @escaping () -> Void) async {
        await postponeInstallation(version: version, handler: SparkleInstallHandler(install))
    }

    func cancelPreparedUpdate() {
        pendingInstallHandler = nil
        pendingInstallVersion = nil
        preparationError = nil
        setUpdatePreparation?(false)
    }

    @MainActor
    private func resumePreparedUpdate() async {
        guard !isPreparingInstallation, let handler = pendingInstallHandler,
              let version = pendingInstallVersion else { return }
        isPreparingInstallation = true
        setUpdatePreparation?(true)
        defer {
            isPreparingInstallation = false
            if let next = pendingInstallHandler, next !== handler {
                Task { @MainActor in await resumePreparedUpdate() }
            }
        }
        let prepared = await Self.continueAfterRuntimeCleanup(
            stop: { [self] in await prepareForUpdate(version: version) },
            install: { [self] in
                guard pendingInstallHandler === handler else { return }
                pendingInstallHandler = nil
                pendingInstallVersion = nil
                preparationError = nil
                handler.invoke()
            }
        )
        if !prepared, pendingInstallHandler === handler {
            setUpdatePreparation?(false)
        }
        if !prepared, pendingInstallHandler === handler {
            let reason = "Update paused because keyboard cleanup could not be verified. Resolve the runtime issue in Settings, then choose Check for Updates to retry."
            preparationError = reason
            canCheckForUpdates = true
            AppLogger.shared.error("⚠️ [UpdateService] \(reason)")
            UserNotificationService.shared.notifyConfigEvent("Update paused", body: reason, key: "update.runtime-cleanup")
        }
    }

    /// One continuation after successful admitted cleanup; refusal does not install.
    @MainActor
    static func continueAfterRuntimeCleanup(stop: () async -> Bool, install: () -> Void) async -> Bool {
        guard await stop() else { return false }
        install()
        return true
    }

    @MainActor
    private func prepareForUpdate(version: String) async -> Bool {
        AppLogger.shared.log("⏸️ [UpdateService] Stopping owned runtime before update to v\(version)")
        // Always run cleanup, including a retained Caps journal with no live worker.
        guard let stopRuntime else { return false }
        return await stopRuntime()
    }

    @MainActor
    private func finalizeUpdate() async {
        // Use the same driverless readiness path as normal launch. No obsolete
        // driver/helper requirements or automatic installer repair after update.
        MainAppStateController.shared.invalidateValidationCooldown()
        await MainAppStateController.shared.revalidate()
    }
}
