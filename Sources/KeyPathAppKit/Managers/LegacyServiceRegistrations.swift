import KeyPathCore
import KeyPathInstallationWizard
import ServiceManagement

/// Drops the SMAppService registrations KeyPath 1.0.1 made for its kanata daemon
/// and helper (#1353). Migration only: this never registers anything.
///
/// Best effort, and it needs no administrator prompt. Release builds no longer
/// ship those plists, so ServiceManagement usually reports them not found and
/// this does nothing; a stale Login Items entry may then remain until macOS
/// drops it. The root batch boots the jobs out regardless, and success is
/// judged by that batch's verification, never by these calls.
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
                logs.append("[legacy-cleanup] \(plistName): unregister failed (\(error.localizedDescription)); the administrator step boots the job out")
            }
            await SystemStateProvider.shared.invalidateSMAppServiceStatus(plistName: plistName)
        }
        return logs
    }
}
