import Foundation

/// Shared admission for app operations using one ConfigurationService. Owns no
/// persistence or UI state; a permit explicitly identifies trusted nested work.
actor ConfigurationOperationGate {
    struct Permit: Sendable {
        fileprivate let owner: UUID
        fileprivate let operation: UUID
    }

    enum Failure: LocalizedError {
        case recursiveOperation
        case invalidPermit

        var errorDescription: String? {
            switch self {
            case .recursiveOperation:
                "An operation callback cannot recursively save or restore through the same configuration service."
            case .invalidPermit:
                "The configuration operation permit is no longer active."
            }
        }
    }

    @TaskLocal private static var activeOperations: Set<UUID> = []
    private let owner = UUID()
    private var active: Permit?
    private var waiters: [CheckedContinuation<Permit, Never>] = []

    func withOperation<Result: Sendable>(
        using permit: Permit? = nil,
        _ operation: @Sendable (Permit) async throws -> Result
    ) async throws -> Result {
        if let permit {
            guard permit.owner == owner, permit.operation == active?.operation else {
                throw Failure.invalidPermit
            }
            return try await operation(permit)
        }
        try Task.checkCancellation()
        if let active, Self.activeOperations.contains(active.operation) {
            throw Failure.recursiveOperation
        }
        let admitted = await acquire()
        defer { release() }
        // Cancelled waiters retain their FIFO place, then leave without mutation.
        try Task.checkCancellation()
        var context = Self.activeOperations
        context.insert(admitted.operation)
        return try await Self.$activeOperations.withValue(context) {
            try await operation(admitted)
        }
    }

    private func acquire() async -> Permit {
        if active != nil {
            return await withCheckedContinuation { waiters.append($0) }
        }
        let permit = Permit(owner: owner, operation: UUID())
        active = permit
        return permit
    }

    private func release() {
        guard !waiters.isEmpty else {
            active = nil
            return
        }
        let next = Permit(owner: owner, operation: UUID())
        active = next
        waiters.removeFirst().resume(returning: next)
    }
}
