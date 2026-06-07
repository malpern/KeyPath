import KeyPathCore
import SwiftUI
#if os(macOS)
    import AppKit
#endif

/// Main view for Home Row Mods collection with progressive disclosure
struct HomeRowModsCollectionView: View {
    @Binding var config: HomeRowModsConfig
    let availableLayers: [String]
    let onConfigChanged: (HomeRowModsConfig) -> Void
    let onEnsureLayersExist: ([String]) async -> Void
    let onEnableLayerCollections: (([UUID]) async -> Void)?
    var holdTimingBinding: Binding<Double>?
    var holdTimingValue: Int = 180
    var holdTimingDefault: Int = 180
    var holdTimingRange: ClosedRange<Double> = 120 ... 300
    var holdTimingStep: Double = 20
    var onResetHoldTiming: (() -> Void)?
    var isCollectionEnabled: Bool = true

    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @State var showingCustomizeWindow = false
    @State var selectedKey: String?
    @State var showingNewLayerSheet = false
    @State var newLayerName = ""
    @State var locallyCreatedLayers: Set<String> = []
    @State var hoveredHoldBehavior: HomeRowHoldMode?
    @State var hoveredLayerToggleMode: LayerToggleMode?
    @State var timingPreviewPhase: TimingPreviewPhase = .idle
    @State var timingPreviewTask: Task<Void, Never>?

    enum TimingPreviewPhase: Equatable {
        case idle
        case pressing
        case modifier
    }

    @State var showingHelp = false

    private var activeKeymap: LogicalKeymap {
        .resolve(id: selectedKeymapId)
    }

