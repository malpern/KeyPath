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

    @StateObject var viewModel = MapperViewModel()
    @State var isSystemActionPickerOpen = false
    @State var isAppConditionPickerOpen = false
    @State var cachedRunningApps: [NSRunningApplication] = []
    @State var showingResetDialog = false
    @State var isSystemActionsExpanded = false
    @State var isLaunchAppsExpanded = false
    @State var isLayersExpanded = false
    @State var knownApps: [AppLaunchInfo] = []
    @State var showingNewLayerDialog = false
    @State var newLayerName = ""
    @State var isHoldVariantPopoverOpen = false
    @State var showMultiTapSlideOver = false
    /// Currently selected layer for "Go to Layer" output
    @State var selectedLayerOutput: String?

    /// Current behavior slot being edited (tap is default)
    @State var selectedBehaviorSlot: BehaviorSlot = .tap
    /// Which behavior slots have actions configured for current key
    @State var configuredBehaviorSlots: Set<BehaviorSlot> = []

    /// Animation state for output keycap behavior demonstration
    @State var outputKeycapScale: CGFloat = 1.0
    @State var behaviorAnimationTask: Task<Void, Never>?
    /// Animation state for behavior slot label (shows above output keycap)
    @State var showBehaviorLabel = false
    /// Animation state for output keycap bounce when switching behavior slots
    @State var outputKeycapBounce = false

    var body: some View {
        bodyView
    }

    private var bodyView: some View {
        let base = VStack(spacing: 8) {
            if shouldShowHealthGate {
                healthGateContent
            } else {
                mapperContent
                    .saturation(Double(1 - fadeAmount)) // Monochromatic when faded
                    .opacity(Double(1 - fadeAmount * 0.5)) // Fade with keyboard
            }
        }

        let withAppear = base.onAppear {
            guard !shouldShowHealthGate, let kanataViewModel else { return }
            viewModel.configure(kanataManager: kanataViewModel.underlyingManager)
            viewModel.setLayer(kanataViewModel.currentLayerName)
            // Initialize with actual mapping for A key (keyCode 0)
            // Look up from layerKeyMap to get current remapping, if any
            let defaultKeyCode: UInt16 = 0 // 'A' key on macOS
            let layerInfo = layerKeyMap[defaultKeyCode]
            let inputLabel = "a"
            let outputLabel = layerInfo?.displayLabel.lowercased() ?? "a"
            let appId = layerInfo?.appLaunchIdentifier
            let systemId = layerInfo?.systemActionIdentifier
            let urlId = layerInfo?.urlIdentifier
            viewModel.setInputFromKeyClick(
                keyCode: defaultKeyCode,
                inputLabel: inputLabel,
                outputLabel: outputLabel,
                appIdentifier: appId,
                systemActionIdentifier: systemId,
                urlIdentifier: urlId
            )
            // Load any existing behavior (hold action, etc.) from saved rules
            viewModel.loadBehaviorFromExistingRule(kanataManager: kanataViewModel.underlyingManager)
            // Notify parent to highlight the A key
            onKeySelected?(viewModel.inputKeyCode)
            // Pre-load running apps for instant popover display
            preloadRunningApps()
            // Initialize configured behavior slots
            updateConfiguredBehaviorSlots()
        }

        let withDisappear = withAppear.onDisappear {
            viewModel.stopKeyCapture()
        }

        let withExit = withDisappear.onExitCommand {
            if isAnyRecordingActive {
                cancelAllRecording()
            }
        }

        let withInputChange = withExit.onChange(of: viewModel.inputKeyCode) { _, newKeyCode in
            onKeySelected?(newKeyCode)
            // Reset to tap slot when selecting a new key
            selectedBehaviorSlot = .tap
            updateConfiguredBehaviorSlots()
        }

        let withLayerChange = withInputChange.onReceive(
            NotificationCenter.default.publisher(for: .kanataLayerChanged)
        ) { notification in
            if let layerName = notification.userInfo?["layerName"] as? String {
                viewModel.setLayer(layerName)
            }
        }

        let withDrawerSelection = withLayerChange.onReceive(
            NotificationCenter.default.publisher(for: .mapperDrawerKeySelected)
        ) { notification in
            guard !shouldShowHealthGate else { return }
            guard let keyCode = notification.userInfo?["keyCode"] as? UInt16,
                  let inputKey = notification.userInfo?["inputKey"] as? String,
                  let outputKey = notification.userInfo?["outputKey"] as? String
            else { return }

            // Extract optional action identifiers
            let appId = notification.userInfo?["appIdentifier"] as? String
            let systemId = notification.userInfo?["systemActionIdentifier"] as? String
            let urlId = notification.userInfo?["urlIdentifier"] as? String

            // Extract app condition info (for editing app-specific rules)
            let appBundleId = notification.userInfo?["appBundleId"] as? String
            let appDisplayName = notification.userInfo?["appDisplayName"] as? String

            // Update the mapper's input to the clicked key
            viewModel.setInputFromKeyClick(
                keyCode: keyCode,
                inputLabel: inputKey,
                outputLabel: outputKey,
                appIdentifier: appId,
                systemActionIdentifier: systemId,
                urlIdentifier: urlId
            )

            // Load any existing behavior (hold action, etc.) from saved rules
            if let manager = kanataViewModel?.underlyingManager {
                viewModel.loadBehaviorFromExistingRule(kanataManager: manager)
            }

            // If app condition is provided, set it for app-specific rule editing
            if let bundleId = appBundleId, let displayName = appDisplayName {
                // Load the app icon (or use fallback)
                let icon: NSImage
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                    icon = NSWorkspace.shared.icon(forFile: appURL.path)
                    icon.size = NSSize(width: 24, height: 24)
                } else {
                    icon = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
                        ?? NSImage()
                }
                viewModel.selectedAppCondition = AppConditionInfo(
                    bundleIdentifier: bundleId,
                    displayName: displayName,
                    icon: icon
                )
            }
        }

        let withOpenAppConditionPicker = withDrawerSelection.onReceive(
            NotificationCenter.default.publisher(for: .openMapperAppConditionPicker)
        ) { _ in
            // Open the app condition picker when requested (e.g., from "New Rule" button in App Rules tab)
            guard !shouldShowHealthGate else { return }
            refreshRunningApps()
            // Small delay to allow tab switch animation to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isAppConditionPickerOpen = true
            }
        }

        let withSetAppCondition = withOpenAppConditionPicker.onReceive(
            NotificationCenter.default.publisher(for: .mapperSetAppCondition)
        ) { notification in
            // Set app condition directly (from "+" button on app card in App Rules tab)
            guard !shouldShowHealthGate else { return }
            guard let bundleId = notification.userInfo?["bundleId"] as? String,
                  let displayName = notification.userInfo?["displayName"] as? String
            else { return }

            // Load app icon
            let icon: NSImage
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                icon = NSWorkspace.shared.icon(forFile: appURL.path)
                icon.size = NSSize(width: 24, height: 24)
            } else {
                icon = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage()
            }

            viewModel.selectedAppCondition = AppConditionInfo(
                bundleIdentifier: bundleId,
                displayName: displayName,
                icon: icon
            )

            // Reset input/output for new rule
            viewModel.resetForNewMapping()
        }

        let withAutoSave = withSetAppCondition.onChange(of: viewModel.isRecordingOutput) { wasRecording, isRecording in
            // Only trigger when recording just stopped
            guard wasRecording, !isRecording else { return }
            guard !shouldShowHealthGate else { return }

            // Check if we have a valid mapping (input != output or has an action)
            let hasOutputAction = viewModel.selectedApp != nil ||
                viewModel.selectedSystemAction != nil ||
                viewModel.selectedURL != nil
            let hasKeyRemapping = viewModel.inputLabel.lowercased() != viewModel.outputLabel.lowercased()

            guard hasOutputAction || hasKeyRemapping else { return }
            guard let manager = kanataViewModel?.underlyingManager else { return }

            // Auto-save the mapping
            Task {
                await viewModel.save(kanataManager: manager)
                // Update configured slots after save
                updateConfiguredBehaviorSlots()
            }
        }

        let withOutputChange = withAutoSave.onChange(of: viewModel.outputLabel) { _, _ in
            updateConfiguredBehaviorSlots()
        }

        let withHoldChange = withOutputChange.onChange(of: viewModel.holdAction) { _, _ in
            updateConfiguredBehaviorSlots()
        }

        let withDoubleTapChange = withHoldChange.onChange(of: viewModel.doubleTapAction) { _, _ in
            updateConfiguredBehaviorSlots()
        }

        let withTapDanceChange = withDoubleTapChange.onChange(of: viewModel.tapDanceSteps.map(\.action)) { _, _ in
            updateConfiguredBehaviorSlots()
        }

        let withAppChange = withTapDanceChange.onChange(of: viewModel.selectedApp?.name) { _, _ in
            updateConfiguredBehaviorSlots()
        }

        let withSystemChange = withAppChange.onChange(of: viewModel.selectedSystemAction?.id) { _, _ in
            updateConfiguredBehaviorSlots()
        }

        let withSlotChange = withSystemChange.onChange(of: selectedBehaviorSlot) { _, newSlot in
            playBehaviorAnimation(for: newSlot)
        }

        let withResetDialog = withSlotChange.confirmationDialog(
            "Clear Mapping",
            isPresented: $showingResetDialog,
            titleVisibility: .visible
        ) {
            // Option 1: Clear just the current slot (only for non-tap slots that are configured)
            if selectedBehaviorSlot != .tap, currentSlotIsConfigured {
                Button("Clear \(selectedBehaviorSlot.label) Only") {
                    clearCurrentSlot()
                }
                .accessibilityIdentifier("overlay-mapper-reset-slot-button")
            }

            // Option 2: Clear all behaviors for this key
            Button("Clear All for \"\(viewModel.inputLabel.uppercased())\"") {
                clearAllBehaviorsForCurrentKey()
            }
            .accessibilityIdentifier("overlay-mapper-reset-key-button")

            // Option 3: Clear everything
            Button("Clear All Custom Mappings", role: .destructive) {
                performResetAll()
            }
            .accessibilityIdentifier("overlay-mapper-reset-all-button")

            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("overlay-mapper-reset-cancel-button")
        } message: {
            if selectedBehaviorSlot != .tap, currentSlotIsConfigured {
                Text("What would you like to clear?")
            } else {
                Text("Choose what to clear for \"\(viewModel.inputLabel.uppercased())\"")
            }
        }

        return withResetDialog.sheet(isPresented: $viewModel.showingURLDialog) {
            URLInputDialog(
                urlText: $viewModel.urlInputText,
                onSubmit: { viewModel.submitURL() },
                onCancel: { viewModel.showingURLDialog = false }
            )
        }
    }

    private let showDebugBorders = false

    /// Whether any behavior slot has been modified for the current key
    private var hasAnyModifiedMapping: Bool {
        // Tap slot modified
        let tapModified = viewModel.inputLabel.lowercased() != viewModel.outputLabel.lowercased() ||
            viewModel.selectedApp != nil ||
            viewModel.selectedSystemAction != nil ||
            viewModel.selectedURL != nil ||
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

    private var mapperContent: some View {
        SlideOverContainer(
            isPresented: $showMultiTapSlideOver,
            panelTitle: "Multi-tap Actions",
            mainContent: { mapperMainContent },
            panelContent: { multiTapPanelContent }
        )
    }

    private var mapperMainContent: some View {
        VStack(spacing: 0) {
            // Custom keycap layout with labels on top
            GeometryReader { proxy in
                let availableWidth = max(1, proxy.size.width)
                let keycapWidth: CGFloat = 100
                let arrowWidth: CGFloat = 20
                let spacing: CGFloat = 16
                let baseWidth = keycapWidth * 2 + spacing * 2 + arrowWidth
                let scale = min(1, availableWidth / baseWidth)

                HStack(alignment: .top, spacing: spacing) {
                    // Input column: Keycap -> Dropdown -> App indicators
                    VStack(spacing: 4) {
                        MapperInputKeycap(
                            label: viewModel.inputLabel,
                            keyCode: viewModel.inputKeyCode,
                            isRecording: viewModel.isRecordingInput,
                            onTap: { viewModel.toggleInputRecording() }
                        )
                        appConditionDropdown
                        appMappingIndicators
                    }
                    .frame(width: keycapWidth)

                    // Arrow centered vertically with keycaps (100pt tall)
                    ZStack {
                        // Arrow centered with keycap height
                        Image(systemName: "arrow.right")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .frame(height: 100) // Match keycap height

                        // Reset button positioned at bottom of arrow column
                        if hasAnyModifiedMapping {
                            VStack {
                                Spacer()
                                Button {
                                    showingResetDialog = true
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Clear mapping options")
                                .accessibilityIdentifier("overlay-mapper-reset")
                            }
                            .frame(height: 100)
                        }
                    }
                    .frame(width: arrowWidth)

                    // Output column: Keycap -> Output type dropdown
                    VStack(spacing: 4) {
                        // Keycap with label overlay above
                        ZStack(alignment: .top) {
                            // Use different keycap for tap vs other behavior slots
                            if selectedBehaviorSlot == .tap {
                                MapperKeycapView(
                                    label: viewModel.outputLabel,
                                    isRecording: viewModel.isRecordingOutput,
                                    maxWidth: keycapWidth,
                                    appInfo: viewModel.selectedApp,
                                    systemActionInfo: viewModel.selectedSystemAction,
                                    urlFavicon: viewModel.selectedURLFavicon,
                                    onTap: { viewModel.toggleOutputRecording() }
                                )
                                .scaleEffect(outputKeycapScale)
                            } else {
                                // Hold/Combo use BehaviorSlotKeycap
                                BehaviorSlotKeycap(
                                    label: currentSlotOutputLabel,
                                    isConfigured: currentSlotIsConfigured,
                                    isRecording: isRecordingForCurrentSlot,
                                    slotName: selectedBehaviorSlot.label,
                                    onTap: { toggleRecordingForCurrentSlot() },
                                    onClear: { clearCurrentSlot() }
                                )
                                .scaleEffect(outputKeycapBounce ? 1.05 : 1.0)
                                .scaleEffect(outputKeycapScale)
                            }

                            // Behavior slot label floats above keycap
                            if selectedBehaviorSlot != .tap {
                                Text(selectedBehaviorSlot.label)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.accentColor)
                                    .offset(y: -18)
                                    .opacity(showBehaviorLabel ? 1 : 0)
                                    .scaleEffect(showBehaviorLabel ? 1 : 0.8)
                            }
                        }
                        // Output type dropdown shown for all slots
                        outputTypeDropdown

                        // Hold variant button - shown when Hold tab is selected and configured
                        if selectedBehaviorSlot == .hold, !viewModel.holdAction.isEmpty {
                            holdVariantButton
                        }

                        if selectedBehaviorSlot == .tap {
                            Button {
                                showMultiTapSlideOver = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Multi-tap actions")
                                        .font(.caption)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("overlay-mapper-multitap-link")
                        }
                    }
                    .frame(width: keycapWidth)
                }
                .border(showDebugBorders ? Color.blue : Color.clear, width: 1)
                .frame(width: baseWidth, height: proxy.size.height, alignment: .leading)
                .scaleEffect(scale, anchor: .leading)
                .frame(width: availableWidth, height: proxy.size.height, alignment: .leading)
            }
            .frame(height: 160)

            if viewModel.showAdvanced {
                AdvancedBehaviorContent(viewModel: viewModel)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer(minLength: 0)

            // Behavior state picker - flat controls with click feedback
            // Use ZStack to overlay status message without affecting layout
            ZStack(alignment: .top) {
                BehaviorStatePicker(
                    selectedState: $selectedBehaviorSlot,
                    configuredStates: configuredBehaviorSlots,
                    tapIsNonIdentity: tapHasNonIdentityMapping
                )
                .padding(.top, 8)

                // Status message overlaid above the picker (doesn't push content down)
                if let status = viewModel.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(viewModel.statusIsError ? .red : (status.contains("✓") ? .green : .secondary))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.ultraThinMaterial)
                        )
                        .offset(y: -8)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .animation(.easeOut(duration: 0.2), value: status)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var multiTapPanelContent: some View {
        MultiTapSlideOverView(viewModel: viewModel, sourceKey: viewModel.inputLabel)
    }

    /// App condition dropdown - subtle when not set, shows app icon when set
    private var appConditionDropdown: some View {
        let hasCondition = viewModel.selectedAppCondition != nil
        let displayText = viewModel.selectedAppCondition?.displayName ?? "Everywhere"

        return Button {
            // Start loading apps immediately BEFORE opening popover
            refreshRunningApps()
            isAppConditionPickerOpen = true
        } label: {
            HStack(spacing: 4) {
                if let app = viewModel.selectedAppCondition {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 12, height: 12)
                }
                Text(displayText)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .font(.caption2)
            .foregroundStyle(hasCondition ? .primary : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hasCondition ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(hasCondition ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overlay-mapper-app-condition")
        .popover(isPresented: $isAppConditionPickerOpen, arrowEdge: .bottom) {
            appConditionPopover
        }
    }

    /// Pre-load running apps when view appears for instant popover display
    private func preloadRunningApps() {
        cachedRunningApps = fetchRunningAppsSynchronously()
    }

    /// Refresh the cached running apps list - synchronous since NSWorkspace is fast
    private func refreshRunningApps() {
        cachedRunningApps = fetchRunningAppsSynchronously()
    }

    /// Fetch running apps synchronously (NSWorkspace.runningApplications is a fast cached call)
    private func fetchRunningAppsSynchronously() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular &&
                    app.bundleIdentifier != Bundle.main.bundleIdentifier &&
                    app.localizedName != nil
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    /// Popover content for app condition picker
    private var appConditionPopover: some View {
        ScrollView {
            VStack(spacing: 0) {
                everywhereOption
                Divider().opacity(0.2).padding(.horizontal, 8)
                onlyInHeader
                runningAppsList
                Divider().opacity(0.2).padding(.horizontal, 8)
                chooseAppOption
            }
            .padding(.vertical, 6)
        }
        .frame(minWidth: 240, maxHeight: 350)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
        .padding(4)
    }
}
