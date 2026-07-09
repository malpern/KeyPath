import AppKit
import Combine
import KeyPathCore
import SwiftUI

/// Mapper section for the overlay drawer.
/// Shows the main Mapper content scaled down to fit the drawer.
struct OverlayMapperSection: View {
    let isDark: Bool
    let kanataViewModel: KanataViewModel?
    let healthIndicatorState: HealthIndicatorState
    let onHealthTap: () -> Void
    /// Fade amount for monochrome/opacity transition (0 = full color, 1 = faded)
    var fadeAmount: CGFloat = 0
    /// Callback when a key is selected (to highlight on keyboard)
    var onKeySelected: ((UInt16?) -> Void)?
    /// Layer key map for looking up actual mappings (passed from overlay view)
    var layerKeyMap: [UInt16: LayerKeyInfo] = [:]

    @Environment(\.services) var services
    @State var viewModel = MapperViewModel()
    @State var isSystemActionPickerOpen = false
    @State var isAppConditionPickerOpen = false
    @State var showTapCountPicker = false
    @State var showingAppPickerSheet = false
    @State var showingResetDialog = false
    // Output-type picker navigation (page + selectedLayerOutput) lives on
    // MapperViewModel — the picker is rendered in a hoisted window-anchored
    // layer where view @State does not propagate. See MapperViewModel
    // "Output-Type Picker (Overlay) Navigation State".
    @State var knownApps: [AppLaunchInfo] = []
    @State var showingNewLayerDialog = false
    @State var newLayerName = ""
    @State var isHoldVariantPopoverOpen = false
    @State var showMultiTapSlideOver = false
    /// Selected tap count (1 = single, 2 = double, 3 = triple)
    @State var selectedTapCount: Int = 1
    /// Cached set of installed pack IDs (for green dot on visual-only packs)
    @State var installedPackIDs: Set<String> = []

    /// Current behavior slot being edited (tap is default)
    @State var selectedBehaviorSlot: BehaviorSlot = .tap
    /// Current tap output mode (default or shift variant)
    @State var selectedTapOutputMode: TapOutputMode = .default
    /// Which behavior slots have actions configured for current key
    @State var configuredBehaviorSlots: Set<BehaviorSlot> = []

    /// Animation state for input keycap behavior demonstration
    @State var inputKeycapScale: CGFloat = 1.0
    @State var behaviorAnimationTask: Task<Void, Never>?
    /// Animation state for behavior slot label (shows above input keycap)
    @State var showBehaviorLabel = false
    /// Animation state for input keycap bounce when switching behavior slots
    @State var inputKeycapBounce = false

    var body: some View {
        bodyView
    }

    private let showDebugBorders = false

    /// Whether any behavior slot has been modified for the current key
    private var hasAnyModifiedMapping: Bool {
        // Tap slot modified
        let tapModified = viewModel.inputLabel.lowercased() != viewModel.outputLabel.lowercased() ||
            viewModel.selectedApp != nil ||
            viewModel.selectedSystemAction != nil ||
            viewModel.selectedURL != nil ||
            viewModel.hasShiftedOutputConfigured ||
            viewModel.selectedAppCondition != nil

        // Hold modified
        let holdModified = !viewModel.holdAction.isEmpty

        return tapModified || holdModified
    }

    /// Whether tap has a non-identity mapping (A→B, not A→A)
    /// Used to show "in use" dot only when tap does something different
    private var tapHasNonIdentityMapping: Bool {
        // Check if there's a key remapping (not same key)
        let hasKeyRemapping = viewModel.inputLabel.lowercased() != viewModel.outputLabel.lowercased()

        // Check if there's an action assigned (app, system action, URL)
        let hasAction = viewModel.selectedApp != nil ||
            viewModel.selectedSystemAction != nil ||
            viewModel.selectedURL != nil

        return hasKeyRemapping || hasAction || hasMultiTapConfigured
    }

