import Foundation
import KeyPathCore
import KeyPathPermissions

// MARK: - Rule Conflict Detection

/// Information about a conflict between rule sources
@MainActor
struct RuleConflictInfo {
    enum Source {
        case collection(RuleCollection)
        case customRule(CustomRule)

        var name: String {
            switch self {
            case let .collection(collection): collection.name
            case let .customRule(rule): rule.displayTitle
            }
        }
    }

    let source: Source
    let keys: [String]

    var displayName: String {
        source.name
    }
}

// MARK: - RuleCollectionsManager

/// Manages rule collections and custom rules with conflict detection.
///
/// Extracted from RuntimeCoordinator to reduce its size and improve
/// separation of concerns. This manager handles:
/// - Loading/saving rule collections and custom rules
/// - Conflict detection between rules
/// - Layer state management
/// - Configuration regeneration on changes
@MainActor
final class RuleCollectionsManager {
    // MARK: - State

    var ruleCollections: [RuleCollection] = []
    var customRules: [CustomRule] = []
    var currentLayerName: String = RuleCollectionLayer.base.displayName

    /// Active keymap layout ID (e.g., "colemak-dh", "dvorak")
    /// When set to non-QWERTY, generates remapping rules in the config
    var activeKeymapId: String = LogicalKeymap.defaultId

    /// Whether to include punctuation in keymap remapping
    var keymapIncludesPunctuation: Bool = false

    // MARK: - Dependencies

    let ruleCollectionStore: RuleCollectionStore
    let customRulesStore: CustomRulesStore
    let configurationService: ConfigurationService
    let eventListener: KanataEventListener

    /// Callback invoked when rules change (for config regeneration)
    var onRulesChanged: (() async -> Void)?

    /// Callback invoked when layer changes (for UI updates)
    var onLayerChanged: ((String) -> Void)?

    /// Callback invoked when a keypath:// action URI is received via push-msg
    var onActionURI: ((KeyPathActionURI) -> Void)?

    /// Callback invoked when an unknown (non-keypath://) message is received
    var onUnknownMessage: ((String) -> Void)?

    /// Callback for reporting errors
    var onError: ((String) -> Void)?

    /// Callback for reporting warnings (non-blocking)
    var onWarning: ((String) -> Void)?

    /// Callback for interactive conflict resolution
    /// Returns the user's choice, or nil if cancelled
    var onConflictResolution: ((RuleConflictContext) async -> RuleConflictChoice?)?

    /// Callback to suppress file watcher before internal saves (prevents double-reload beep)
    var onBeforeSave: (() -> Void)?

    // MARK: - Initialization

    init(
        ruleCollectionStore: RuleCollectionStore = .shared,
        customRulesStore: CustomRulesStore = .shared,
        configurationService: ConfigurationService,
        eventListener: KanataEventListener = KanataEventListener()
    ) {
        self.ruleCollectionStore = ruleCollectionStore
        self.customRulesStore = customRulesStore
        self.configurationService = configurationService
        self.eventListener = eventListener
    }

    deinit {
        let listener = eventListener
        Task.detached(priority: .background) {
            await listener.stop()
        }
    }
}
