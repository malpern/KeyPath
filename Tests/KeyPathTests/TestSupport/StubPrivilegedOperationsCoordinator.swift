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

    func cleanupPrivilegedHelper() async throws {
        try record("cleanupPrivilegedHelper")
    }

    func installRequiredRuntimeServices() async throws {
        try record("installRequiredRuntimeServices")
    }

    func recoverRequiredRuntimeServices() async throws {
        try record("recoverRequiredRuntimeServices")
    }

    func installServicesIfUninstalled(context _: String) async throws -> Bool {
        try record("installServicesIfUninstalled")
        return false
    }

    func installNewsyslogConfig() async throws {
        try record("installNewsyslogConfig")
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

    func activateVirtualHIDManager() async throws {
        try record("activateVirtualHIDManager")
    }

    func terminateProcess(pid _: Int32) async throws {
        try record("terminateProcess")
    }

    func killAllKanataProcesses() async throws {
        try record("killAllKanataProcesses")
    }

    func stopKanataDaemonService() async throws {
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
