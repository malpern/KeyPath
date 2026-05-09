import Foundation

/// Pure-function safety logic for the VirtualHID daemon invariant:
/// Kanata must never run without a healthy VirtualHID daemon, because kanata
/// grabs keyboard input and VirtualHID is the only path for re-emitting keystrokes.
///
/// Extracted as a value type so the decision logic is unit-testable without
/// instantiating singletons or hitting real system services.
struct VHIDSafetyCheck {
    /// Returns `true` when kanata is running but the VirtualHID daemon is not healthy.
    /// Callers should emergency-stop kanata when this returns `true`.
    static func shouldEmergencyStop(kanataRunning: Bool, vhidDaemonHealthy: Bool) -> Bool {
        kanataRunning && !vhidDaemonHealthy
    }

    /// Returns `true` when VirtualHID is healthy enough to allow kanata to start.
    static func canStartKanata(vhidDaemonHealthy: Bool) -> Bool {
        vhidDaemonHealthy
    }
}
