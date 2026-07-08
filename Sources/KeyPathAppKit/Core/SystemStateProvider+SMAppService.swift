import KeyPathCore
import ServiceManagement

public extension SystemStateProvider {
    /// Cached SMAppService status read for hot paths.
    ///
    /// Delegates to the existing status provider so the blocking Apple IPC remains
    /// coalesced and off the caller's actor while Phase 1 grows the full snapshot.
    func cachedSMAppServiceStatus(for plistName: String) async -> SMAppService.Status {
        await SMAppServiceStatusProvider.shared.cachedStatus(for: plistName)
    }

    /// Fresh SMAppService status read for post-mutation verification.
    func freshSMAppServiceStatus(for plistName: String) async -> SMAppService.Status {
        await SMAppServiceStatusProvider.shared.freshStatus(for: plistName)
    }

    /// Invalidates cached SMAppService status after a registration mutation.
    func invalidateSMAppServiceStatus(plistName: String) async {
        await SMAppServiceStatusProvider.shared.invalidate(plistName: plistName)
    }
}
