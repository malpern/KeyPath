import KeyPathCore
import KeyPathInstallationWizard
import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct RulesTabView: View {
    @Environment(KanataViewModel.self) var kanataManager
    @Environment(\.services) var services
    @State private var searchQuery = ""
    @State var recommendationFocusCollectionId: UUID?
    @State private var showingResetConfirmation = false
    @State private var showingNewRuleSheet = false
    @State var settingsToastManager = WizardToastManager()
    @State private var createButtonHovered = false
    @State var stableSortOrder: [UUID] = []
    @State var pendingSelections: [UUID: String] = [:]
    @State var pendingToggles: [UUID: Bool] = [:]
    @State var showingHomeRowModsHelp = false
    @State var homeRowModsEditState: HomeRowModsEditState?
    @State var homeRowLayerTogglesEditState: HomeRowLayerTogglesEditState?
    @State var chordGroupsEditState: ChordGroupsEditState?
    @State var sequencesEditState: SequencesEditState?
    @State var appKeymaps: [AppKeymap] = []
    @State var isKindaVimInstalled = false
    @State var isKeystrokeHistoryInstalled = false
    @State var pendingEnablePack: Pack?
    @State var pendingEnableUnmetDeps: [UnmetDependency] = []
    @State var pendingDisablePack: Pack?
    @State var pendingDisableDependents: [Pack] = []
    @State var unmetDependencyMap: [String: [UnmetDependency]] = [:]
    @State var collectionOwnershipMap: [UUID: (packID: String, packName: String)] = [:]
    @State var managedToggleCollection: RuleCollection?
    private let catalog = RuleCollectionCatalog()

    /// Total count of custom rules (everywhere + app-specific)
    var isWindowSnappingOnLauncher: Bool {
        guard let ws = kanataManager.ruleCollections.first(where: { $0.id == RuleCollectionIdentifier.windowSnapping }),
              ws.isEnabled
        else { return false }
        return ws.windowSnappingActivationMode == .quickLauncher
    }

    private var totalCustomRulesCount: Int {
        kanataManager.customRules.count + appKeymaps.flatMap(\.overrides).count
    }

    /// Whether there are any custom rules (everywhere or app-specific)
    private var hasAnyCustomRules: Bool {
        !kanataManager.customRules.isEmpty || !appKeymaps.isEmpty
    }

    /// View ID for custom rules section to force re-render on changes
    private var customRulesViewId: String {
        let rulesHash = kanataManager.customRules
            .map { "\($0.id)-\($0.input.hashValue)-\($0.action.outputString.hashValue)-\($0.title.hashValue)" }
            .joined()
        let appsHash = appKeymaps.map(\.id.uuidString).joined()
        return "custom-rules-\(rulesHash)-\(appsHash)"
    }

    /// Show all catalog collections, merging with existing state.
    /// Excludes pack-internal collections (managed entirely by their owning pack).
    var allCollections: [RuleCollection] {
        let catalog = RuleCollectionCatalog()
        return catalog.defaultCollections().compactMap { catalogCollection in
            // Hide pack-internal collections from the Rules tab
            if catalogCollection.owningPackID != nil { return nil }
            // Find matching collection from kanataManager to preserve enabled state
            if var existing = kanataManager.ruleCollections.first(where: { $0.id == catalogCollection.id }) {
                // Also hide if the persisted copy gained an owningPackID
                if existing.owningPackID != nil { return nil }
                // Always use catalog category (user data may have stale values)
                existing.category = catalogCollection.category
                return existing
            }
            // Return catalog item with its default enabled state
            return catalogCollection
        }
    }

    /// Collections sorted by stable order (enabled first, captured on view appear)
    private var sortedCollections: [RuleCollection] {
        guard !stableSortOrder.isEmpty else { return allCollections }
        return allCollections.sorted { a, b in
            guard let indexA = stableSortOrder.firstIndex(of: a.id),
                  let indexB = stableSortOrder.firstIndex(of: b.id)
            else {
                return false
            }
            return indexA < indexB
        }
    }

    var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSearching: Bool {
        !trimmedSearchQuery.isEmpty
    }

    private var filteredCollections: [RuleCollection] {
        guard isSearching else { return sortedCollections }
        return sortedCollections.filter(collectionMatchesSearch)
    }

    private var filteredCustomRules: [CustomRule] {
        guard isSearching else { return kanataManager.customRules }
        let query = trimmedSearchQuery.lowercased()
        return kanataManager.customRules.filter { rule in
            [rule.title, rule.notes ?? "", rule.input, rule.action.outputString]
                .joined(separator: " ")
                .lowercased()
                .contains(query)
        }
    }

    private var filteredAppKeymaps: [AppKeymap] {
        guard isSearching else { return appKeymaps }
        let query = trimmedSearchQuery.lowercased()
        return appKeymaps
            .map { keymap in
                var filtered = keymap
                filtered.overrides = keymap.overrides.filter { override in
                    [keymap.mapping.displayName, keymap.mapping.bundleIdentifier, override.inputKey, override.action.outputString]
                        .joined(separator: " ")
                        .lowercased()
                        .contains(query)
                }
                return filtered
            }
            .filter { !$0.overrides.isEmpty }
    }

    private var hasSearchResults: Bool {
        !filteredCollections.isEmpty || !filteredCustomRules.isEmpty || !filteredAppKeymaps.isEmpty
    }

    /// Flat list of items: category headers interleaved with collections
    private var categorizedItems: [CategorizedItem] {
        let grouped = Dictionary(grouping: filteredCollections, by: \.category)
        var items: [CategorizedItem] = []
        for category in grouped.keys.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            guard let collections = grouped[category] else { continue }
            items.append(.header(category))
            for collection in collections {
                items.append(.collection(collection))
            }
        }
        return items
    }

    private var recommendationCollections: [(collection: RuleCollection, reason: String)] {
        guard !isSearching else { return [] }

        let effectiveCollections = allCollections.map { collection in
            var updated = collection
            if let pendingToggle = pendingToggles[collection.id] {
                updated.isEnabled = pendingToggle
            }
            return updated
        }

        return RulesRecommendationEngine.recommendations(from: effectiveCollections)
            .compactMap { recommendation in
                guard let collection = effectiveCollections.first(where: { $0.id == recommendation.collectionId }) else {
                    return nil
                }
                return (collection: collection, reason: recommendation.reason)
            }
            .prefix(3)
            .map { $0 }
    }

    func computeSortOrder() -> [UUID] {
        // Group by category, sort categories by sortOrder
        let grouped = Dictionary(grouping: allCollections, by: \.category)
        var order: [UUID] = []

        for category in grouped.keys.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            guard let collections = grouped[category] else { continue }
            let enabled = collections.filter(\.isEnabled).map(\.id)
            let disabled = collections.filter { !$0.isEnabled }.map(\.id)
            var categoryOrder = enabled + disabled

            // Keep Backup Caps Lock directly after Caps Lock Remap
            let capsLockRemapId = RuleCollectionIdentifier.capsLockRemap
            let backupCapsLockId = RuleCollectionIdentifier.backupCapsLock
            if let capsIndex = categoryOrder.firstIndex(of: capsLockRemapId),
               let backupIndex = categoryOrder.firstIndex(of: backupCapsLockId),
               backupIndex != capsIndex + 1
            {
                categoryOrder.remove(at: backupIndex)
                let insertIndex = min(capsIndex + 1, categoryOrder.count)
                categoryOrder.insert(backupCapsLockId, at: insertIndex)
            }

            order.append(contentsOf: categoryOrder)
        }

        return order
    }

    private var customRulesTitle: String {
        "Custom Rules"
    }

    // collectionRow, packForCollection → RulesSummaryView+CollectionRow.swift (via extension on RulesTabView)
    // handleCollectionToggle, toggleViaPack, refresh helpers → RulesSummaryView+ToggleHandling.swift

    var body: some View {
        @Bindable var kanataManager = kanataManager
        VStack(spacing: 0) {
            // Top Action Bar
            HStack(spacing: 12) {
                MacSearchField(text: $searchQuery)
                    .accessibilityIdentifier("rules-search-field")
                    .accessibilityLabel("Search rules")
                    .frame(width: 128)

                Spacer()

                Button {
                    showingResetConfirmation = true
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
                .accessibilityIdentifier("rules-reset-button")
                .accessibilityLabel("Reset Rules")

                Button {
                    openConfigInEditor()
                } label: {
                    Label("Edit config", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("rules-edit-config-button")
                .accessibilityLabel("Edit Config")

                Button {
                    NotificationCenter.default.post(name: .openOverlayWithMapper, object: nil)
                } label: {
                    Label("Create Rule", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("rules-create-button")
                .accessibilityLabel("Create Rule")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))

            Divider()

            // Rules List
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if !recommendationCollections.isEmpty {
                            RecommendedRulesSection(
                                recommendations: recommendationCollections,
                                onReview: { collection in
                                    if let pack = packForCollection(collection) {
                                        PackDetailWindowController.shared.showWindow(pack: pack, kanataManager: kanataManager)
                                    } else {
                                        recommendationFocusCollectionId = collection.id
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            scrollProxy.scrollTo("collection-\(collection.id.uuidString)", anchor: .top)
                                        }
                                    }
                                }
                            )
                            .padding(.vertical, 4)
                        }

                        if true {
                            // Custom Rules Section — always visible, shows CTA when empty
                            ExpandableCollectionRow(
                                collectionId: "custom-rules",
                                name: customRulesTitle,
                                icon: "square.and.pencil",
                                count: isSearching ? (filteredCustomRules.count + filteredAppKeymaps.flatMap(\.overrides).count) : totalCustomRulesCount,
                                isEnabled: filteredCustomRules.isEmpty
                                    || filteredCustomRules.allSatisfy(\.isEnabled),
                                mappings: filteredCustomRules.map { (
                                    $0.input,
                                    $0.action.outputString,
                                    $0.shiftedOutput,
                                    nil,
                                    $0.title.isEmpty ? nil : $0.title,
                                    false,
                                    nil as String?,
                                    $0.isEnabled,
                                    $0.id,
                                    $0.behavior
                                ) },
                                appKeymaps: filteredAppKeymaps,
                                onToggle: { isOn in
                                    Task {
                                        for rule in kanataManager.customRules {
                                            await kanataManager.toggleCustomRule(rule.id, enabled: isOn)
                                        }
                                    }
                                },
                                onEditMapping: { id in
                                    // Open overlay with mapper tab and preset values for editing
                                    if let rule = kanataManager.customRules.first(where: { $0.id == id }) {
                                        var userInfo: [String: Any] = [
                                            "inputKey": rule.input,
                                            "outputKey": rule.action.outputString
                                        ]
                                        if let shiftedOutput = rule.shiftedOutput {
                                            userInfo["shiftedOutputKey"] = shiftedOutput
                                        }
                                        NotificationCenter.default.post(
                                            name: .openOverlayWithMapperPreset,
                                            object: nil,
                                            userInfo: userInfo
                                        )
                                    }
                                },
                                onDeleteMapping: { id in
                                    Task { await kanataManager.removeCustomRule(id) }
                                },
                                onDeleteAppRule: { keymap, override in
                                    deleteAppRule(keymap: keymap, override: override)
                                },
                                onEditAppRule: { keymap, override in
                                    // Open overlay with mapper tab and preset values for editing app-specific rule
                                    NotificationCenter.default.post(
                                        name: .openOverlayWithMapperPreset,
                                        object: nil,
                                        userInfo: [
                                            "inputKey": override.inputKey,
                                            "outputKey": override.action.kanataOutput,
                                            "appBundleId": keymap.mapping.bundleIdentifier,
                                            "appDisplayName": keymap.mapping.displayName
                                        ]
                                    )
                                },
                                showZeroState: !hasAnyCustomRules,
                                onCreateFirstRule: {
                                    // Close settings and open overlay with mapper tab
                                    NotificationCenter.default.post(name: .openOverlayWithMapper, object: nil)
                                },
                                description: isSearching ? "Filtered custom rules" : "Remap any key combination or sequence",
                                defaultExpanded: !hasAnyCustomRules,
                                scrollID: "custom-rules",
                                scrollProxy: scrollProxy
                            )
                            // Force SwiftUI to re-render when customRules or appKeymaps change
                            .id(customRulesViewId)
                            .padding(.vertical, 4)
                        }

                        // Collection Rows grouped by category (flat list with interleaved headers)
                        ForEach(categorizedItems) { item in
                            switch item {
                            case let .header(category):
                                HStack(spacing: 6) {
                                    Text(category.displayName.uppercased())
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .tracking(0.8)

                                    VStack { Divider() }
                                }
                                .padding(.horizontal, 8)
                                .padding(.top, 16)
                                .padding(.bottom, 2)

                            case let .collection(collection):
                                collectionRow(for: collection, scrollProxy: scrollProxy)
                                    .id("collection-\(collection.id.uuidString)")
                                    .onAppear {
                                        if recommendationFocusCollectionId == collection.id {
                                            recommendationFocusCollectionId = nil
                                        }
                                    }
                                    .padding(.vertical, 4)

                                // Insert KindaVim after Vim Navigation in the Navigation category
                                if collection.id == RuleCollectionIdentifier.vimNavigation {
                                    kindaVimRow
                                        .padding(.vertical, 4)
                                }
                            }
                        }

                        keystrokeHistoryRow
                            .padding(.vertical, 4)

                        if isSearching, !hasSearchResults {
                            VStack(spacing: 10) {
                                Text("No matching rules")
                                    .font(.headline)
                                Text("Try a different search term or clear the filter.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Button("Clear Search") {
                                    searchQuery = ""
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .accessibilityIdentifier("rules-search-empty-clear-button")
                                .accessibilityLabel("Clear rules search from empty state")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                            .padding(.bottom, 12)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: 500)
        .settingsBackground()
        .withToasts(settingsToastManager)
        .overlay(alignment: .top) {
            if let toastMessage = kanataManager.toastMessage {
                ToastView(message: toastMessage, type: kanataManager.toastType)
                    .padding(.top, 16)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1000)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: kanataManager.toastMessage)
        .onAppear {
            // Capture sort order once when view appears (enabled first, then disabled)
            // This ensures stable layout - toggling a rule won't move it until window reopens
            if stableSortOrder.isEmpty {
                stableSortOrder = computeSortOrder()
            }
            // Load app-specific keymaps
            loadAppKeymaps()
            Task {
                isKindaVimInstalled = await InstalledPackTracker.shared.isInstalled(
                    packID: PackRegistry.kindaVim.id
                )
                isKeystrokeHistoryInstalled = await InstalledPackTracker.shared.isInstalled(
                    packID: PackRegistry.keystrokeHistory.id
                )
                await refreshCollectionOwnership()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appKeymapsDidChange)) { _ in
            loadAppKeymaps()
        }
        .onReceive(NotificationCenter.default.publisher(for: .installedPacksChanged)) { _ in
            Task { await refreshCollectionOwnership() }
        }
        .sheet(item: $homeRowModsEditState) { editState in
            HomeRowModsModalView(
                config: Binding(
                    get: { editState.collection.configuration.homeRowModsConfig ?? HomeRowModsConfig() },
                    set: { _ in }
                ),
                onSave: { newConfig in
                    Task {
                        await kanataManager.updateHomeRowModsConfig(collectionId: editState.collection.id, config: newConfig)
                    }
                    homeRowModsEditState = nil
                },
                onCancel: {
                    homeRowModsEditState = nil
                },
                initialSelectedKey: editState.selectedKey
            )
        }
        .sheet(item: $homeRowLayerTogglesEditState) { editState in
            HomeRowLayerTogglesModalView(
                config: Binding(
                    get: { editState.collection.configuration.homeRowLayerTogglesConfig ?? HomeRowLayerTogglesConfig() },
                    set: { _ in }
                ),
                onSave: { newConfig in
                    Task {
                        await kanataManager.updateHomeRowLayerTogglesConfig(collectionId: editState.collection.id, config: newConfig)
                    }
                    homeRowLayerTogglesEditState = nil
                },
                onCancel: {
                    homeRowLayerTogglesEditState = nil
                },
                initialSelectedKey: editState.selectedKey
            )
        }
        .sheet(item: $chordGroupsEditState) { editState in
            ChordGroupsModalView(
                config: Binding(
                    get: {
                        // Get the LATEST config from kanataManager, not the stale editState snapshot
                        if let currentCollection = kanataManager.ruleCollections.first(where: { $0.id == editState.collection.id }) {
                            return currentCollection.configuration.chordGroupsConfig ?? ChordGroupsConfig()
                        }
                        return editState.collection.configuration.chordGroupsConfig ?? ChordGroupsConfig()
                    },
                    set: { _ in }
                ),
                onSave: { newConfig in
                    Task {
                        await kanataManager.updateChordGroupsConfig(collectionId: editState.collection.id, config: newConfig)
                    }
                    chordGroupsEditState = nil
                },
                onCancel: {
                    chordGroupsEditState = nil
                }
            )
        }
        .sheet(item: $sequencesEditState) { editState in
            SequencesModalView(
                config: Binding(
                    get: {
                        // Get the LATEST config from kanataManager, not the stale editState snapshot
                        if let currentCollection = kanataManager.ruleCollections.first(where: { $0.id == editState.collection.id }) {
                            return currentCollection.configuration.sequencesConfig ?? SequencesConfig()
                        }
                        return editState.collection.configuration.sequencesConfig ?? SequencesConfig()
                    },
                    set: { _ in }
                ),
                onSave: { newConfig in
                    Task {
                        await kanataManager.updateSequencesConfig(collectionId: editState.collection.id, config: newConfig)
                    }
                    sequencesEditState = nil
                },
                onCancel: {
                    sequencesEditState = nil
                }
            )
        }
        .sheet(isPresented: $showingHomeRowModsHelp) {
            MarkdownHelpSheet(resource: "home-row-mods", title: "Home Row Mods")
        }
        .sheet(isPresented: $kanataManager.showRuleConflictDialog) {
            if let context = kanataManager.pendingRuleConflict {
                RuleConflictResolutionDialog(
                    context: context,
                    onChoice: { choice in
                        kanataManager.resolveRuleConflict(with: choice)
                    },
                    onCancel: {
                        kanataManager.resolveRuleConflict(with: nil)
                    }
                )
                .interactiveDismissDisabled()
            }
        }
        .sheet(isPresented: $kanataManager.showMappingConflictDialog) {
            if let context = kanataManager.pendingMappingConflict {
                MappingConflictResolutionDialog(
                    context: context,
                    onChoice: { collectionID in
                        kanataManager.resolveMappingConflict(disabling: collectionID)
                    },
                    onCancel: {
                        kanataManager.resolveMappingConflict(disabling: nil)
                    }
                )
                .interactiveDismissDisabled()
            }
        }
        .alert("Reset Configuration?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Open Backups Folder") {
                openBackupsFolder()
            }
            Button("Reset", role: .destructive) {
                resetToDefaultConfig()
            }
        } message: {
            Text(
                """
                This will reset your configuration to macOS Function Keys only (all custom rules removed).
                A safety backup will be stored in ~/.config/keypath/.backups.
                """
            )
        }
        // Dependency: config mismatch dialog (can't auto-resolve)
        .alert("Missing Configuration", isPresented: Binding(
            get: { pendingEnablePack != nil },
            set: { if !$0 { pendingEnablePack = nil; pendingEnableUnmetDeps = [] } }
        )) {
            if let depPackID = pendingEnableUnmetDeps.first?.dependency.packID,
               let depPack = PackRegistry.pack(id: depPackID)
            {
                Button("Open \(depPack.name)") {
                    PackDetailWindowController.shared.showWindow(pack: depPack, kanataManager: kanataManager)
                    pendingEnablePack = nil
                    pendingEnableUnmetDeps = []
                }
            }
            Button("Cancel", role: .cancel) {
                pendingEnablePack = nil
                pendingEnableUnmetDeps = []
            }
        } message: {
            if let pack = pendingEnablePack, let dep = pendingEnableUnmetDeps.first {
                Text("\(pack.name) needs \(PackRegistry.pack(id: dep.dependency.packID)?.name ?? dep.dependency.packID): \(dep.dependency.description)")
            }
        }
        // Dependency: disable warning dialog
        .alert("Other Rules Depend on This", isPresented: Binding(
            get: { pendingDisablePack != nil },
            set: { if !$0 { pendingDisablePack = nil; pendingDisableDependents = [] } }
        )) {
            Button("Disable Anyway", role: .destructive) {
                if let pack = pendingDisablePack,
                   let collectionID = pack.associatedCollectionID
                {
                    pendingToggles[collectionID] = false
                    Task {
                        await kanataManager.toggleRuleCollection(collectionID, enabled: false)
                        pendingToggles.removeValue(forKey: collectionID)
                        refreshUnmetDependencies()
                    }
                }
                pendingDisablePack = nil
                pendingDisableDependents = []
            }
            Button("Cancel", role: .cancel) {
                pendingDisablePack = nil
                pendingDisableDependents = []
            }
        } message: {
            let names = pendingDisableDependents.map(\.name).joined(separator: ", ")
            Text("Disabling \(pendingDisablePack?.name ?? "") will affect: \(names)")
        }
        .alert("Part of a Pack", isPresented: Binding(
            get: { managedToggleCollection != nil },
            set: { if !$0 { managedToggleCollection = nil } }
        )) {
            if let collection = managedToggleCollection,
               let owner = collectionOwnershipMap[collection.id]
            {
                Button("Turn Off \(owner.packName)", role: .destructive) {
                    Task {
                        let manager = kanataManager.underlyingManager.ruleCollectionsManager
                        try? await PackInstaller.shared.uninstall(packID: owner.packID, manager: manager)
                        kanataManager.underlyingManager.notifyStateChanged()
                        await refreshCollectionOwnership()
                    }
                    managedToggleCollection = nil
                }
            }
            Button("Cancel", role: .cancel) {
                managedToggleCollection = nil
            }
        } message: {
            if let collection = managedToggleCollection,
               let owner = collectionOwnershipMap[collection.id]
            {
                Text("\(collection.name) is part of the \(owner.packName) pack. To change it independently, turn off the pack first.")
            }
        }
        .onAppear {
            refreshUnmetDependencies()
        }
    }

    // collectionMatchesSearch, openConfigInEditor, openBackupsFolder, resetToDefaultConfig → RulesSummaryView+Packs.swift
    // kindaVimRow, keystrokeHistoryRow, loadAppKeymaps, deleteAppRule → RulesSummaryView+Packs.swift
}
