import Foundation

public struct OperationTimeoutError: LocalizedError {
    public init() {}

    public var errorDescription: String? {
        "Operation timed out"
    }
}

/// Controls whether a timed-out or cancelled call waits for its operation to finish.
public enum TimeoutCancellation: Sendable {
    /// Use for reads whose late results can be discarded.
    case returnImmediately
    /// Use for mutations that must finish cancellation and cleanup before the caller proceeds.
    case waitForOperation
}

/// Run an async operation against a monotonic deadline. Timeout and caller
/// cancellation both cancel the operation; the cancellation policy determines
/// whether the caller waits for a non-cooperative operation to finish.
public func withTimeout<T: Sendable>(
    _ duration: Duration,
    cancellation: TimeoutCancellation,
    operation: @escaping @isolated(any) @Sendable () async throws -> T
) async throws -> T {
    try Task.checkCancellation()
    guard duration > .zero else { throw OperationTimeoutError() }

    let deadline = ContinuousClock.now.advanced(by: duration)
    let (stream, continuation) = AsyncThrowingStream<T, Error>.makeStream()

    let operationTask = Task {
        do {
            try Task.checkCancellation()
            let value = try await operation()
            continuation.yield(value)
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }
    let deadlineTask = Task {
        do {
            try await Task.sleep(until: deadline, clock: .continuous)
            continuation.finish(throwing: OperationTimeoutError())
        } catch {
            // The operation completed or the caller cancelled.
        }
    }

    // A task group always joins its children. The stream lets a read discard
    // late work while callers that own mutations can still wait for cleanup.
    do {
        var iterator = stream.makeAsyncIterator()
        guard let value = try await iterator.next() else { throw CancellationError() }
        try Task.checkCancellation()
        deadlineTask.cancel()
        return value
    } catch {
        deadlineTask.cancel()
        operationTask.cancel()
        if cancellation == .waitForOperation {
            await operationTask.value
        }
        throw error
    }
}
