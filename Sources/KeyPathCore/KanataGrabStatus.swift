import Foundation

/// Authoritative input-grab status reported by kanata over its TCP channel
/// (`ServerMessage::InputGrab`, added in the bundled fork for KeyPath #630).
///
/// This is ground truth straight from kanata's OS grab layer — it is NOT
/// inferred from key-event flow, so it is immune to the "no keys seen"
/// ambiguity (idle user vs. failed grab vs. synthetic/VNC input that bypasses
/// the physical seize).
public struct KanataInputGrabStatus: Sendable, Equatable {
    /// True when kanata currently has at least one physical device seized.
    public let active: Bool
    /// Names of the currently seized devices. Empty when `active` is false.
    public let devices: [String]
    /// Optional human-readable explanation, typically populated on failure
    /// (e.g. another process holds an exclusive grab, not running as root).
    public let reason: String?
    /// Wall-clock time KeyPath observed the status. Diagnostics/logging only.
    public let observedAt: Date

    public init(active: Bool, devices: [String], reason: String?, observedAt: Date) {
        self.active = active
        self.devices = devices
        self.reason = reason
        self.observedAt = observedAt
    }
}
