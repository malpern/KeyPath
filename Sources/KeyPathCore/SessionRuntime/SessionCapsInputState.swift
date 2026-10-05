/// Pure admission for the session's reserved F18 transport. A captured F18 event
/// cannot identify a device or distinguish substituted Caps from native F18.
/// Callers must establish the managed lease and serialize its lifecycle with input.
public struct SessionCapsInputState: Sendable {
    public static let logicalCapsUsage: UInt32 = 57
    public static let capturedF18Usage: UInt32 = 109

    public private(set) var leaseGeneration: String?
    private var admittedPressGeneration: String?

    public init() {}

    /// Repeating activation for the same lease preserves its admitted press.
    /// A replacement lease must supply a fresh generation, even on the same device.
    public mutating func activate(generation: String) {
        guard !generation.isEmpty else {
            revoke()
            return
        }
        if leaseGeneration != generation { admittedPressGeneration = nil }
        leaseGeneration = generation
    }

    /// Clears admission; subsequent releases/repeats cannot belong to this lease.
    /// The worker remains responsible for releasing its runtime/output ledger.
    public mutating func revoke() {
        leaseGeneration = nil
        admittedPressGeneration = nil
    }

    /// nil means leave the captured event physical. Ordinary input is returned
    /// unchanged for the worker's existing mapped-input and press-ledger checks.
    /// Raw Caps always passes through because its WindowServer latch is upstream.
    public func logicalUsage(capturedUsage: UInt32, value: UInt64) -> UInt32? {
        guard value <= 2, capturedUsage != Self.logicalCapsUsage else { return nil }
        guard capturedUsage == Self.capturedF18Usage else { return capturedUsage }
        guard let leaseGeneration,
              value == 1 || admittedPressGeneration == leaseGeneration
        else { return nil }
        return Self.logicalCapsUsage
    }

    /// Commit only after runtime input enqueue succeeds. Merely translating a
    /// candidate must not authorize its later repeat/release. The generation
    /// rejects completion from an earlier lease after revocation or replacement.
    public mutating func didAdmit(capturedUsage: UInt32, value: UInt64, generation: String) {
        guard capturedUsage == Self.capturedF18Usage,
              generation == leaseGeneration,
              logicalUsage(capturedUsage: capturedUsage, value: value) == Self.logicalCapsUsage
        else { return }
        if value == 1 { admittedPressGeneration = generation }
        if value == 0 { admittedPressGeneration = nil }
    }
}
