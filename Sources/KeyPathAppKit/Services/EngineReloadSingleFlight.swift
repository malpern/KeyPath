import Foundation
import KeyPathCore

/// Coalesces concurrent engine reload requests into a single in-flight operation.
///
/// Goal: prevent overlapping TCP reloads (and any fallback behaviors) from creating
/// typing reliability issues (service restarts / remap gaps).
actor EngineReloadSingleFlight {
    static let shared = EngineReloadSingleFlight()

    private var inFlight: Task<EngineReloadResult, Never>?

    /// Run `operation` after a small debounce. If another call happens while the
    /// operation is in-flight, it will await the same result.
    func run(
        reason: String,
        debounce: TimeInterval = 0.25,
        operation: @Sendable @escaping () async -> EngineReloadResult
    ) async -> EngineReloadResult {
        if let inFlight {
            AppLogger.shared.debug(
                "🔁 [EngineReload] Coalescing reload request (reason=\(reason))"
            )
            return await inFlight.value
        }

        let start = Date()
        let task = Task { () -> EngineReloadResult in
            if debounce > 0 {
                let ns = UInt64(debounce * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }

            let result = await operation()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            AppLogger.shared.debug(
                "✅ [EngineReload] Reload completed in \(ms)ms (reason=\(reason), success=\(result.isSuccess))"
            )
            return result
        }

        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }
}
