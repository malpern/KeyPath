import Foundation

/// Credits each key event from the session tap to one physical keyboard
/// (ADR-048, opt-in per-keyboard rules).
///
/// The session tap merges every keyboard into one stream. IOHIDManager names
/// the keyboard but arrives separately, about 1 ms earlier, sometimes later.
/// The caller records every HID key value with `record(_:)` and asks
/// `attribute(_:nowNs:)` about each tap event, in tap order. Both callbacks
/// run on one run loop, so this type needs no locking.
///
/// It stores key usages and times only, never text, and keeps a bounded number
/// of unconsumed HID values.
///
/// Rules (all from ADR-048, section 2):
/// - A press is credited to a keyboard when every unconsumed HID press of the
///   same key within the window comes from that keyboard. Candidates from more
///   than one keyboard fall back. Either way the candidate closest in time is
///   consumed, leaving the others for later tap events.
/// - A press is decided with the candidates present when it is asked about. A
///   second keyboard's HID value that arrives after that cannot make it
///   ambiguous; the caller does not hold presses that already have a match.
/// - A release clears that key's other unconsumed HID values up to the release
///   time. They belong to presses macOS merged or that arrived after their tap
///   event gave up, and must not be credited to the next press.
/// - With no candidate yet, the answer is `.wait` until the window's look-ahead
///   has passed, then `.fallback(.noMatch)`.
/// - A release is credited to whatever its press was credited to, so the engine
///   never sees a press on one keyboard and a release on another.
/// - A repeat is credited to the press's keyboard only while no other keyboard
///   holds the same key.
struct KeyboardAttributionMatcher {
    struct Configuration: Equatable {
        /// How far a HID value may precede its tap event. The overlap run
        /// measured up to 27 ms.
        var lookBehindNs: UInt64 = 30_000_000
        /// How far a HID value may follow its tap event. The overlap run
        /// measured up to 3.9 ms. This is also how long a press waits.
        var lookAheadNs: UInt64 = 5_000_000
        /// Unconsumed HID values kept at most; the oldest are dropped first.
        var capacity = 256
    }

    struct HIDValue: Equatable {
        /// IORegistry entry ID of the keyboard.
        let device: UInt64
        /// HID keyboard-page usage.
        let usage: UInt32
        let isDown: Bool
        let timeNs: UInt64
    }

    struct TapEvent: Equatable {
        /// HID keyboard-page usage of the tap event's key.
        let usage: UInt32
        let isDown: Bool
        let isRepeat: Bool
        let timeNs: UInt64
    }

    enum Fallback: Equatable {
        /// No HID value of this key and direction arrived within the window.
        case noMatch
        /// HID values from more than one keyboard were candidates.
        case ambiguous
        /// A repeat while the key is down on more than one keyboard.
        case heldOnSeveralKeyboards
        /// A release or repeat whose press was not credited to one keyboard.
        case pressNotCredited
    }

    enum Decision: Equatable {
        /// Credit the event to this keyboard.
        case keyboard(UInt64)
        /// Treat the event as coming from no particular keyboard.
        case fallback(Fallback)
        /// Not decidable yet: ask again after the next `record(_:)`, or once
        /// `nowNs` has passed the event's look-ahead.
        case wait
    }

    let configuration: Configuration
    /// Unconsumed HID values, oldest first.
    private(set) var unconsumed: [HIDValue] = []
    /// Keyboards whose HID state says each key is down.
    private var heldBy: [UInt32: Set<UInt64>] = [:]
    /// What the tap's current press of each key was credited to; a nil value
    /// means the press fell back.
    private var pressCredit: [UInt32: UInt64?] = [:]

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    mutating func record(_ value: HIDValue) {
        if value.isDown {
            heldBy[value.usage, default: []].insert(value.device)
        } else {
            heldBy[value.usage]?.remove(value.device)
            if heldBy[value.usage]?.isEmpty == true { heldBy[value.usage] = nil }
        }
        unconsumed.append(value)
        if unconsumed.count > configuration.capacity {
            unconsumed.removeFirst(unconsumed.count - configuration.capacity)
        }
    }

    /// Forgets a keyboard that was removed, including keys it still held.
    mutating func removeDevice(_ device: UInt64) {
        unconsumed.removeAll { $0.device == device }
        for usage in Array(heldBy.keys) {
            heldBy[usage]?.remove(device)
            if heldBy[usage]?.isEmpty == true { heldBy[usage] = nil }
        }
    }

    mutating func attribute(_ event: TapEvent, nowNs: UInt64) -> Decision {
        let earliest = event.timeNs > configuration.lookBehindNs ? event.timeNs - configuration.lookBehindNs : 0
        let (sum, overflow) = event.timeNs.addingReportingOverflow(configuration.lookAheadNs)
        let latest = overflow ? UInt64.max : sum
        // Tap events arrive in time order, so nothing older can match again.
        unconsumed.removeAll { $0.timeNs < earliest }

        if event.isDown, event.isRepeat {
            return repeatDecision(for: event.usage)
        }

        let candidates = unconsumed.indices.filter { index in
            let value = unconsumed[index]
            return value.usage == event.usage && value.isDown == event.isDown
                && value.timeNs >= earliest && value.timeNs <= latest
        }

        if !event.isDown {
            // A release follows its press, whatever HID value it pairs with.
            consumeClosest(of: candidates, to: event.timeNs)
            unconsumed.removeAll { $0.usage == event.usage && $0.timeNs <= event.timeNs }
            guard let credit = pressCredit.removeValue(forKey: event.usage) else {
                return .fallback(.noMatch)
            }
            return credit.map(Decision.keyboard) ?? .fallback(.pressNotCredited)
        }

        guard !candidates.isEmpty else {
            if nowNs < latest { return .wait }
            pressCredit[event.usage] = .some(nil)
            return .fallback(.noMatch)
        }

        let devices = Set(candidates.map { unconsumed[$0].device })
        consumeClosest(of: candidates, to: event.timeNs)
        guard devices.count == 1, let device = devices.first else {
            pressCredit[event.usage] = .some(nil)
            return .fallback(.ambiguous)
        }
        pressCredit[event.usage] = device
        return .keyboard(device)
    }

    private func repeatDecision(for usage: UInt32) -> Decision {
        guard let credit = pressCredit[usage] else { return .fallback(.noMatch) }
        guard let device = credit else { return .fallback(.pressNotCredited) }
        let others = (heldBy[usage] ?? []).subtracting([device])
        return others.isEmpty ? .keyboard(device) : .fallback(.heldOnSeveralKeyboards)
    }

    private mutating func consumeClosest(of candidates: [Int], to timeNs: UInt64) {
        func distance(_ index: Int) -> UInt64 {
            let time = unconsumed[index].timeNs
            return time > timeNs ? time - timeNs : timeNs - time
        }
        guard let closest = candidates.min(by: { distance($0) < distance($1) }) else { return }
        unconsumed.remove(at: closest)
    }
}
