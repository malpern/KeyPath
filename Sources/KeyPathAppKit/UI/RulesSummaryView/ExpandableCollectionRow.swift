import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

// MARK: - Expandable Collection Row

struct ExpandableCollectionRow: View {
    let name: String
    let icon: String
    let count: Int
    let isEnabled: Bool
    let mappings: [(input: String, output: String, shiftedOutput: String?, ctrlOutput: String?, description: String?, sectionBreak: Bool, enabled: Bool, id: UUID, behavior: MappingBehavior?)]
    let onToggle: (Bool) -> Void
    let onEditMapping: ((UUID) -> Void)?
    let onDeleteMapping: ((UUID) -> Void)?
    var showZeroState: Bool = false
    var onCreateFirstRule: (() -> Void)?
    var description: String?
    var layerActivator: MomentaryActivator?
    /// Current leader key display name for layer-based collections
    var leaderKeyDisplay: String = "␣ Space"
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
        VStack(alignment: .leading, spacing: 0) {
            // Scroll anchor for auto-scroll when expanded
            if let id = scrollID {
                Color.clear
                    .frame(height: 0)
                    .id(id)
            }

            // Header Row (clickable for expand/collapse)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                    // Auto-scroll to show expanded content
                    if isExpanded, let id = scrollID, let proxy = scrollProxy {
                        // Delay slightly to allow expansion animation to begin
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(100))
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
                                .foregroundStyle(.primary)
                            if count > 0, showZeroState || onEditMapping != nil {
                                // Show count for custom rules section only
                                Text("(\(count))")
                                    .font(.headline)
                                    .fontWeight(.regular)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let desc = description {
                            Text(desc)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if layerActivator != nil {
                            Label("Hold \(leaderKeyDisplay)", systemImage: "hand.point.up.left")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    Spacer()

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
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color(NSColor.windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(isHovered ? 0.15 : 0), lineWidth: 1)
            )
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            // Expanded Mappings or Zero State
            if isExpanded {
                if showZeroState, mappings.isEmpty, let onCreate = onCreateFirstRule {
                    // Zero State - only show if BOTH showZeroState is true AND mappings is actually empty
                    VStack(spacing: 12) {
                        Text("No rules yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

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
                    let config = coll.homeRowModsConfig ?? HomeRowModsConfig()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tap keys for letters, hold for modifiers")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        // Summary of current configuration
                        if !config.enabledKeys.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 16) {
                                    // Left hand
                                    if config.enabledKeys.contains(where: { HomeRowModsConfig.leftHandKeys.contains($0) }) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Left hand")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            HStack(spacing: 6) {
                                                ForEach(HomeRowModsConfig.leftHandKeys, id: \.self) { key in
                                                    if config.enabledKeys.contains(key) {
                                                        let modSymbol = config.modifierAssignments[key].map { formatModifierForDisplay($0) } ?? ""
                                                        Button(action: {
                                                            onOpenHomeRowModsModalWithKey?(key)
                                                        }) {
                                                            HomeRowKeyChipSmall(letter: key.uppercased(), symbol: modSymbol)
                                                        }
                                                        .buttonStyle(.plain)
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
                                                .foregroundStyle(.secondary)
                                            HStack(spacing: 6) {
                                                ForEach(HomeRowModsConfig.rightHandKeys, id: \.self) { key in
                                                    if config.enabledKeys.contains(key) {
                                                        let modSymbol = config.modifierAssignments[key].map { formatModifierForDisplay($0) } ?? ""
                                                        Button(action: {
                                                            onOpenHomeRowModsModalWithKey?(key)
                                                        }) {
                                                            HomeRowKeyChipSmall(letter: key.uppercased(), symbol: modSymbol)
                                                        }
                                                        .buttonStyle(.plain)
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
                                    .foregroundStyle(.secondary)
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
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 16)
                } else if displayStyle == .table {
                    // Table view for complex collections like Vim
                    MappingTableContent(mappings: mappings)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .padding(.horizontal, 12)
                } else {
                    // List view for standard collections and custom rules
                    VStack(spacing: 6) {
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
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
            }
        }
        .onAppear {
            if !hasInitialized {
                isExpanded = defaultExpanded
                hasInitialized = true
            }
        }
        .onChange(of: defaultExpanded) { _, newValue in
            // Auto-expand when rules are added (going from empty to non-empty)
            if newValue, !isExpanded {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
            }
        }
        .onChange(of: isEnabled) { _, _ in
            // Parent state updated, clear local override to stay in sync
            localEnabled = nil
        }
    }

    @ViewBuilder
    func iconView(for icon: String) -> some View {
        if icon.hasPrefix("text:") {
            let text = String(icon.dropFirst(5))
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        } else if icon.hasPrefix("resource:") {
            let resourceName = String(icon.dropFirst(9))
            if let resourceURL = Bundle.main.url(forResource: resourceName, withExtension: "svg"),
               let image = NSImage(contentsOf: resourceURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            } else {
                // Fallback to system image
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }
        } else {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
        }
    }

    func prettyKeyName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
            .capitalized
    }
}
