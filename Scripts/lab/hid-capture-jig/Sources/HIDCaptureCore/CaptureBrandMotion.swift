import Foundation

/// A tiny, deterministic motion model shared by the Jig's branded drawing.
/// Keeping animation math out of AppKit makes it testable and ensures visual
/// feedback never changes capture state or timing.
public struct CaptureBrandMotion: Equatable, Sendable {
    public let completion: Double
    public let breath: Double
    public let eventPulse: Double
    public let glintPosition: Double

    public static func resolve(
        snapshot: CaptureSnapshot,
        nowNs: UInt64,
        reduceMotion: Bool
    ) -> CaptureBrandMotion {
        let expectedCount = snapshot.expected.count
        let completion = expectedCount == 0
            ? 0
            : min(1, Double(snapshot.received.count) / Double(expectedCount))

        if reduceMotion {
            return CaptureBrandMotion(
                completion: completion,
                breath: 0.5,
                eventPulse: 0,
                glintPosition: completion
            )
        }

        let cycleNs: UInt64 = snapshot.state == .capturing ? 1_900_000_000 : 3_800_000_000
        let phase = Double(nowNs % cycleNs) / Double(cycleNs)
        let breath = (sin(phase * .pi * 2 - .pi / 2) + 1) / 2

        let eventPulse: Double
        if let lastEventAtNs = snapshot.lastEventAtNs, nowNs >= lastEventAtNs {
            let elapsed = Double(nowNs - lastEventAtNs) / 420_000_000
            let remaining = max(0, 1 - min(1, elapsed))
            eventPulse = remaining * remaining * (3 - 2 * remaining)
        } else {
            eventPulse = 0
        }

        return CaptureBrandMotion(
            completion: completion,
            breath: breath,
            eventPulse: eventPulse,
            glintPosition: phase
        )
    }
}
