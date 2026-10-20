import Foundation
import KeyPathCore
import KeyPathRulesCore

/// Infers what a collection needs from its environment, from the mappings it
/// will actually generate (configuration-driven families included), and checks
/// those needs against the active backend.
///
/// The counterpart of `RuleCollectionDependencyExtractor`, which covers needs
/// one rule satisfies for another (layers, Hyper).
enum RuleCollectionNeedsExtractor {
    static func needs(for collection: RuleCollection) -> Set<RuleEnvironmentNeed> {
        needs(for: KanataConfiguration.effectiveMappings(for: collection))
    }

    static func needs(for mappings: [KeyMapping]) -> Set<RuleEnvironmentNeed> {
        var needs: Set<RuleEnvironmentNeed> = []
        for mapping in mappings {
            if mapping.input.lowercased() == "caps" { needs.insert(.capsLockInput) }
            if mapping.deviceOverrides?.isEmpty == false { needs.insert(.deviceTargeting) }
            for key in emittedKeys(mapping) {
                needs.insert(.emits(key: key))
            }
        }
        return needs
    }

    /// The needs the active backend or Mac cannot meet. Caps Lock input is met
    /// on the session backend by the managed intermediate key.
    static func unmet(_ needs: Set<RuleEnvironmentNeed>,
                      profile: BackendCapabilityProfile = .shared,
                      fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) })
        -> [RuleEnvironmentNeed]
    {
        needs.filter { need in
            switch need {
            case let .emits(key): !profile.canEmit(kanataKey: key)
            case .capsLockInput: false
            case .deviceTargeting: !profile.supportsDeviceTargeting
            case let .externalApp(_, path): !fileExists(path)
            }
        }
        .sorted { String(describing: $0) < String(describing: $1) }
    }

    private static func emittedKeys(_ mapping: KeyMapping) -> [String] {
        var actions = [mapping.action]
        if case let .dualRole(behavior) = mapping.behavior {
            actions += [behavior.tapAction, behavior.holdAction]
        }
        return actions.compactMap { action in
            switch action {
            case let .keystroke(key):
                key
            case let .systemAction(id):
                SystemActionInfo.allActions.first { $0.id == id }?.kanataKeycode
            default:
                nil
            }
        }
    }
}
