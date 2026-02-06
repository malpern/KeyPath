import KeyPathCore
import SwiftUI

#if os(macOS)
import AppKit
#endif

// MARK: - Expandable Collection Row

struct ExpandableCollectionRow: View {
    let collectionId: String
    let name: String
    let icon: String
    let count: Int
    let isEnabled: Bool
    let mappings: [(input: String, output: String, shiftedOutput: String?, ctrlOutput: String?, description: String?, sectionBreak: Bool, enabled: Bool, id: UUID, behavior: MappingBehavior?)]
    var appKeymaps: [AppKeymap] = []
    let onToggle: (Bool) -> Void
    let onEditMapping: ((UUID) -> Void)?
    let onDeleteMapping: ((UUID) -> Void)?
    var onDeleteAppRule: ((AppKeymap, AppKeyOverride) -> Void)?
    var onEditAppRule: ((AppKeymap, AppKeyOverride) -> Void)?
    var showZeroState: Bool = false
    var onCreateFirstRule: (() -> Void)?
    var description: String?
    var layerActivator: MomentaryActivator?
    /// Current leader key display name for layer-based collections
    var leaderKeyDisplay: String = "␣ Space"
    /// Optional activation hint from collection (overrides default formatting)
    var activationHint: String?
    var defaultExpanded: Bool = false
    var displayStyle: RuleCollectionDisplayStyle = .list
    /// For singleKeyPicker style: the full collection with presets
    var collection: RuleCollection?
    var onSelectOutput: ((String) -> Void)?
    /// For tapHoldPicker style: callback to select tap output
    var onSelectTapOutput: ((String) -> Void)?
    /// For tapHoldPicker style: callback to select hold output
    var onSelectHoldOutput: ((String) -> Void)?
    /// For homeRowMods style: callback to update config
    var onUpdateHomeRowModsConfig: ((HomeRowModsConfig) -> Void)?
    /// For homeRowMods style: callback to open modal
    var onOpenHomeRowModsModal: (() -> Void)?
    /// For homeRowMods style: callback to open modal with a specific key selected
    var onOpenHomeRowModsModalWithKey: ((String) -> Void)?
    /// For homeRowLayerToggles style: callback to update config
    var onUpdateHomeRowLayerTogglesConfig: ((HomeRowLayerTogglesConfig) -> Void)?
    /// For homeRowLayerToggles style: callback to open modal
    var onOpenHomeRowLayerTogglesModal: (() -> Void)?
    /// For homeRowLayerToggles style: callback to open modal with a specific key selected
    var onOpenHomeRowLayerTogglesModalWithKey: ((String) -> Void)?
    /// For chordGroups style: callback to update config
    var onUpdateChordGroupsConfig: ((ChordGroupsConfig) -> Void)?
    /// For chordGroups style: callback to open modal
    var onOpenChordGroupsModal: (() -> Void)?
    /// For sequences style: callback to update config
    var onUpdateSequencesConfig: ((SequencesConfig) -> Void)?
    /// For sequences style: callback to open modal
    var onOpenSequencesModal: (() -> Void)?
    /// For layerPresetPicker style: callback to select a layer preset
    var onSelectLayerPreset: ((String) -> Void)?
    /// For windowSnapping: callback to change key convention
    var onSelectWindowConvention: ((WindowKeyConvention) -> Void)?
    /// For functionKeys: callback to change mode (media keys vs function keys)
    var onSelectFunctionKeyMode: ((FunctionKeyMode) -> Void)?
    /// For launcherGrid: callback to update launcher config
    var onLauncherConfigChanged: ((LauncherGridConfig) -> Void)?
    /// Unique ID for scroll-to behavior
    var scrollID: String?
    /// Scroll proxy for auto-scrolling when expanded
    var scrollProxy: ScrollViewProxy?
    /// Optional transparent-mode toggle (used by Vim collection)
    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var hasInitialized = false
    @State private var localEnabled: Bool? // Optimistic local state for instant toggle feedback

    /// Effective enabled state: use local optimistic value if set, otherwise parent value
    private var effectiveEnabled: Bool {
        localEnabled ?? isEnabled
    }

