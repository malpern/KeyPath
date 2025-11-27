import Foundation

/// Centralized, test-friendly sleep helpers for wizard flows.
/// Uses `ContinuousClock` instead of direct task sleeping so we can lint and
/// override later for determinism.
enum WizardSleep {
    private static let clock = ContinuousClock()

    /// Pause for a number of milliseconds (cancellable).
    @discardableResult
    static func ms(_ value: Int) async -> Bool {
        do {
            try await clock.sleep(for: .milliseconds(value))
            return true
        } catch {
            return false
        }
    }

    /// Pause for fractional seconds (cancellable).
    @discardableResult
    static func seconds(_ value: Double) async -> Bool {
        let millis = Int((value * 1000).rounded())
        return await ms(millis)
    }
}
