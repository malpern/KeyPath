import Foundation

extension RuleCollectionsManager {
    /// Admission precedes snapshots and mutation. Nested internal calls carry an
    /// explicit permit; callbacks without one fail rather than deadlock/reenter.
    func withRuleMutation<Result: Sendable>(
        using permit: ConfigurationOperationGate.Permit? = nil,
        failure: Result,
        _ operation: @escaping @MainActor @Sendable (ConfigurationOperationGate.Permit) async -> Result
    ) async -> Result {
        do {
            return try await configurationService.operationGate.withOperation(using: permit) { @MainActor admitted in
                await operation(admitted)
            }
        } catch is CancellationError {
            return failure
        } catch {
            onError?(error.localizedDescription)
            return failure
        }
    }
}
