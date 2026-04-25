// Live, observable wrapper around `KindaVimStrategyResolver`. Watches
// kindaVim's prefs plist and the frontmost macOS app, republishes a
// `currentStrategy` every time either input changes.
//
// Used by:
// - The Pack Detail status block (strategy badge)
// - The vim-hint UI to filter the static `VimBindings` table down to
//   commands the active strategy actually supports

import AppKit
import KeyPathCore
import Observation

@MainActor
@Observable
final class KindaVimStrategyMonitor {
    static let shared = KindaVimStrategyMonitor()

    private(set) var currentStrategy: KindaVimStrategy = .accessibility
    private(set) var currentBundleID: String?

    @ObservationIgnored
    private var lists: KindaVimStrategyResolver.PreferenceLists = .empty

    @ObservationIgnored
    private let resolver: KindaVimStrategyResolver

    @ObservationIgnored
    private var monitoringCount = 0

    @ObservationIgnored
    private var plistWatcher: ConfigFileWatcher?

    @ObservationIgnored
    private var frontmostObserver: NSObjectProtocol?

    init(resolver: KindaVimStrategyResolver = KindaVimStrategyResolver()) {
        self.resolver = resolver
    }

    /// Refcounted start. Idempotent across multiple callers.
    func startMonitoring() {
        monitoringCount += 1
        guard monitoringCount == 1 else { return }

        AppLogger.shared.log("👀 [KindaVimStrategy] Starting monitor")

        lists = resolver.loadPreferenceLists()
        currentBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        recomputeStrategy()

        let watcher = ConfigFileWatcher()
        watcher.startWatching(path: KindaVimStrategyResolver.defaultPreferencesURL.path) { [weak self] in
            await self?.handlePreferencesChanged()
        }
        plistWatcher = watcher

        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
            Task { @MainActor in
                self?.handleFrontmostAppChanged(bundleID: app.bundleIdentifier)
            }
        }
    }

    func stopMonitoring() {
        guard monitoringCount > 0 else { return }
        monitoringCount -= 1
        guard monitoringCount == 0 else { return }

        AppLogger.shared.log("🛑 [KindaVimStrategy] Stopping monitor")

        plistWatcher?.stopWatching()
        plistWatcher = nil

        if let token = frontmostObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        frontmostObserver = nil
    }

    // MARK: - Reactions

    private func handlePreferencesChanged() async {
        let newLists = resolver.loadPreferenceLists()
        guard newLists != lists else { return }
        lists = newLists
        AppLogger.shared.log("👀 [KindaVimStrategy] Prefs plist changed; recomputing")
        recomputeStrategy()
    }

    private func handleFrontmostAppChanged(bundleID: String?) {
        guard bundleID != currentBundleID else { return }
        currentBundleID = bundleID
        recomputeStrategy()
    }

    private func recomputeStrategy() {
        let resolved = resolver.strategy(for: currentBundleID, lists: lists)
        guard resolved != currentStrategy else { return }
        currentStrategy = resolved
        AppLogger.shared.log(
            "👀 [KindaVimStrategy] strategy → \(resolved.rawValue) (bundle=\(currentBundleID ?? "nil"))"
        )
        // Telemetry: sample on every app-switch transition. Off by
        // default; the store gates writes on the user's opt-in flag.
        KindaVimTelemetryStore.shared.recordStrategySample(resolved.rawValue)
    }
}
