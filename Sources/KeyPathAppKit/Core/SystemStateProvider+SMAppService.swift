import KeyPathCore
import ServiceManagement

public extension SystemStateProvider {
    /// Synchronous SMAppService status bridge for legacy call sites that cannot
    /// yet await the cached provider.
    ///
    /// Kept behind `SystemStateProvider` so Phase 1 has one owner for status
    /// evidence while the full immutable snapshot is introduced.
    nonisolated func smAppServiceStatusSynchronously(for plistName: String) -> SMAppService.Status {
        SMAppServiceStatusProvider.statusSynchronously(for: plistName)
    }

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
