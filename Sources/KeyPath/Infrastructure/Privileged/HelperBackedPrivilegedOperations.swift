import Foundation
import KeyPathCore

/// Helper-backed implementation of PrivilegedOperations.
/// Uses the SMAppService/XPC helper via PrivilegedOperationsCoordinator, with
/// clear, explicit logging on fallback to the legacy AppleScript path.
public struct HelperBackedPrivilegedOperations: PrivilegedOperations {
    public init() {}

    public func startKanataService() async -> Bool {
        do {
            AppLogger.shared.log("🔐 [PrivOps] Helper-first startKanataService")
            try await PrivilegedOperationsCoordinator.shared.restartUnhealthyServices()
            return true
        } catch {
            AppLogger.shared.log("🚨 [PrivOps] FALLBACK: helper restartUnhealthyServices failed: \(error.localizedDescription). Using AppleScript path.")
            return await LegacyPrivilegedOperations().startKanataService()
        }
    }

    public func restartKanataService() async -> Bool {
        do {
            AppLogger.shared.log("🔐 [PrivOps] Helper-first restartKanataService")
            try await PrivilegedOperationsCoordinator.shared.restartUnhealthyServices()
            return true
        } catch {
            AppLogger.shared.log("🚨 [PrivOps] FALLBACK: helper restartUnhealthyServices failed: \(error.localizedDescription). Using AppleScript path.")
            return await LegacyPrivilegedOperations().restartKanataService()
        }
    }

    public func stopKanataService() async -> Bool {
        do {
            AppLogger.shared.log("🔐 [PrivOps] Helper-first stopKanataService (killAllKanataProcesses)")
            try await PrivilegedOperationsCoordinator.shared.killAllKanataProcesses()
            return true
        } catch {
            AppLogger.shared.log("🚨 [PrivOps] FALLBACK: helper killAllKanataProcesses failed: \(error.localizedDescription). Using AppleScript path.")
            return await LegacyPrivilegedOperations().stopKanataService()
        }
    }
}

