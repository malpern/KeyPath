// Bridges the KindaVim pack's install/uninstall state to the live
// helpers it depends on (`KindaVimStateAdapter` for mode signals,
// `KindaVimStrategyMonitor` for per-app strategy tracking). Started
// once at app launch; observes `installedPacksChanged` and refcount-
// starts/stops both monitors as the user toggles the pack from
// Gallery (or Pack Detail).

import Foundation
import KeyPathCore

@MainActor
final class KindaVimPackController {
    static let shared = KindaVimPackController()

    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .installedPacksChanged,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await KindaVimPackController.shared.refresh()
            }
        }
        // Apply initial state.
        Task { await refresh() }
    }

    func stop() {
        observer.map(NotificationCenter.default.removeObserver)
        observer = nil
        if isMonitoring {
            KindaVimStateAdapter.shared.stopMonitoring()
            KindaVimStrategyMonitor.shared.stopMonitoring()
            isMonitoring = false
        }
    }

    /// Tracks whether we currently hold refcounts on the adapter / strategy
    /// monitor so we balance start/stop calls without double-decrementing.
    private var isMonitoring = false

    private func refresh() async {
        let installed = await InstalledPackTracker.shared.isInstalled(packID: PackRegistry.kindaVim.id)
        if installed, !isMonitoring {
            KindaVimStateAdapter.shared.startMonitoring()
            KindaVimStrategyMonitor.shared.startMonitoring()
            isMonitoring = true
        } else if !installed, isMonitoring {
            KindaVimStateAdapter.shared.stopMonitoring()
            KindaVimStrategyMonitor.shared.stopMonitoring()
            isMonitoring = false
        }
    }
}
