@testable import KeyPathAppKit

@MainActor
final class StubPrivilegedOperationsCoordinator: PrivilegedOperationsCoordinating {
    var calls: [String] = []
    var failOnCall: String?

    private func record(_ name: String) throws {
        if failOnCall == name {
            throw StubError.forced
        }
        calls.append(name)
    }

    func installLaunchDaemon(plistPath _: String, serviceID _: String) async throws {
        try record("installLaunchDaemon")
    }

    func cleanupPrivilegedHelper() async throws {
        try record("cleanupPrivilegedHelper")
    }

    func installAllLaunchDaemonServices(kanataBinaryPath _: String, kanataConfigPath _: String, tcpPort _: Int) async throws {
        try record("installAllLaunchDaemonServices")
    }

    func installAllLaunchDaemonServices() async throws {
        try record("installAllLaunchDaemonServices")
    }

    func restartUnhealthyServices() async throws {
        try record("restartUnhealthyServices")
    }

    func installServicesIfUninstalled(context _: String) async throws -> Bool {
        try record("installServicesIfUninstalled")
        return false
    }

    func installLaunchDaemonServicesWithoutLoading() async throws {
        try record("installLaunchDaemonServicesWithoutLoading")
    }

    func installLogRotation() async throws {
        try record("installLogRotation")
    }

    func regenerateServiceConfiguration() async throws {
        try record("regenerateServiceConfiguration")
    }

    func repairVHIDDaemonServices() async throws {
        try record("repairVHIDDaemonServices")
    }

    func downloadAndInstallCorrectVHIDDriver() async throws {
        try record("downloadAndInstallCorrectVHIDDriver")
    }

    func installBundledKanata() async throws {
        try record("installBundledKanata")
    }

    func activateVirtualHIDManager() async throws {
        try record("activateVirtualHIDManager")
    }

    func terminateProcess(pid _: Int32) async throws {
        try record("terminateProcess")
    }

    func killAllKanataProcesses() async throws {
        try record("killAllKanataProcesses")
    }

    func stopKanataService() async throws {
        try record("stopKanataService")
    }

    func restartKarabinerDaemonVerified() async throws -> Bool {
        try record("restartKarabinerDaemonVerified")
        return true
    }

    func uninstallVirtualHIDDrivers() async throws {
        try record("uninstallVirtualHIDDrivers")
    }

    func disableKarabinerGrabber() async throws {
        try record("disableKarabinerGrabber")
    }

    func sudoExecuteCommand(_ command: String, description _: String) async throws {
        try record("sudoExecuteCommand:\(command)")
    }

    enum StubError: Error {
        case forced
    }
}
