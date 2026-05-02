import Foundation
import KeyPathCore

/// A row item in the categorized rules list: either a section header or a collection row
enum CategorizedItem: Identifiable {
    case header(RuleCollectionCategory)
    case collection(RuleCollection)

    var id: String {
        switch self {
        case let .header(category): "header-\(category.rawValue)"
        case let .collection(collection): "collection-\(collection.id.uuidString)"
        }
    }
}

/// State for home row mods editing modal
struct HomeRowModsEditState: Identifiable {
    let id = UUID()
    let collection: RuleCollection
    let selectedKey: String?
}

/// State for home row layer toggles editing modal
struct HomeRowLayerTogglesEditState: Identifiable {
    let id = UUID()
    let collection: RuleCollection
    let selectedKey: String?
}

/// State for chord groups editing modal
struct ChordGroupsEditState: Identifiable {
    let id = UUID()
    let collection: RuleCollection
}

/// State for sequences editing modal
struct SequencesEditState: Identifiable {
    let id = UUID()
    let collection: RuleCollection
}
