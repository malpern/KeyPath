import KeyPathCore
import KeyPathInstallationWizard
import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct RulesTabView: View {
    @Environment(KanataViewModel.self) var kanataManager
    @Environment(\.services) private var services
    @State private var searchQuery = ""
    @State private var recommendationFocusCollectionId: UUID?
    @State private var showingResetConfirmation = false
    @State private var showingNewRuleSheet = false
    @State private var settingsToastManager = WizardToastManager()
    @State private var createButtonHovered = false
    /// Stable sort order captured when view appears (enabled collections first)
    @State private var stableSortOrder: [UUID] = []
    /// Track pending selections for immediate UI feedback (before backend confirms)
    @State var pendingSelections: [UUID: String] = [:]
    /// Track pending toggle states for immediate UI feedback
    @State var pendingToggles: [UUID: Bool] = [:]
    @State private var showingHomeRowModsHelp = false
    @State private var homeRowModsEditState: HomeRowModsEditState?
    @State private var homeRowLayerTogglesEditState: HomeRowLayerTogglesEditState?
    @State private var chordGroupsEditState: ChordGroupsEditState?
    @State private var sequencesEditState: SequencesEditState?
    @State private var appKeymaps: [AppKeymap] = []
    @State private var isKindaVimInstalled = false
    @State private var isKeystrokeHistoryInstalled = false
    /// Dependency resolution: pack awaiting enable confirmation
    @State private var pendingEnablePack: Pack?
    @State private var pendingEnableUnmetDeps: [UnmetDependency] = []
    /// Dependency resolution: pack awaiting disable confirmation
    @State private var pendingDisablePack: Pack?
    @State private var pendingDisableDependents: [Pack] = []
    /// Tracks packs with unmet dependencies (for warning badges)
    @State private var unmetDependencyMap: [String: [UnmetDependency]] = [:]
    /// Maps collection IDs to managing pack info (for installed packs only)
    @State private var collectionOwnershipMap: [UUID: (packID: String, packName: String)] = [:]
    /// Alert: collection whose toggle was tapped while managed by a pack
    @State private var managedToggleCollection: RuleCollection?
    private let catalog = RuleCollectionCatalog()

    /// Total count of custom rules (everywhere + app-specific)
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

    private var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
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

    /// Compute sort order: grouped by category, then enabled first within each category
    private func computeSortOrder() -> [UUID] {
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

    /// Helper to build a collection row - extracted to simplify type-checking
    @ViewBuilder
    private func collectionRow(for collection: RuleCollection, scrollProxy: ScrollViewProxy) -> some View {
        let style = collection.displayStyle
        let isSpecializedTable = style == .table && (
            collection.id == RuleCollectionIdentifier.numpadLayer ||
                collection.id == RuleCollectionIdentifier.vimNavigation ||
                collection.id == RuleCollectionIdentifier.windowSnapping ||
                collection.id == RuleCollectionIdentifier.macFunctionKeys
        )
        let needsCollection = style == .singleKeyPicker || style == .homeRowMods || style == .homeRowLayerToggles || style == .tapHoldPicker || style == .layerPresetPicker || style == .launcherGrid ||
            style == .chordGroups ||
            style ==
            .sequences || style == .autoShiftSymbols || isSpecializedTable
        ExpandableCollectionRow(
            collectionId: collection.id.uuidString,
            name: dynamicCollectionName(for: collection),
            icon: collection.icon ?? "circle",
            count: style == .singleKeyPicker || style == .tapHoldPicker ? 1 :
                (style == .layerPresetPicker ? (collection.configuration.layerPresetPickerConfig?.selectedMappings.count ?? 0) : collection.mappings.count),
            isEnabled: pendingToggles[collection.id] ?? collection.isEnabled,
            mappings: collection.mappings.map {
                ($0.input, $0.action.outputString, $0.shiftedOutput, $0.ctrlOutput, $0.description, $0.sectionBreak, $0.sectionLabel, collection.isEnabled, $0.id, nil)
            },
            onToggle: { isOn in
                handleCollectionToggle(collection: collection, isOn: isOn)
            },
            onEditMapping: nil,
            onDeleteMapping: nil,
            onTapRow: packForCollection(collection).map { pack in
                { PackDetailWindowController.shared.showWindow(pack: pack, kanataManager: kanataManager) }
            },
            description: dynamicCollectionDescription(for: collection),
            layerActivator: collection.momentaryActivator,
            leaderKeyDisplay: currentLeaderKeyDisplay,
            activationHint: dynamicActivationHint(for: collection),
            managingPackName: collectionOwnershipMap[collection.id]?.packName,
            onManagedToggleTapped: collectionOwnershipMap[collection.id] != nil ? {
                managedToggleCollection = collection
            } : nil,
            defaultExpanded: recommendationFocusCollectionId == collection.id,
            displayStyle: style,
            collection: needsCollection ? collection : nil,
            onSelectOutput: style == .singleKeyPicker ? { output in
                pendingSelections[collection.id] = output
                Task { await kanataManager.updateCollectionOutput(collection.id, output: output) }
            } : nil,
            onSelectTapOutput: style == .tapHoldPicker ? { tap in
                Task { await kanataManager.updateCollectionTapOutput(collection.id, tapOutput: tap) }
            } : nil,
            onSelectHoldOutput: style == .tapHoldPicker ? { hold in
                Task { await kanataManager.updateCollectionHoldOutput(collection.id, holdOutput: hold) }
            } : nil,
            onUpdateHomeRowModsConfig: style == .homeRowMods ? { config in
                pendingToggles[collection.id] = true
                Task { await kanataManager.updateHomeRowModsConfig(collectionId: collection.id, config: config) }
            } : nil,
            homeRowAvailableLayers: style == .homeRowMods ? availableHomeRowLayers(for: collection) : [],
            onEnsureHomeRowLayersExist: style == .homeRowMods ? { layerNames in
                for layerName in layerNames {
                    await kanataManager.underlyingManager.rulesManager.createLayer(layerName)
                }
            } : nil,
            onEnableLayerCollections: style == .homeRowMods ? { collectionIds in
                await kanataManager.batchEnableCollections(collectionIds)
            } : nil,
            onOpenHomeRowModsModal: style == .homeRowMods ? {
                homeRowModsEditState = HomeRowModsEditState(collection: collection, selectedKey: nil)
            } : nil,
            onOpenHomeRowModsModalWithKey: style == .homeRowMods ? { key in
                homeRowModsEditState = HomeRowModsEditState(collection: collection, selectedKey: key)
            } : nil,
            onUpdateHomeRowLayerTogglesConfig: style == .homeRowLayerToggles ? { config in
                pendingToggles[collection.id] = true
                Task { await kanataManager.updateHomeRowLayerTogglesConfig(collectionId: collection.id, config: config) }
            } : nil,
            onOpenHomeRowLayerTogglesModal: style == .homeRowLayerToggles ? {
                homeRowLayerTogglesEditState = HomeRowLayerTogglesEditState(collection: collection, selectedKey: nil)
            } : nil,
            onOpenHomeRowLayerTogglesModalWithKey: style == .homeRowLayerToggles ? { key in
                homeRowLayerTogglesEditState = HomeRowLayerTogglesEditState(collection: collection, selectedKey: key)
            } : nil,
            onUpdateChordGroupsConfig: style == .chordGroups ? { config in
                pendingToggles[collection.id] = true
                Task { await kanataManager.updateChordGroupsConfig(collectionId: collection.id, config: config) }
            } : nil,
            onOpenChordGroupsModal: style == .chordGroups ? {
                chordGroupsEditState = ChordGroupsEditState(collection: collection)
            } : nil,
            onUpdateSequencesConfig: style == .sequences ? { config in
                pendingToggles[collection.id] = true
                Task { await kanataManager.updateSequencesConfig(collectionId: collection.id, config: config) }
            } : nil,
            onOpenSequencesModal: style == .sequences ? {
                sequencesEditState = SequencesEditState(collection: collection)
            } : nil,
            onSelectLayerPreset: style == .layerPresetPicker ? { presetId in
                Task { await kanataManager.updateCollectionLayerPreset(collection.id, presetId: presetId) }
            } : nil,
            onSelectWindowConvention: collection.id == RuleCollectionIdentifier.windowSnapping ? { convention in
                Task { await kanataManager.updateWindowKeyConvention(collection.id, convention: convention) }
            } : nil,
            onSelectFunctionKeyMode: collection.id == RuleCollectionIdentifier.macFunctionKeys ? { mode in
                Task { await kanataManager.updateFunctionKeyMode(collection.id, mode: mode) }
            } : nil,
            onLauncherConfigChanged: collection.id == RuleCollectionIdentifier.launcher ? { config in
                Task { await kanataManager.updateLauncherConfig(collection.id, config: config) }
            } : nil,
            onAutoShiftConfigChanged: collection.id == RuleCollectionIdentifier.autoShiftSymbols ? { config in
                pendingToggles[collection.id] = true
                Task { await kanataManager.updateAutoShiftSymbolsConfig(collectionId: collection.id, config: config) }
            } : nil,
            onHelpTapped: collection.id == RuleCollectionIdentifier.homeRowMods ? {
                showingHomeRowModsHelp = true
            } : nil,
            scrollID: "collection-\(collection.id.uuidString)",
            scrollProxy: scrollProxy
        )
        .overlay(
            // Orange border for collections that need a Pack Detail view built
            packForCollection(collection) == nil && !collection.isSystemDefault
                ? RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1.5)
                : nil
        )
    }

    private func packForCollection(_ collection: RuleCollection) -> Pack? {
        PackRegistry.starterKit.first { $0.associatedCollectionID == collection.id }
    }

    // MARK: - Dependency-Aware Toggle

    private func handleCollectionToggle(collection: RuleCollection, isOn: Bool) {
        AppLogger.shared.log("🎚️ [Rules] handleCollectionToggle: '\(collection.name)' isOn=\(isOn) pack=\(packForCollection(collection)?.name ?? "nil") collectionID=\(collection.id)")
        if let owner = collectionOwnershipMap[collection.id] {
            settingsToastManager.showError(
                "Part of \(owner.packName) — turn off the pack to change this"
            )
            pendingToggles.removeValue(forKey: collection.id)
            return
        }

        let pack = packForCollection(collection)

        if isOn, let pack {
            // Check for unmet dependencies before enabling
            let unmet = PackDependencyChecker.unmetRequirements(
                for: pack.id,
                enabledCollections: kanataManager.ruleCollections,
                installedPackIDs: []
            )

            if !unmet.isEmpty {
                // Auto-resolvable: all unmet deps just need to be enabled
                let allAutoResolvable = unmet.allSatisfy { $0.reason == .notEnabled }

                if allAutoResolvable {
                    // Auto-enable dependencies and the pack
                    pendingToggles[collection.id] = true
                    Task {
                        for dep in unmet {
                            if let depPack = PackRegistry.pack(id: dep.dependency.packID),
                               let depCollectionID = depPack.associatedCollectionID
                            {
                                await kanataManager.toggleRuleCollection(depCollectionID, enabled: true)
                            }
                        }
                        await kanataManager.toggleRuleCollection(collection.id, enabled: true)
                        pendingToggles.removeValue(forKey: collection.id)
                        refreshUnmetDependencies()
                        let depNames = unmet.map { PackRegistry.pack(id: $0.dependency.packID)?.name ?? $0.dependency.packID }
                        settingsToastManager.showSuccess("Also enabled \(depNames.joined(separator: ", "))")
                    }
                    return
                } else {
                    // Config mismatch — show dialog
                    pendingEnablePack = pack
                    pendingEnableUnmetDeps = unmet
                    return
                }
            }
        }

        if !isOn, let pack {
            // Check if other enabled packs depend on this one
            let dependents = PackDependencyChecker.dependents(
                of: pack.id,
                enabledCollections: kanataManager.ruleCollections,
                installedPackIDs: []
            )

            if !dependents.isEmpty {
                pendingDisablePack = pack
                pendingDisableDependents = dependents
                return
            }
        }

        // No dependency issues — toggle directly
        pendingToggles[collection.id] = isOn
        if !isOn {
            pendingSelections.removeValue(forKey: collection.id)
        }
        Task {
            if let pack {
                AppLogger.shared.log("🎚️ [Rules] toggleViaPack path for '\(pack.name)' (collectionID=\(collection.id), packAssoc=\(pack.associatedCollectionID?.uuidString ?? "nil"))")
                await toggleViaPack(pack, isOn: isOn)
            } else {
                AppLogger.shared.log("🎚️ [Rules] direct toggleRuleCollection for '\(collection.name)' (id=\(collection.id))")
                await kanataManager.toggleRuleCollection(collection.id, enabled: isOn)
            }
            pendingToggles.removeValue(forKey: collection.id)
            refreshUnmetDependencies()
        }
    }

    private func toggleViaPack(_ pack: Pack, isOn: Bool) async {
        let manager = kanataManager.underlyingManager.ruleCollectionsManager
        do {
            if isOn {
                _ = try await PackInstaller.shared.install(pack, manager: manager)
            } else {
                try await PackInstaller.shared.uninstall(packID: pack.id, manager: manager)
            }
            // System packs (e.g. Vallack) directly mutate collection isEnabled
            // state and call regenerateConfigFromCollections(), which doesn't
            // trigger RuntimeCoordinator's state publisher. Push the updated
            // collection state to the ViewModel so toggles and previews reflect
            // the new enabled state.
            kanataManager.underlyingManager.notifyStateChanged()
        } catch {
            AppLogger.shared.log("⚠️ [Rules] Pack toggle failed for '\(pack.name)': \(error.localizedDescription)")
            await kanataManager.toggleRuleCollection(
                pack.associatedCollectionID ?? UUID(),
                enabled: isOn
            )
        }
    }

    private func refreshCollectionOwnership() async {
        var map: [UUID: (packID: String, packName: String)] = [:]
        for collection in allCollections {
            if let owner = await InstalledPackTracker.shared.packManagingCollection(collection.id) {
                let pack = PackRegistry.pack(id: owner.packID)
                let isSelfManaged = pack?.associatedCollectionID == collection.id
                if !isSelfManaged {
                    map[collection.id] = (packID: owner.packID, packName: owner.packName)
                }
            }
        }
        collectionOwnershipMap = map
    }

    private func refreshUnmetDependencies() {
        unmetDependencyMap = PackDependencyChecker.allUnmetRequirements(
            enabledCollections: kanataManager.ruleCollections,
            installedPackIDs: []
        )
    }

    private func availableHomeRowLayers(for _: RuleCollection) -> [String] {
        let existingLayerNames = Set(
            kanataManager.ruleCollections
                .map(\.targetLayer.kanataName)
                .filter { $0.lowercased() != "base" }
        )
        return Array(existingLayerNames).sorted()
    }

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
                                mappings: filteredCustomRules.map { ($0.input, $0.action.outputString, $0.shiftedOutput, nil, $0.title.isEmpty ? nil : $0.title, false, nil as String?, $0.isEnabled, $0.id, $0.behavior) },
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


    private func collectionMatchesSearch(_ collection: RuleCollection) -> Bool {
        let query = trimmedSearchQuery.lowercased()

        let mappingText = collection.mappings
            .flatMap { mapping in
                [mapping.input, mapping.action.outputString, mapping.shiftedOutput ?? "", mapping.ctrlOutput ?? "", mapping.description ?? ""]
            }
            .joined(separator: " ")

        let searchable = [
            collection.name,
            collection.summary,
            collection.activationHint ?? "",
            collection.tags.joined(separator: " "),
            mappingText
        ]
        .joined(separator: " ")
        .lowercased()

        return searchable.contains(query)
    }

    private func openConfigInEditor() {
        let url = URL(fileURLWithPath: kanataManager.configPath)
        openFileInPreferredEditor(url)
    }

    private func openBackupsFolder() {
        let backupsPath = "\(NSHomeDirectory())/.config/keypath/.backups"
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: backupsPath)
    }

    private func resetToDefaultConfig() {
        Task {
            do {
                try await kanataManager.resetToDefaultConfig()
                // Clear all pending UI state so toggles reflect actual reset state
                pendingToggles.removeAll()
                pendingSelections.removeAll()
                // Recompute sort order to reflect new enabled/disabled state
                stableSortOrder = computeSortOrder()
                settingsToastManager.showSuccess("Configuration reset to default")
            } catch {
                settingsToastManager.showError("Reset failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - KindaVim Visual-Only Pack

    @ViewBuilder
    private var kindaVimRow: some View {
        let pack = PackRegistry.kindaVim
        if !isSearching || pack.name.localizedCaseInsensitiveContains(trimmedSearchQuery)
            || "kindavim".contains(trimmedSearchQuery.lowercased())
        {
            ExpandableKindaVimRow(
                isPackEnabled: isKindaVimInstalled,
                onToggle: { newValue in
                    isKindaVimInstalled = newValue
                    Task {
                        do {
                            if newValue {
                                let record = InstalledPackRecord(
                                    packID: pack.id,
                                    version: pack.version,
                                    installedAt: Date(),
                                    quickSettingValues: [:]
                                )
                                try await InstalledPackTracker.shared.upsert(record)
                            } else {
                                try await InstalledPackTracker.shared.remove(packID: pack.id)
                            }
                        } catch {
                            AppLogger.shared.log("⚠️ [Rules] KindaVim toggle failed: \(error.localizedDescription)")
                            isKindaVimInstalled = !newValue
                            settingsToastManager.showError("Failed to \(newValue ? "enable" : "disable") KindaVim")
                        }
                    }
                },
                onTapRow: {
                    PackDetailWindowController.shared.showWindow(pack: pack, kanataManager: kanataManager)
                }
            )
        }
    }

    @ViewBuilder
    private var keystrokeHistoryRow: some View {
        let pack = PackRegistry.keystrokeHistory
        if !isSearching || pack.name.localizedCaseInsensitiveContains(trimmedSearchQuery)
            || "keystroke history".contains(trimmedSearchQuery.lowercased())
            || "debug".contains(trimmedSearchQuery.lowercased())
        {
            ExpandableKeystrokeHistoryRow(
                isPackEnabled: isKeystrokeHistoryInstalled,
                onToggle: { newValue in
                    isKeystrokeHistoryInstalled = newValue
                    Task {
                        do {
                            if newValue {
                                let record = InstalledPackRecord(
                                    packID: pack.id,
                                    version: pack.version,
                                    installedAt: Date(),
                                    quickSettingValues: [:]
                                )
                                try await InstalledPackTracker.shared.upsert(record)
                                KeystrokeHistoryService.shared.isRecording = true
                            } else {
                                try await InstalledPackTracker.shared.remove(packID: pack.id)
                                KeystrokeHistoryService.shared.isRecording = false
                                KeystrokeHistoryService.shared.clearEvents()
                            }
                        } catch {
                            AppLogger.shared.log("⚠️ [Rules] Keystroke History toggle failed: \(error.localizedDescription)")
                            isKeystrokeHistoryInstalled = !newValue
                        }
                    }
                },
                onTapRow: {
                    PackDetailWindowController.shared.showWindow(pack: pack, kanataManager: kanataManager)
                }
            )
        }
    }

    // MARK: - App Keymaps Helpers

    private func loadAppKeymaps() {
        Task {
            let keymaps = await services.appKeymapStore.loadKeymaps()
            await MainActor.run {
                appKeymaps = keymaps.sorted { $0.mapping.displayName < $1.mapping.displayName }
            }
        }
    }

    private func deleteAppRule(keymap: AppKeymap, override: AppKeyOverride) {
        Task {
            var updatedKeymap = keymap
            updatedKeymap.overrides.removeAll { $0.id == override.id }

            do {
                if updatedKeymap.overrides.isEmpty {
                    try await services.appKeymapStore.removeKeymap(bundleIdentifier: keymap.mapping.bundleIdentifier)
                } else {
                    try await services.appKeymapStore.upsertKeymap(updatedKeymap)
                }

                try await AppConfigGenerator.regenerateFromStore()
                await AppContextService.shared.reloadMappings()
                _ = await kanataManager.underlyingManager.restartKanata(reason: "App rule deleted from Settings")
            } catch {
                AppLogger.shared.log("⚠️ [RulesTabView] Failed to delete app rule: \(error)")
                settingsToastManager.showError("Failed to delete rule: \(error.localizedDescription)")
            }
        }
    }
}

