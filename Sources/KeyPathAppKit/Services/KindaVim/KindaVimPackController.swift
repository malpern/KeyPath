// Bridges the KindaVim pack's install/uninstall state to the
// `KindaVimModeMonitor`. Started once at app launch; observes
// `installedPacksChanged` and starts/stops the monitor as the user
// toggles the pack from Gallery (or Pack Detail).

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
        KindaVimModeMonitor.shared.stop()
    }

    private func refresh() async {
        let installed = await InstalledPackTracker.shared.isInstalled(packID: PackRegistry.kindaVim.id)
        if installed {
            KindaVimModeMonitor.shared.start()
        } else {
            KindaVimModeMonitor.shared.stop()
        }
    }
}