    private var homeRowDisplayLabels: [String: String] {
        let allRelevantKeys = Set(HomeRowModsConfig.allKeys + HomeRowModsConfig.vallackTopRowKeys)
        return Dictionary(uniqueKeysWithValues: allRelevantKeys.map { key in
            (key, displayLabel(forCanonicalKey: key))
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Home row mods configuration")
                .frame(width: 0, height: 0)
                .opacity(0.01)
                .accessibilityIdentifier("home-row-mods-config-panel")
                .accessibilityLabel("Home row mods configuration")
                .accessibilityValue(homeRowModsAccessibilityValue)

            // Visual keyboard (always visible when expanded)
            ViewThatFits(in: .horizontal) {
                homeRowKeyboard(size: 72)
                homeRowKeyboard(size: 68)
                homeRowKeyboard(size: 64)
                homeRowKeyboard(size: 60)
                homeRowKeyboard(size: 56)
                homeRowKeyboard(size: 52)
                homeRowKeyboard(size: 48)
            }
            .padding(.bottom, 8)

            if let holdTimingBinding {
                HoldTimingSliderRow(
                    value: holdTimingBinding,
                    range: holdTimingRange,
                    step: holdTimingStep,
                    suffix: " ms",
                    currentValue: holdTimingValue,
                    onSliderReleased: { startTimingPreview() },
                    onValueChanged: { newHoldMs in
                        let lo = holdTimingRange.lowerBound
                        let hi = holdTimingRange.upperBound
                        let fraction = (newHoldMs - lo) / (hi - lo)
                        let idleMs = Int(50 + fraction * 200)
                        config.timing.requirePriorIdleMs = idleMs
                        onConfigChanged(config)
                    }
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }

            HStack {
                Spacer()

                if hasCustomizations {
                    Button {
                        resetToDefaults()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isCollectionEnabled)
                    .accessibilityIdentifier("home-row-mods-reset-defaults")
                    .accessibilityLabel("Reset home row mods to defaults")
                    .accessibilityValue(homeRowModsAccessibilityValue)
                }

                Button("Settings...") {
                    showingCustomizeWindow = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!isCollectionEnabled)
                .accessibilityIdentifier("home-row-mods-customize-button")
                .accessibilityLabel("Home row mods settings")
                .accessibilityValue(homeRowModsAccessibilityValue)
            }
            .padding(.horizontal, 10)
        }
        .animation(.easeInOut(duration: 0.2), value: selectedKey)
        .onAppear {
            normalizeLegacyLayerModeIfNeeded()
        }
        .sheet(isPresented: $showingCustomizeWindow) {
            customizeWindowContent
        }
    }

    var usesTopRowKeys: Bool {
        config.enabledKeys.contains(where: { HomeRowModsConfig.vallackTopRowKeys.contains($0) })
    }

    private func homeRowKeyboard(size: CGFloat) -> some View {
        HomeRowKeyboardView(
            enabledKeys: config.enabledKeys,
            modifierAssignments: activeHoldAssignments,
            holdMode: config.holdMode,
            selectedKey: selectedKey,
            keyDisplayLabels: homeRowDisplayLabels,
            helperText: config.holdMode == .modifiers ? "Tap for letter, hold for modifier" : "Tap for letter, hold for layer",
            keyChipSize: size,
            timingPreviewPhase: timingPreviewPhase,
            leftHandKeys: usesTopRowKeys ? HomeRowModsConfig.vallackLeftHandKeys : HomeRowModsConfig.leftHandKeys,
            rightHandKeys: usesTopRowKeys ? HomeRowModsConfig.vallackRightHandKeys : HomeRowModsConfig.rightHandKeys,
            keyPopoverContent: { key in
                Group {
                    if !config.enabledKeys.contains(key) {
                        enableKeyPopoverContent(for: key)
                    } else if config.holdMode == .layers {
                        layerPopoverContent(for: key)
                    } else {
                        modifierPopoverContent(for: key)
                    }
                }
            },
            onPopoverDismiss: {
                selectedKey = nil
            },
            onKeySelected: { key in
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedKey = selectedKey == key ? nil : key
                }
            }
        )
    }

    var layerOptions: [(key: String, label: String, icon: String)] {
        let options = availableLayerNames.map { layer in
            (key: layer, label: LayerInfo.displayName(for: layer), icon: LayerInfo.iconName(for: layer))
        }
        assert(
            options.allSatisfy { knownAvailableLayerNames.contains($0.key.lowercased()) },
            "Home row layer options must only include existing (or just-created) layers."
        )
        return options
    }

    // MARK: - Helpers

    func updateConfig() {
        AppLogger.shared.log("🧪 [QA] Home Row Mods config changed: \(homeRowModsAccessibilityValue)")
        onConfigChanged(config)
    }

    var activeHoldAssignments: [String: String] {
        config.holdMode == .modifiers ? config.modifierAssignments : config.layerAssignments
    }

    func displayLabel(forCanonicalKey key: String) -> String {
        guard let keyCode = LogicalKeymap.keyCode(forQwertyLabel: key),
              let label = activeKeymap.label(for: keyCode, includeExtraKeys: false)
        else {
            return key.uppercased()
        }
        return label.uppercased()
    }

    private var keyMappingInstructionText: String {
        if config.holdMode == .layers {
            return "Click a key to choose its layer."
        }
        return "Click a key to choose its modifier."
    }

    var knownAvailableLayerNames: Set<String> {
        Set(
            availableLayers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        ).union(
            locallyCreatedLayers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    var availableLayerNames: [String] {
        let names = Array(knownAvailableLayerNames).sorted()
        assert(Set(names.map { $0.lowercased() }) == knownAvailableLayerNames, "Layer names should be normalized.")
        return names
    }

    var recommendedLayerNames: [String] {
        ["fun", "num", "sym", "nav"]
    }

    var recommendedLayerAssignments: [String: String] {
        let left = recommendedLayerNames
        return [
            "a": left[0], "s": left[1], "d": left[2], "f": left[3],
            "j": left[3], "k": left[2], "l": left[1], ";": left[0]
        ]
    }

    private var missingRecommendedLayers: [String] {
        let existing = Set(availableLayerNames.map { $0.lowercased() })
        let needed = Set(recommendedLayerNames.map { $0.lowercased() })
        return needed.filter { !existing.contains($0) }.sorted()
    }

    private enum HomeRowModifierPreset: Hashable {
        case macCAGS
        case winGACS
        case custom
    }

    private enum HomeRowLayerPreset: Hashable {
        case `default`
        case custom
    }

    private func modifierPresetSelection(from assignments: [String: String]) -> HomeRowModifierPreset {
        if assignments == HomeRowModsConfig.cagsMacDefault { return .macCAGS }
        if assignments == HomeRowModsConfig.gacsWindows { return .winGACS }
        return .custom
    }

    private func normalizeLegacyLayerModeIfNeeded() {
        guard config.holdMode == .layers, config.hasUserSelectedHoldMode == false else { return }
        config.holdMode = .modifiers
        selectedKey = nil
        updateConfig()
    }

    /// Whether the current assignments differ from defaults (for either mode)
    private var baselineConfig: HomeRowModsConfig {
        usesTopRowKeys ? .vallackDefault : HomeRowModsConfig()
    }

    private var hasCustomizations: Bool {
        let baseline = baselineConfig
        if config.enabledKeys != baseline.enabledKeys { return true }
        if config.timing != baseline.timing { return true }
        if config.oppositeHandMode != baseline.oppositeHandMode { return true }
        if config.modifierAssignments != baseline.modifierAssignments { return true }
        if holdTimingBinding != nil, holdTimingValue != holdTimingDefault { return true }
        return false
    }

    var homeRowModsAccessibilityValue: String {
        let enabledKeys = config.enabledKeys.sorted().joined(separator: ",")
        return "mode \(config.holdMode.displayName), layer activation \(config.layerToggleMode.displayName), enabled keys \(enabledKeys), tap window \(config.timing.tapWindow) ms, hold delay \(config.timing.holdDelay) ms, opposite hand \(config.oppositeHandMode.displayName)"
    }

    /// Reset assignments to the default for the current hold mode
    private func startTimingPreview() {
        timingPreviewTask?.cancel()
        timingPreviewTask = Task { @MainActor in
            let raw = Double(holdTimingValue)
            let lo = holdTimingRange.lowerBound
            let hi = holdTimingRange.upperBound
            let fraction = (raw - lo) / (hi - lo)

            // Exaggerate: "prefer letters" holds letters for 1.2s,
            // "prefer modifiers" holds letters for only 0.15s
            let letterHoldMs = Int(150 + fraction * 1050)
            // Inverse for modifier flash
            let modifierShowMs = Int(200 + (1.0 - fraction) * 600)

            withAnimation(.easeIn(duration: 0.08)) { timingPreviewPhase = .pressing }

            try? await Task.sleep(nanoseconds: UInt64(letterHoldMs) * 1_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.15, dampingFraction: 0.85)) { timingPreviewPhase = .modifier }

            try? await Task.sleep(nanoseconds: UInt64(modifierShowMs) * 1_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.2)) { timingPreviewPhase = .idle }
        }
    }

    private func resetToDefaults() {
        let baseline = baselineConfig
        config.modifierAssignments = baseline.modifierAssignments
        config.layerAssignments = baseline.layerAssignments
        config.enabledKeys = baseline.enabledKeys
        config.timing = baseline.timing
        config.oppositeHandMode = baseline.oppositeHandMode
        config.holdMode = baseline.holdMode
        onResetHoldTiming?()
        updateConfig()
    }
}