    var hasMultiTapConfigured: Bool {
        !viewModel.doubleTapAction.isEmpty || viewModel.tapDanceSteps.contains { !$0.action.isEmpty }
    }

    /// Label shown above the input keycap for non-default triggers
    private var inputModifierLabel: String? {
        if selectedTapCount > 1 {
            return "\(selectedTapCount)× Tap"
        }
        switch selectedBehaviorSlot {
        case .tap: return nil
        case .hold: return "Hold"
        case .shift: return "⇧ Shift"
        case .combo: return "Combo"
        }
    }

    var mapperContent: some View {
        SlideOverContainer(
            isPresented: $showMultiTapSlideOver,
            panelTitle: "Multi-tap Actions",
            mainContent: { mapperMainContent },
            panelContent: { multiTapPanelContent }
        )
    }

    private var mapperMainContent: some View {
        GeometryReader { scrollProxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 20)

                    // Custom keycap layout with labels on top
                    GeometryReader { proxy in
                        let availableWidth = max(1, proxy.size.width - 8)
                        let keycapWidth: CGFloat = 100
                        let arrowWidth: CGFloat = 20
                        let spacing: CGFloat = 16
                        let baseWidth = keycapWidth * 2 + spacing * 2 + arrowWidth
                        let scale = min(1, availableWidth / baseWidth)

                        VStack(spacing: 8) {
                            // Keycap row — vertically centered, fixed height
                            HStack(alignment: .center, spacing: spacing) {
                                // Input keycap
                                ZStack(alignment: .top) {
                                    MapperInputKeycap(
                                        label: viewModel.inputLabel,
                                        keyCode: viewModel.inputKeyCode,
                                        isRecording: viewModel.isRecordingInput,
                                        fadeAmount: fadeAmount,
                                        customShiftSymbol: viewModel.isShiftedOutputDefault ? nil : viewModel.shiftedOutputLabel,
                                        onTap: { viewModel.toggleInputRecording() }
                                    )
                                    .scaleEffect(inputKeycapBounce ? 1.05 : 1.0)
                                    .scaleEffect(inputKeycapScale)

                                    if let inputModifierLabel {
                                        Text(inputModifierLabel)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(Color.accentColor)
                                            .offset(y: -18)
                                            .opacity(showBehaviorLabel ? 1 : 0)
                                            .scaleEffect(showBehaviorLabel ? 1 : 0.8)
                                    }
                                }
                                .frame(width: keycapWidth)

                                // Arrow
                                Image(systemName: "arrow.right")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                    .modifier(TextGlowModifier(fadeAmount: fadeAmount))
                                    .frame(width: arrowWidth)

                                // Output keycap
                                ZStack(alignment: .top) {
                                    if selectedBehaviorSlot == .tap, selectedTapCount == 1 {
                                        MapperKeycapView(
                                            label: activeTapOutputLabel,
                                            isRecording: activeTapIsRecording,
                                            maxWidth: keycapWidth,
                                            appInfo: selectedTapOutputMode == .default ? viewModel.selectedApp : nil,
                                            systemActionInfo: selectedTapOutputMode == .default ? viewModel.selectedSystemAction : nil,
                                            urlFavicon: selectedTapOutputMode == .default ? viewModel.selectedURLFavicon : nil,
                                            folderInfo: selectedTapOutputMode == .default ? viewModel.selectedFolder : nil,
                                            scriptInfo: selectedTapOutputMode == .default ? viewModel.selectedScript : nil,
                                            fadeAmount: fadeAmount,
                                            onTap: { toggleRecordingForCurrentSlot() }
                                        )
                                    } else {
                                        let slotName = selectedTapCount > 1
                                            ? "\(selectedTapCount)× Tap"
                                            : selectedBehaviorSlot.label
                                        BehaviorSlotKeycap(
                                            label: currentSlotOutputLabel,
                                            isConfigured: currentSlotIsConfigured,
                                            isRecording: isRecordingForCurrentSlot,
                                            slotName: slotName,
                                            fadeAmount: fadeAmount,
                                            onTap: { toggleRecordingForCurrentSlot() },
                                            onClear: { clearCurrentSlot() }
                                        )
                                    }
                                }
                                .frame(width: keycapWidth)
                            }

                            // Controls row — centered under keycaps
                            HStack(spacing: spacing) {
                                appConditionDropdown
                                    .frame(width: keycapWidth, alignment: .center)

                                if tapHasNonIdentityMapping || currentSlotIsConfigured {
                                    Button {
                                        showingResetDialog = true
                                    } label: {
                                        Image(systemName: "arrow.counterclockwise")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Clear mapping")
                                    .accessibilityIdentifier("overlay-mapper-reset-trigger")
                                    .accessibilityLabel("Clear mapping")
                                    .frame(width: arrowWidth)
                                } else {
                                    Color.clear
                                        .frame(width: arrowWidth, height: 1)
                                }

                                outputTypeDropdown
                                    .frame(width: keycapWidth, alignment: .center)
                            }
                            .saturation(Double(1 - fadeAmount))
                            .opacity(Double(1 - fadeAmount * 0.5))
                        }
                        .border(showDebugBorders ? Color.blue : Color.clear, width: 1)
                        .frame(width: baseWidth, height: proxy.size.height, alignment: .center)
                        .scaleEffect(scale, anchor: .center)
                        .frame(width: availableWidth, height: proxy.size.height, alignment: .center)
                    }
                    .frame(height: 132)

                    appMappingIndicators
                        .saturation(Double(1 - fadeAmount))
                        .opacity(Double(1 - fadeAmount * 0.5))

                    packSuggestionsForSelectedKey
                        .saturation(Double(1 - fadeAmount))
                        .opacity(Double(1 - fadeAmount * 0.5))

                    if selectedBehaviorSlot == .hold, !viewModel.holdAction.isEmpty {
                        holdVariantButton
                            .saturation(Double(1 - fadeAmount))
                            .opacity(Double(1 - fadeAmount * 0.5))
                    }

                    if viewModel.showAdvanced {
                        AdvancedBehaviorContent(viewModel: viewModel)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .saturation(Double(1 - fadeAmount))
                            .opacity(Double(1 - fadeAmount * 0.5))
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: scrollProxy.size.height, alignment: .leading)
            }
        }
    }

    private var multiTapPanelContent: some View {
        MultiTapSlideOverView(viewModel: viewModel, sourceKey: viewModel.inputLabel)
    }

    /// App condition dropdown - plain text with hover chevron
    private var appConditionDropdown: some View {
        let displayText = inputConditionDisplayText

        return HoverDropdownButton(
            text: displayText,
            icon: appConditionIcon,
            accessibilityIdentifier: "overlay-mapper-app-condition",
            action: { isAppConditionPickerOpen = true }
        )
        .windowAnchoredPopover(isPresented: $isAppConditionPickerOpen) {
            appConditionPopover
        }
        .confirmationDialog("How many taps?", isPresented: $showTapCountPicker) {
            Button("Single Tap") { selectedTapCount = 1 }
                .accessibilityIdentifier("overlay-mapper-single-tap")
            Button("Double Tap") { selectedTapCount = 2 }
                .accessibilityIdentifier("overlay-mapper-double-tap")
            Button("Triple Tap") { selectedTapCount = 3 }
                .accessibilityIdentifier("overlay-mapper-triple-tap")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("overlay-mapper-tap-count-cancel")
        }
    }

    private var appConditionIcon: (name: String, image: NSImage?)? {
        if let app = viewModel.selectedAppCondition {
            return (name: "", image: app.icon)
        }
        if let device = viewModel.selectedDeviceCondition {
            return (name: device.sfSymbolName, image: nil)
        }
        return nil
    }

    /// Display text for the input condition dropdown
    private var inputConditionDisplayText: String {
        let behaviorLabel: String = switch selectedBehaviorSlot {
        case .tap: selectedTapCount > 1 ? "\(selectedTapCount)× Tap" : "Tap"
        case .hold: "Hold"
        case .shift: "Shift"
        case .combo: "Combo"
        }
        let tapLabel: String? = nil as String?
        let appLabel = viewModel.selectedAppCondition?.displayName
        let deviceLabel = viewModel.selectedDeviceCondition?.displayName

        let parts = [behaviorLabel, tapLabel, appLabel, deviceLabel].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    /// Physical keyboard devices currently connected (excludes VirtualHID, trackpads, mice)
    private var physicalDevices: [ConnectedDevice] {
        DeviceSelectionCache.shared.getConnectedDevices().filter { device in
            !device.isNonKeyboard
        }
    }

    /// Popover content for app condition picker
    private var appConditionPopover: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Behavior section
                behaviorSectionHeader
                ForEach(BehaviorSlot.allCases) { slot in
                    behaviorSlotOption(for: slot)
                }
                PopoverListDivider()

                // App section — two options only; running apps loaded lazily in picker sheet
                appSectionHeader
                everywhereOption
                onlyInOption

                // Keyboard section — only shown when multiple physical devices are connected
                if physicalDevices.count > 1 {
                    PopoverListDivider()
                    keyboardHeader
                    allKeyboardsOption
                    ForEach(physicalDevices) { device in
                        deviceOption(for: device)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(minWidth: 240, maxHeight: 400)
        .pickerPopoverChrome()
    }

    // MARK: - Pack Suggestions for Selected Key

    private var packsForSelectedKey: [Pack] {
        guard let keyCode = viewModel.inputKeyCode else { return [] }
        let kanataKey = OverlayKeyboardView.keyCodeToKanataName(keyCode)
        guard !kanataKey.isEmpty else { return [] }
        var packs = PackRegistry.packsTargeting(kanataKey: kanataKey)
        if !packs.contains(where: { $0.id == PackRegistry.launcher.id }),
           let launcherConfig = kanataViewModel?.ruleCollections
           .first(where: { $0.id == RuleCollectionIdentifier.launcher })?
           .configuration.launcherGridConfig,
           launcherConfig.mappings.contains(where: {
               LauncherGridConfig.normalizeKey($0.key) == LauncherGridConfig.normalizeKey(kanataKey)
           })
        {
            packs.append(PackRegistry.launcher)
        }
        return packs
    }

    private func isPackEnabled(_ pack: Pack) -> Bool {
        if let collectionID = pack.associatedCollectionID {
            if kanataViewModel?.ruleCollections.first(where: { $0.id == collectionID })?.isEnabled == true {
                return true
            }
        }
        return installedPackIDs.contains(pack.id)
    }

    @ViewBuilder
    var packSuggestionsForSelectedKey: some View {
        let packs = packsForSelectedKey
        if !packs.isEmpty {
            VStack(spacing: 4) {
                ForEach(packs) { pack in
                    let enabled = isPackEnabled(pack)
                    Button {
                        if let vm = kanataViewModel {
                            PackDetailWindowController.shared.showWindow(pack: pack, kanataManager: vm, fromOverlay: true)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if enabled {
                                PackActiveLED()
                            }
                            Image(systemName: pack.iconSymbol)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(pack.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(enabled ? "\(pack.name) is active — \(pack.tagline)" : pack.tagline)
                    .accessibilityIdentifier("overlay-pack-suggestion-\(pack.id)")
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 3)
            .padding(.bottom, 4)
        }
    }
}

/// Green LED indicator matching the caps lock key LED style.
struct PackActiveLED: View {
    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 5, height: 5)
            .shadow(color: Color.green.opacity(1.0), radius: 2)
            .shadow(color: Color.green.opacity(0.8), radius: 4)
            .shadow(color: Color.green.opacity(0.5), radius: 8)
    }
}
