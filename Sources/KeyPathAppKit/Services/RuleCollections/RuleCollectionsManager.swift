import Foundation
import KeyPathCore
import KeyPathPermissions
import KeyPathRulesCore
import Observation

// MARK: - Rule Conflict Detection

/// Information about a conflict between rule sources
@MainActor
struct RuleConflictInfo {
    enum Source {
        case collection(RuleCollection)
        case customRule(CustomRule)
        /// A party the admission engine names but no stored rule owns (the leader
        /// key, a chord group). It can be shown, not disabled from here.
        case named(String)

        var name: String {
            switch self {
            case let .collection(collection): collection.name
            case let .customRule(rule): rule.displayTitle
            case let .named(name): name
            }
        }

        var canBeDisabled: Bool {
            if case .named = self { return false }
            return true
        }
    }

    let source: Source
    let keys: [String]

    var displayName: String {
        source.name
    }
}

/// Collection persistence and runtime application are separate stages until the
/// multi-store transaction migration. A failed stage may have partially written
/// files; this result does not promise rollback.
enum RulePersistenceResult {
    case persisted(reloadResult: ReloadResult?)
    case failed(Error)

    var didPersist: Bool {
        if case .persisted = self { return true }
        return false
    }
}

/// A user-visible catalog update candidate. Catalog changes never apply merely
/// because they were discovered at load time: the user either keeps their local
/// version or explicitly applies this candidate after reviewing its impact.
struct CatalogUpdatePreview: Identifiable, Equatable {
    let existing: RuleCollection
    let proposed: RuleCollection
    let affectedKeys: [String]
    let affectedLayers: [String]
    let conflictDescription: String?
    let isPackManaged: Bool

    var id: UUID {
        existing.id
    }

    var canApply: Bool {
        !isPackManaged && conflictDescription == nil
    }
}

/// The durable outcome of applying one or more approved catalog updates.
struct CatalogUpdateApplicationResult {
    let saveResult: SaveResult
    let backupPath: String?
    let appliedCollectionIDs: Set<UUID>
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
@Observable
final class RuleCollectionsManager {
    // MARK: - State

    /// A single settled revision for views that read collections and custom rules together.
    private var committedRuleState = RuleStateSnapshot(collections: [], customRules: [])
    @ObservationIgnored private var stagedRuleState: RuleStateSnapshot?

    var committedRuleCollections: [RuleCollection] {
        committedRuleState.collections
    }

    var committedCustomRules: [CustomRule] {
        committedRuleState.customRules
    }

    var ruleCollections: [RuleCollection] {
        get { stagedRuleState?.collections ?? committedRuleCollections }
        set {
            if stagedRuleState != nil {
                stagedRuleState?.collections = newValue
            } else {
                committedRuleState.collections = newValue
            }
        }
    }

    var customRules: [CustomRule] {
        get { stagedRuleState?.customRules ?? committedCustomRules }
        set {
            if stagedRuleState != nil {
                stagedRuleState?.customRules = newValue
            } else {
                committedRuleState.customRules = newValue
            }
        }
    }

    /// Remains set when recovered files cannot yet be read completely.
    var needsRecoveredRuleStateRefresh = false
    var observedRuleRecoveryRevision: UInt64 = 0
    /// Source state is refreshed once for each newly admitted root operation.
    /// Trusted nested calls retain their candidate state instead of reloading it.
    var lastRuleStateRefreshOperationID: UUID?
    var currentLayerName: String = RuleCollectionLayer.base.displayName

    /// Active keymap layout ID (e.g., "colemak-dh", "dvorak")
    /// When set to non-QWERTY, generates remapping rules in the config
    var activeKeymapId: String = LogicalKeymap.defaultId

    /// Whether to include punctuation in keymap remapping
    var keymapIncludesPunctuation: Bool = false

    // MARK: - Active Tasks

    @ObservationIgnored var eventMonitoringTask: Task<Void, Never>?