    /// Format a modifier key for display
    private func formatModifierForDisplay(_ modifier: String) -> String {
        let displayNames: [String: String] = [
            "lmet": "⌘", "rmet": "⌘",
            "lalt": "⌥", "ralt": "⌥",
            "lctl": "⌃", "rctl": "⌃",
            "lsft": "⇧", "rsft": "⇧"
        ]
        return displayNames[modifier] ?? modifier
    }

    var body: some View {
        mainContent
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            scrollAnchorView
            headerButtonView
            expandedContentView
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color(NSColor.windowBackgroundColor))
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(isHovered ? 0.15 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onAppear {
            if !hasInitialized {
                isExpanded = defaultExpanded
                hasInitialized = true
            }
        }
        .onChange(of: defaultExpanded) { _, newValue in
            if newValue, !isExpanded {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
            }
        }
        .onChange(of: isEnabled) { _, _ in
            localEnabled = nil
        }
    }

    @ViewBuilder
    private var scrollAnchorView: some View {
        if let id = scrollID {
            Color.clear
                .frame(height: 0)
                .id(id)
        }
    }

    @ViewBuilder
    private var headerButtonView: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left side: Clickable area for expansion
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                    // Auto-scroll to show expanded content
                    if isExpanded, let id = scrollID, let proxy = scrollProxy {
                        // Delay slightly to allow expansion animation to begin
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(id, anchor: .top)
                            }
                        }
                    }
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    iconView(for: icon)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            if count > 0, showZeroState || onEditMapping != nil {
                                // Show count for custom rules section only
                                Text("(\(count))")
                                    .font(.headline)
                                    .fontWeight(.regular)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let desc = description {
                            Text(desc)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if let hint = activationHint {
                            // Use collection's custom activation hint (e.g., "Hold Hyper key")
                            Label(hint, systemImage: "hand.point.up.left")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        } else if layerActivator != nil {
                            // Fall back to leader key display for leader-based collections
                            Label("Hold \(leaderKeyDisplay)", systemImage: "hand.point.up.left")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            // Right side: Toggle (NOT inside button, so it receives taps)
            Toggle(
                "",
                isOn: Binding(
                    get: { effectiveEnabled },
                    set: { newValue in
                        // Optimistic update: change UI immediately
                        localEnabled = newValue
                        // Then trigger async operation
                        onToggle(newValue)
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(.blue)
            .accessibilityIdentifier("rules-summary-toggle-\(collectionId)")
            .accessibilityLabel("Toggle \(name)")
        }
        .padding(12)
    }

    @ViewBuilder
    private var expandedContentView: some View {
        if isExpanded {
            // Inset back plane container for expanded content
            InsetBackPlane {
                if showZeroState, mappings.isEmpty, appKeymaps.isEmpty, let onCreate = onCreateFirstRule {
                    // Zero State - only show if BOTH showZeroState is true AND all mappings are actually empty
                    VStack(spacing: 12) {
                        Text("No rules yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Button {
                            onCreate()
                        } label: {
                            Label("Create Your First Rule", systemImage: "plus.circle.fill")
                                .font(.body.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else if displayStyle == .singleKeyPicker, let coll = collection {
                    // Segmented picker for single-key remapping
                    SingleKeyPickerContent(
                        collection: coll,
                        onSelectOutput: { output in
                            onSelectOutput?(output)
                        }
                    )
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 16)
                } else if displayStyle == .tapHoldPicker, let coll = collection {
                    // Tap-hold picker for dual-role keys
                    TapHoldPickerContent(
                        collection: coll,
                        onSelectTapOutput: { tap in
                            onSelectTapOutput?(tap)
                        },
                        onSelectHoldOutput: { hold in
                            onSelectHoldOutput?(hold)
                        }
                    )
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 16)
                } else if displayStyle == .homeRowMods, let coll = collection {
                    // Home Row Mods: show summary with current config, click to customize
                    let config = coll.configuration.homeRowModsConfig ?? HomeRowModsConfig()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tap keys for letters, hold for modifiers")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        // Summary of current configuration
                        if !config.enabledKeys.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 16) {
                                    // Left hand
                                    if config.enabledKeys.contains(where: { HomeRowModsConfig.leftHandKeys.contains($0) }) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Left hand")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            HStack(spacing: 6) {
                                                ForEach(HomeRowModsConfig.leftHandKeys, id: \.self) { key in
                                                    if config.enabledKeys.contains(key) {
                                                        let modSymbol = config.modifierAssignments[key].map { formatModifierForDisplay($0) } ?? ""
                                                        HomeRowKeyButton(
                                                            key: key,
                                                            modSymbol: modSymbol,
                                                            action: { onOpenHomeRowModsModalWithKey?(key) }
                                                        )
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Right hand
                                    if config.enabledKeys.contains(where: { HomeRowModsConfig.rightHandKeys.contains($0) }) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Right hand")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            HStack(spacing: 6) {
                                                ForEach(HomeRowModsConfig.rightHandKeys, id: \.self) { key in
                                                    if config.enabledKeys.contains(key) {
                                                        let modSymbol = config.modifierAssignments[key].map { formatModifierForDisplay($0) } ?? ""
                                                        HomeRowKeyButton(
                                                            key: key,
                                                            modSymbol: modSymbol,
                                                            action: { onOpenHomeRowModsModalWithKey?(key) }
                                                        )
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                let hasOffsets = !config.timing.tapOffsets.isEmpty
                                let quickTapText = config.timing.quickTapEnabled ? "Quick tap on" : "Quick tap off"
                                let quickTapTerm = config.timing.quickTapEnabled && config.timing.quickTapTermMs > 0 ? " + \(config.timing.quickTapTermMs)ms" : ""
                                Text("Timing: \(config.timing.tapWindow)ms tap\(quickTapTerm)\(hasOffsets ? " (+ per-key offsets)" : ""), \(config.timing.holdDelay)ms hold · \(quickTapText)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            )
                        }

                        Button("Customize...") {
                            onOpenHomeRowModsModal?()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("rules-summary-home-row-mods-customize-button")
                        .accessibilityLabel("Customize home row mods")
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 16)
                } else if displayStyle == .layerPresetPicker, let coll = collection {
                    // Layer preset picker for collections with multiple preset configurations
                    LayerPresetPickerContent(
                        collection: coll,
                        onSelectPreset: { presetId in
                            onSelectLayerPreset?(presetId)
                        }
                    )
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 16)
                } else if displayStyle == .launcherGrid, let coll = collection {
                    // Launcher grid for app/website shortcuts
                    if let config = coll.configuration.launcherGridConfig {
                        LauncherCollectionView(
                            config: Binding(
                                get: { config },
                                set: { newConfig in
                                    onLauncherConfigChanged?(newConfig)
                                }
                            ),
                            onConfigChanged: { newConfig in
                                onLauncherConfigChanged?(newConfig)
                            }
                        )
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .padding(.horizontal, 16)
                    }
                } else if displayStyle == .chordGroups, let coll = collection {
                    // Chord Groups: Ben Vallack-style multi-key combinations
                    let config = coll.configuration.chordGroupsConfig ?? ChordGroupsConfig()
                    ChordGroupsCollectionView(
                        config: Binding(
                            get: { config },
                            set: { _ in }
                        ),
                        onConfigChanged: { newConfig in
                            onUpdateChordGroupsConfig?(newConfig)
                        },
                        onOpenModal: {
                            onOpenChordGroupsModal?()
                        }
                    )
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 16)
                } else if displayStyle == .sequences, let coll = collection {
                    // Sequences: Multi-key sequences that trigger layers
                    let config = coll.configuration.sequencesConfig ?? SequencesConfig()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Create multi-key sequences like 'Leader → w' to activate layers")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if config.sequences.isEmpty {
                            Text("No sequences configured yet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(config.sequences.prefix(3)) { sequence in
                                    HStack {
                                        Text(sequence.prettyKeys)
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                        Image(systemName: "arrow.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(sequence.action.displayName)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                if config.sequences.count > 3 {
                                    Text("+ \(config.sequences.count - 3) more")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Button {
                            onOpenSequencesModal?()
                        } label: {
                            Label("Customize...", systemImage: "arrow.right.arrow.left.circle")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("sequences-customize-button")
                        .accessibilityLabel("Customize sequences")
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 16)
                } else if displayStyle == .table {
                    // Check for specialized collection views
                    if collection?.id == RuleCollectionIdentifier.numpadLayer {
                        // Numpad uses specialized grid
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Transform your keyboard into a numpad")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            NumpadTransformGrid(mappings: collection?.mappings ?? [])
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .padding(.horizontal, 16)
                    } else if collection?.id == RuleCollectionIdentifier.vimNavigation {
                        // Vim uses animated category cards
                        VimCommandCardsView(mappings: collection?.mappings ?? [])
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                            .padding(.horizontal, 12)
                    } else if collection?.id == RuleCollectionIdentifier.windowSnapping {
                        // Window snapping uses visual monitor canvas
                        WindowSnappingView(
                            mappings: collection?.mappings ?? [],
                            convention: collection?.windowKeyConvention ?? .standard,
                            onConventionChange: { convention in
                                onSelectWindowConvention?(convention)
                            }
                        )
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .padding(.horizontal, 12)
                    } else if collection?.id == RuleCollectionIdentifier.macFunctionKeys {
                        // Function keys use flip card display
                        FunctionKeysView(
                            mappings: collection?.mappings ?? [],
                            currentMode: collection?.functionKeyMode,
                            onModeChange: { mode in
                                onSelectFunctionKeyMode?(mode)
                            }
                        )
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .padding(.horizontal, 12)
                    } else {
                        // Generic table for other collections
                        MappingTableContent(mappings: mappings)
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                            .padding(.horizontal, 12)
                    }
                } else {
                    // List view for standard collections and custom rules
                    VStack(spacing: 6) {
                        // Section: "Everywhere" rules (if we have app-specific rules too, show header)
                        if !mappings.isEmpty, !appKeymaps.isEmpty {
                            RulesSectionHeaderCompact(
                                title: "Everywhere",
                                systemImage: "globe"
                            )
                        }

                        ForEach(mappings, id: \.id) { mapping in
                            MappingRowView(
                                mapping: mapping,
                                layerActivator: layerActivator,
                                leaderKeyDisplay: leaderKeyDisplay,
                                onEditMapping: onEditMapping,
                                onDeleteMapping: onDeleteMapping,
                                prettyKeyName: prettyKeyName
                            )
                        }

                        // Section: App-specific rules
                        ForEach(appKeymaps) { keymap in
                            AppRulesSectionHeaderCompact(keymap: keymap)
                                .padding(.top, mappings.isEmpty ? 0 : 8)

                            ForEach(keymap.overrides) { override in
                                AppRuleRowCompact(
                                    keymap: keymap,
                                    override: override,
                                    onEdit: {
                                        onEditAppRule?(keymap, override)
                                    },
                                    onDelete: {
                                        onDeleteAppRule?(keymap, override)
                                    },
                                    prettyKeyName: prettyKeyName
                                )
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
            } // InsetBackPlane
        }
    }

    @ViewBuilder
    private func iconView(for icon: String) -> some View {
        let scale: CGFloat = 0.85
        let iconSize: CGFloat = 24 * scale
        if icon.hasPrefix("text:") {
            let text = String(icon.dropFirst(5))
            Text(text)
                .font(.system(size: 14 * scale, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: iconSize, height: iconSize)
        } else if icon.hasPrefix("resource:") {
            let resourceName = String(icon.dropFirst(9))
            // Try Bundle.module first (Swift Package resources), then Bundle.main
            let resourceURL = Bundle.module.url(forResource: resourceName, withExtension: "svg")
                ?? Bundle.main.url(forResource: resourceName, withExtension: "svg")
            if let url = resourceURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
            } else {
                // Fallback to system image
                Image(systemName: "questionmark.circle")
                    .font(.system(size: iconSize))
                    .foregroundColor(.secondary)
            }
        } else {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundColor(.secondary)
        }
    }

    func prettyKeyName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
            .capitalized
    }
}
