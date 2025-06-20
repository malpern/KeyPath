import Foundation

enum KanataBehavior: Codable {
    case simpleRemap(from: String, toKey: String)
    case tapHold(key: String, tap: String, hold: String)
    case tapDance(key: String, actions: [TapDanceAction])
    case sequence(trigger: String, sequence: [String])
    case combo(keys: [String], result: String)
    case layer(key: String, layerName: String, mappings: [String: String])
}

struct TapDanceAction: Codable, Equatable {
    let tapCount: Int
    let action: String
    let description: String
}

struct EnhancedRemapVisualization: Codable {
    let behavior: KanataBehavior
    let title: String
    let description: String
}

extension KanataBehavior {
    var primaryKey: String {
        switch self {
        case .simpleRemap(let from, _):
            return from
        case .tapHold(let key, _, _):
            return key
        case .tapDance(let key, _):
            return key
        case .sequence(let trigger, _):
            return trigger
        case .combo(let keys, _):
            return keys.joined(separator: " + ")
        case .layer(let key, _, _):
            return key
        }
    }

    var behaviorType: String {
        switch self {
        case .simpleRemap:
            return "Simple Remap"
        case .tapHold:
            return "Tap-Hold"
        case .tapDance:
            return "Tap Dance"
        case .sequence:
            return "Sequence"
        case .combo:
            return "Combo"
        case .layer:
            return "Layer"
        }
    }

    var description: String {
        switch self {
        case .simpleRemap(let from, let toKey):
            return "Maps '\(from)' key to '\(toKey)'"
        case .tapHold(let key, let tap, let hold):
            return "'\(key)' key: tap for '\(tap)', hold for '\(hold)'"
        case .tapDance(let key, let actions):
            let actionDescriptions = actions.map { "\($0.tapCount)x: \($0.action)" }
            return "'\(key)' key tap dance: \(actionDescriptions.joined(separator: ", "))"
        case .sequence(let trigger, let sequence):
            return "Type '\(trigger)' to output sequence: \(sequence.joined(separator: " → "))"
        case .combo(let keys, let result):
            return "Press \(keys.joined(separator: " + ")) together to output '\(result)'"
        case .layer(let key, let layerName, let mappings):
            let mappingCount = mappings.count
            return "'\(key)' activates '\(layerName)' layer with \(mappingCount) mapping\(mappingCount == 1 ? "" : "s")"
        }
    }
}