    // MARK: - Dependencies

    let ruleCollectionStore: RuleCollectionStore
    let customRulesStore: CustomRulesStore
    let configurationService: ConfigurationService
    let eventListener: KanataEventListener
    let keymapPreferences: UserDefaults
    let preferencesService: PreferencesService
    var pendingLeaderKeyPreference: LeaderKeyPreference?

    struct LeaderPreferenceSnapshot: Sendable {
        let value: LeaderKeyPreference
        let data: Data?
    }

    func snapshotLeaderPreference() -> LeaderPreferenceSnapshot {
        LeaderPreferenceSnapshot(
            value: preferencesService.leaderKeyPreference,
            data: preferencesService.persistenceDefaults.data(forKey: PreferencesService.leaderKeyPreferenceKey)
        )
    }

    /// Apply already-persisted rules and retain the runtime disposition.
    var onRulesChanged: (() async -> ReloadResult)?

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

    /// Callback for save-time mapping-conflict resolution (#460).
    /// Returns the id of the collection to disable, or nil if cancelled.
    var onMappingConflictResolution: ((MappingConflictContext) async -> UUID?)?

    /// What the session runtime learned about Caps Lock at its last start
    /// (phase 4d). Set by `RuntimeCoordinator` from the lifecycle coordinator;
    /// `.unknown` until the first start. See `AdmissionEngine.Environment`.
    var admissionEnvironment: AdmissionEngine.Environment = .unknown

    /// Callback for resolving newly introduced rule prerequisites.
    /// Returns the user's confirmed apply choice, or nil if cancelled.
    var onPrerequisiteResolution:
        ((RulePrerequisiteResolutionContext) async -> RulePrerequisiteResolutionChoice?)?

    /// Interactive setup owns the sheet until its atomic save has succeeded.
    var onPrerequisiteSetup: ((RulePrerequisiteResolutionContext, @escaping RuleSetupApply) async -> SaveResult)?

    /// Callback for confirming a disable that would orphan enabled dependents.
    /// Returns `.disableAnyway`, or nil to keep the provider enabled.
    var onDependentResolution:
        ((RuleDependentResolutionContext) async -> RuleDependentResolutionChoice?)?

    /// Callback to suppress file watcher before internal saves (prevents double-reload beep)
    var onBeforeSave: (() -> Void)?

    // MARK: - Initialization

    init(
        ruleCollectionStore: RuleCollectionStore = .shared,
        customRulesStore: CustomRulesStore = .shared,
        configurationService: ConfigurationService,
        eventListener: KanataEventListener = KanataEventListener(),
        keymapPreferences: UserDefaults = .standard,
        preferencesService: PreferencesService? = nil
    ) {
        self.ruleCollectionStore = ruleCollectionStore
        self.customRulesStore = customRulesStore
        self.configurationService = configurationService
        self.eventListener = eventListener
        self.keymapPreferences = keymapPreferences
        self.preferencesService = preferencesService ?? PreferencesService.shared
    }

    /// Hold rule changes for the duration of a write, including reload
    /// and recovery. Nested operations using the same permit share the draft.
    func withStagedRuleMutation<Result: Sendable>(
        using permit: ConfigurationOperationGate.Permit? = nil,
        _ operation: @escaping @MainActor @Sendable (ConfigurationOperationGate.Permit) async throws -> Result
    ) async throws -> Result {
        try await configurationService.operationGate.withOperation(using: permit) { @MainActor [self] admitted in
            guard stagedRuleState == nil else { return try await operation(admitted) }
            stagedRuleState = committedRuleState
            defer {
                if let stagedRuleState, committedRuleState != stagedRuleState {
                    committedRuleState = stagedRuleState
                }
                stagedRuleState = nil
            }
            return try await operation(admitted)
        }
    }

    deinit {
        eventMonitoringTask?.cancel()
        let listener = eventListener
        Task.detached(priority: .background) {
            await listener.stop()
        }
    }
}
