import Foundation

public struct KeycapBurstItem: Equatable, Sendable {
    public let sequence: Int
    public let keyCode: UInt16
    public let label: String
    public let pressDepth: Double
    public let opacity: Double
    public let xOffset: Double
    public let yOffset: Double
    public let scale: Double
    public let isPressed: Bool
    public let isRepeat: Bool
}

public struct KeycapBurstOutput: Equatable, Sendable {
    public let items: [KeycapBurstItem]
    public let totalPresses: Int
    public let presentedPresses: Int
    public let recentPresses: Int
    public let intensity: Double
    public let isAnimating: Bool
}

public enum KeycapBurstModel {
    private static let visibleLifetimeNs: UInt64 = 900_000_000
    private static let pressReleaseNs: UInt64 = 160_000_000
    private static let burstWindowNs: UInt64 = 250_000_000
    private static let presentationCadenceNs: UInt64 = 36_000_000

    public static func resolve(
        events: [CapturedKeyEvent],
        pressedKeyCodes: [UInt16],
        nowNs: UInt64,
        reduceMotion: Bool,
        limit: Int = 10
    ) -> KeycapBurstOutput {
        let downEvents = events.filter { $0.phase == .down }
        var lastPresentationNs: UInt64 = 0
        let presented = downEvents.map { event -> (event: CapturedKeyEvent, timestampNs: UInt64) in
            let earliest = lastPresentationNs == 0
                ? event.timestampNs
                : lastPresentationNs &+ (reduceMotion ? 0 : presentationCadenceNs)
            let timestamp = max(event.timestampNs, earliest)
            lastPresentationNs = timestamp
            return (event, timestamp)
        }
        let activeEvents = presented.filter {
            nowNs >= $0.timestampNs && nowNs - $0.timestampNs <= visibleLifetimeNs
        }
        let visible = Array(activeEvents.suffix(max(0, limit)))
        let pressed = Set(pressedKeyCodes)
        let recentRealPresses = downEvents.reduce(into: 0) { count, event in
            if nowNs >= event.timestampNs, nowNs - event.timestampNs <= burstWindowNs {
                count += 1
            }
        }
        let recentPresentedPresses = presented.reduce(into: 0) { count, item in
            if nowNs >= item.timestampNs, nowNs - item.timestampNs <= burstWindowNs {
                count += 1
            }
        }
        let recentPresses = max(recentRealPresses, recentPresentedPresses)
        let intensity = min(1, Double(recentPresses) / 8)
        let presentedPresses = presented.reduce(into: 0) { count, item in
            if nowNs >= item.timestampNs {
                count += 1
            }
        }
        let isAnimating = lastPresentationNs > 0 &&
            (nowNs < lastPresentationNs || nowNs - lastPresentationNs <= visibleLifetimeNs)

        let items = visible.enumerated().map { index, presentedEvent in
            let event = presentedEvent.event
            let ageNs = nowNs - presentedEvent.timestampNs
            let age = min(1, Double(ageNs) / Double(visibleLifetimeNs))
            let pressDepth: Double
            let opacity: Double
            let xOffset: Double
            let yOffset: Double
            let scale: Double

            if reduceMotion {
                pressDepth = 0
                opacity = 1 - 0.42 * age
                xOffset = Double(index - visible.count / 2) * 2
                yOffset = Double(index) * 2.5
                scale = 0.96 + Double(index) * 0.004
            } else {
                let release = min(1, Double(ageNs) / Double(pressReleaseNs))
                pressDepth = pow(1 - release, 2)
                let fadeStart = 0.42
                let fade = age <= fadeStart ? 0 : (age - fadeStart) / (1 - fadeStart)
                opacity = 1 - 0.82 * fade * fade
                let arrival = 1 - pow(1 - release, 3)
                let fan = [-9.0, 6.0, -4.0, 10.0, -7.0, 3.0][event.sequence % 6]
                xOffset = fan * arrival * (0.45 + intensity * 0.55)
                yOffset = Double(index) * (3.3 + intensity * 1.8) * arrival
                scale = (0.94 + Double(index) * 0.005) * (1 - pressDepth * 0.035)
            }

            return KeycapBurstItem(
                sequence: event.sequence,
                keyCode: event.keyCode,
                label: label(for: event),
                pressDepth: pressDepth,
                opacity: max(0, min(1, opacity)),
                xOffset: xOffset,
                yOffset: yOffset,
                scale: scale,
                isPressed: pressed.contains(event.keyCode),
                isRepeat: event.isRepeat
            )
        }

        return KeycapBurstOutput(
            items: items,
            totalPresses: downEvents.count,
            presentedPresses: presentedPresses,
            recentPresses: recentPresses,
            intensity: intensity,
            isAnimating: isAnimating
        )
    }

    public static func label(for event: CapturedKeyEvent) -> String {
        switch event.characters {
        case " ": return "SPACE"
        case "\r", "\n": return "RETURN"
        case "\t": return "TAB"
        case "\u{7f}", "\u{8}": return "DELETE"
        case "\u{1b}": return "ESC"
        case "\u{f700}": return "UP"
        case "\u{f701}": return "DOWN"
        case "\u{f702}": return "LEFT"
        case "\u{f703}": return "RIGHT"
        case "":
            switch event.keyCode {
            case 36, 76: return "RETURN"
            case 48: return "TAB"
            case 49: return "SPACE"
            case 51, 117: return "DELETE"
            case 53: return "ESC"
            case 123: return "LEFT"
            case 124: return "RIGHT"
            case 125: return "DOWN"
            case 126: return "UP"
            default: return "K\(event.keyCode)"
            }
        default:
            let value = event.characters.uppercased()
            return value.count <= 6 ? value : String(value.prefix(5)) + "…"
        }
    }
}
