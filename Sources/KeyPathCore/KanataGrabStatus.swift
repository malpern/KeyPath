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
    /// Wall-clock time KeyPath observed the status. Diagnostics/logging only —
    /// NOT used in health decisions. Staleness is handled structurally (the
    /// store is reset when the TCP connection drops), not by age-out, so there
    /// is no timestamp-expiry check on this field.
    public let observedAt: Date

    public init(active: Bool, devices: [String], reason: String?, observedAt: Date) {
        self.active = active
        self.devices = devices
        self.reason = reason
        self.observedAt = observedAt
    }
}

/// Process-wide store for the latest authoritative `InputGrab` status.
///
/// The TCP event listener records into this store and resets it whenever the
/// kanata connection drops, so a non-nil `latest` always means "received on the
/// current live TCP session." The health checker reads it as the **primary**
/// input-capture signal; when it is nil (old kanata that never emits
/// `InputGrab`, or no grab-state transition since connect — kanata does not
/// replay on connect) the checker falls back to the stderr log-pattern detector
/// (#632). Belt-and-suspenders: an authoritative signal that never lies, backed
/// by inference when the signal is simply absent.
public final class KanataGrabStatusStore: @unchecked Sendable {
    public static let shared = KanataGrabStatusStore()

    private let lock = NSLock()
    private var _latest: KanataInputGrabStatus?

    private init() {}

    /// The most recent status received on the current live connection, or nil
    /// if none has been received (or the connection has since dropped).
    public var latest: KanataInputGrabStatus? {
        lock.withLock { _latest }
    }

    /// Record an authoritative status received from kanata.
    public func record(_ status: KanataInputGrabStatus) {
        lock.withLock { _latest = status }
    }

    /// Clear the stored status. Called when the kanata connection drops so a
    /// stale value can never outlive the session it belonged to.
    public func reset() {
        lock.withLock { _latest = nil }
    }
}
