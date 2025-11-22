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
            if error.isSMAppServiceApprovalRequired {
                AppLogger.shared.log(
                    "⚠️ [PrivOps] Helper start requires Background Items approval. Prompting user instead of falling back to legacy path."
                )
                NotificationCenter.default.post(name: .smAppServiceApprovalRequired, object: nil)
                return false
            }
            AppLogger.shared.log(
                "❌ [PrivOps] Helper restartUnhealthyServices failed: \(error.localizedDescription)")
            return false
        }
    }

    public func restartKanataService() async -> Bool {
        do {
            AppLogger.shared.log("🔐 [PrivOps] Helper-first restartKanataService")
            try await PrivilegedOperationsCoordinator.shared.restartUnhealthyServices()
            return true
        } catch {
            if error.isSMAppServiceApprovalRequired {
                AppLogger.shared.log(
                    "⚠️ [PrivOps] Helper restart requires Background Items approval. Prompting user instead of falling back to legacy path."
                )
                NotificationCenter.default.post(name: .smAppServiceApprovalRequired, object: nil)
                return false
            }
            AppLogger.shared.log(
                "❌ [PrivOps] Helper restartUnhealthyServices failed: \(error.localizedDescription)")
            return false
        }
    }

    public func stopKanataService() async -> Bool {
        do {
            AppLogger.shared.log("🔐 [PrivOps] Helper-first stopKanataService (killAllKanataProcesses)")
            try await PrivilegedOperationsCoordinator.shared.killAllKanataProcesses()
            return true
        } catch {
            AppLogger.shared.log(
                "❌ [PrivOps] helper killAllKanataProcesses failed: \(error.localizedDescription)")
            return false
        }
    }
}

private extension Error {
    var isSMAppServiceApprovalRequired: Bool {
        if let privilegedError = self as? PrivilegedOperationError {
            switch privilegedError {
            case let .installationFailed(message), let .operationFailed(message):
                return message.lowercased().contains("approval required in system settings")
            case .commandFailed, .executionError:
                return false
            }
        }

        let description = localizedDescription.lowercased()
        return description.contains("approval required in system settings")
    }
}
