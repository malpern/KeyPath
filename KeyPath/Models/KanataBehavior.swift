import Foundation

enum KanataBehavior: Codable {
    case simpleRemap(from: String, toKey: String)
    case tapHold(key: String, tap: String, hold: String)
    case tapDance(key: String, actions: [TapDanceAction])
    case sequence(trigger: String, sequence: [String])
    case combo(keys: [String], result: String)
    case layer(key: String, layerName: String, mappings: [String: String])
}

struct TapDanceAction: Codable {
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
}
