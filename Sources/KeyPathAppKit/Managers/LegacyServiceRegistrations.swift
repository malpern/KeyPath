import KeyPathCore
import KeyPathInstallationWizard
import ServiceManagement

/// Drops the SMAppService registrations KeyPath 1.0.1 made for its kanata daemon
/// and helper (#1353). Migration only: this never registers anything.
///
/// Best effort, and it needs no administrator prompt. Current builds no longer
/// ship those plists, so ServiceManagement often cannot resolve them; the root
/// cleanup batch boots the jobs out regardless. Success is judged by that
/// batch's verification, never by these calls.
@MainActor
enum LegacyServiceRegistrations {
    static func unregister() async -> [String] {
        await unregister(
            statusFor: { await SystemStateProvider.shared.freshSMAppServiceStatus(for: $0) },
            service: { HelperManager.smServiceFactory($0) }
        )
    }

    static func unregister(
        statusFor: (String) async -> SMAppService.Status,
        service: (String) -> SMAppServiceProtocol
    ) async -> [String] {
        var logs: [String] = []
        for plistName in LegacyPrivilegedRuntime.serviceManagementPlists {
            let initial = await statusFor(plistName)
            guard initial == .enabled || initial == .requiresApproval else {
                logs.append("[legacy-cleanup] \(plistName): not registered with ServiceManagement")
                continue
            }
            do {
                try await service(plistName).unregister()
                logs.append("[legacy-cleanup] \(plistName): unregistered")
            } catch {
                logs.append("[legacy-cleanup] \(plistName): unregister failed (\(error.localizedDescription)); removing as administrator")
            }
            await SystemStateProvider.shared.invalidateSMAppServiceStatus(plistName: plistName)
        }
        return logs
    }
}
