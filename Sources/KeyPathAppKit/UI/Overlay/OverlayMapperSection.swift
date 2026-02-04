import AppKit
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

    @StateObject private var viewModel = MapperViewModel()
    @State private var isSystemActionPickerOpen = false
    @State private var isAppConditionPickerOpen = false
    @State private var cachedRunningApps: [NSRunningApplication] = []
    @State private var showingResetDialog = false
    @State private var isSystemActionsExpanded = false
    @State private var isLaunchAppsExpanded = false
    @State private var isLayersExpanded = false
    @State private var knownApps: [AppLaunchInfo] = []
    @State private var showingNewLayerDialog = false
    @State private var newLayerName = ""
    @State private var isHoldVariantPopoverOpen = false
    @State private var showMultiTapSlideOver = false

    /// Current behavior slot being edited (tap is default)
    @State private var selectedBehaviorSlot: BehaviorSlot = .tap
    /// Which behavior slots have actions configured for current key
    @State private var configuredBehaviorSlots: Set<BehaviorSlot> = []

    /// Animation state for output keycap behavior demonstration
    @State private var outputKeycapScale: CGFloat = 1.0
    @State private var behaviorAnimationTask: Task<Void, Never>?
    /// Animation state for behavior slot label (shows above output keycap)
    @State private var showBehaviorLabel = false
    /// Animation state for output keycap bounce when switching behavior slots
    @State private var outputKeycapBounce = false

    // MARK: - Computed Properties for Selected Slot

    /// The display label for the currently selected behavior slot's output
    /// Returns the configured action, or empty string if not configured
    private var currentSlotOutputLabel: String {
        switch selectedBehaviorSlot {
        case .tap:
            return viewModel.outputLabel
        case .hold:
            let action = viewModel.holdAction
            return action.isEmpty ? "" : KeyDisplayFormatter.format(action)
        case .combo:
            let action = viewModel.comboOutput
            return action.isEmpty ? "" : KeyDisplayFormatter.format(action)
        }
    }

    /// Whether the current slot has an action configured
    /// Hold/Combo are optional behaviors that must be explicitly added
    private var currentSlotIsConfigured: Bool {
        switch selectedBehaviorSlot {
        case .tap:
            // Tap always has a behavior (even if it's same key in/out)
            true
        case .hold:
            !viewModel.holdAction.isEmpty
        case .combo:
            viewModel.advancedBehavior.hasValidCombo
        }
    }

    /// Whether we're currently recording for the selected slot
    private var isRecordingForCurrentSlot: Bool {
        switch selectedBehaviorSlot {
        case .tap:
            viewModel.isRecordingOutput
        case .hold:
            viewModel.isRecordingHold
        case .combo:
            viewModel.isRecordingComboOutput
        }
    }

    /// Whether any recording mode is active (for ESC cancel)
    private var isAnyRecordingActive: Bool {
        viewModel.isRecordingInput ||
            viewModel.isRecordingOutput ||
            viewModel.isRecordingHold ||
            viewModel.isRecordingDoubleTap ||
            viewModel.isRecordingComboOutput
    }

    /// Cancel all active recording modes
    private func cancelAllRecording() {
        viewModel.stopRecording()
        viewModel.stopAllRecording()
    }

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

        let withURLDialog = withResetDialog.sheet(isPresented: $viewModel.showingURLDialog) {
            URLInputDialog(
                urlText: $viewModel.urlInputText,
                onSubmit: { viewModel.submitURL() },
                onCancel: { viewModel.showingURLDialog = false }
            )
        }

        return withURLDialog
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

    private var hasMultiTapConfigured: Bool {
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

    // MARK: - App-Specific Mapping Indicators

    /// Shows small app icons for apps that have mappings for the currently selected key
    /// Uses a fixed height to prevent layout shifting
    @ViewBuilder
    private var appMappingIndicators: some View {
        // Fixed height container to prevent layout shifts
        ZStack(alignment: .topLeading) {
            // Invisible spacer to reserve height (one row of 16px icons + padding)
            Color.clear.frame(height: 20)

            if !viewModel.appsWithCurrentKeyMapping.isEmpty,
               let keyCode = viewModel.inputKeyCode
            {
                let inputKey = OverlayKeyboardView.keyCodeToKanataName(keyCode)
                FlowLayout(spacing: 4) {
                    ForEach(viewModel.appsWithCurrentKeyMapping) { appKeymap in
                        appMappingIcon(for: appKeymap, inputKey: inputKey)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    /// Individual app icon button for the mapping indicators
    private func appMappingIcon(for appKeymap: AppKeymap, inputKey: String) -> some View {
        let bundleId = appKeymap.mapping.bundleIdentifier
        let displayName = appKeymap.mapping.displayName
        let mapping = appKeymap.overrides.first { $0.inputKey.lowercased() == inputKey.lowercased() }
        let output = mapping?.outputAction ?? "?"
        let tooltip = "\(displayName): \(inputKey) → \(output)"

        return Button {
            selectAppFromIndicator(appKeymap)
        } label: {
            if let icon = AppIconResolver.icon(forBundleIdentifier: bundleId) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityIdentifier("app-mapping-indicator-\(bundleId)")
    }

    /// Handle tap on an app mapping indicator - switches to that app's context
    private func selectAppFromIndicator(_ appKeymap: AppKeymap) {
        let bundleId = appKeymap.mapping.bundleIdentifier
        let displayName = appKeymap.mapping.displayName

        // Get icon using existing resolver
        let icon = AppIconResolver.icon(forBundleIdentifier: bundleId)
            ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: displayName)!

        // Create AppConditionInfo and set on view model
        viewModel.selectedAppCondition = AppConditionInfo(
            bundleIdentifier: bundleId,
            displayName: displayName,
            icon: icon
        )

        // Find the override for this input key and update output display
        if let keyCode = viewModel.inputKeyCode {
            let inputKey = OverlayKeyboardView.keyCodeToKanataName(keyCode)
            if let override = appKeymap.overrides.first(where: { $0.inputKey.lowercased() == inputKey.lowercased() }) {
                viewModel.outputLabel = KeyDisplayFormatter.format(override.outputAction)
            }
        }
    }

    @ViewBuilder
    private var everywhereOption: some View {
        Button {
            viewModel.selectedAppCondition = nil
            isAppConditionPickerOpen = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: viewModel.selectedAppCondition == nil ? "checkmark" : "globe")
                    .font(.title2)
                    .frame(width: 28)
                    .opacity(viewModel.selectedAppCondition == nil ? 1 : 0.6)
                Text("Everywhere")
                    .font(.body)
                Spacer()
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(LayerPickerItemButtonStyle())
        .focusable(false)
    }

    @ViewBuilder
    private var onlyInHeader: some View {
        HStack {
            Text("Only in...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var runningAppsList: some View {
        if cachedRunningApps.isEmpty {
            HStack {
                Spacer()
                Text("No apps running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 12)
        } else {
            ForEach(cachedRunningApps, id: \.processIdentifier) { app in
                runningAppButton(for: app)
            }
        }
    }

    @ViewBuilder
    private func runningAppButton(for app: NSRunningApplication) -> some View {
        Button {
            selectRunningApp(app)
        } label: {
            HStack(spacing: 10) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "app")
                        .font(.title3)
                        .frame(width: 24, height: 24)
                }
                Text(app.localizedName ?? "Unknown")
                    .font(.body)
                    .lineLimit(1)
                Spacer()
                if viewModel.selectedAppCondition?.bundleIdentifier == app.bundleIdentifier {
                    Image(systemName: "checkmark")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(LayerPickerItemButtonStyle())
        .focusable(false)
        .accessibilityIdentifier("overlay-mapper-running-app-\(app.bundleIdentifier ?? "pid-\(app.processIdentifier)")")
        .accessibilityLabel(app.localizedName ?? "Unknown app")
    }

    private func selectRunningApp(_ app: NSRunningApplication) {
        if let bundleId = app.bundleIdentifier,
           let name = app.localizedName
        {
            let icon = app.icon ?? NSWorkspace.shared.icon(forFile: app.bundleURL?.path ?? "")
            viewModel.selectedAppCondition = AppConditionInfo(
                bundleIdentifier: bundleId,
                displayName: name,
                icon: icon
            )
        }
        isAppConditionPickerOpen = false
    }

    @ViewBuilder
    private var chooseAppOption: some View {
        Button {
            isAppConditionPickerOpen = false
            pickAppForCondition()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.title3)
                    .frame(width: 28)
                Text("Choose App...")
                    .font(.body)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(LayerPickerItemButtonStyle())
        .focusable(false)
    }

    /// Clear all behavior slots for the current key (tap, hold, combo)
    private func clearAllBehaviorsForCurrentKey() {
        // Clear tap (remove any app/system/URL mapping)
        viewModel.revertToKeystroke()

        // Clear all advanced behaviors (hold, multi-tap, timing, etc.)
        viewModel.advancedBehavior.reset()

        // Update UI state
        updateConfiguredBehaviorSlots()
        onKeySelected?(nil)
        SoundPlayer.shared.playSuccessSound()
    }

    /// Perform the actual reset of entire keyboard to defaults, including app-specific rules
    private func performResetAll() {
        guard let manager = kanataViewModel?.underlyingManager else { return }
        Task {
            // Reset custom key mappings on all layers
            await viewModel.resetAllToDefaults(kanataManager: manager)

            // Also delete ALL app-specific rules
            do {
                let keymaps = await AppKeymapStore.shared.loadKeymaps()
                for keymap in keymaps {
                    try await AppKeymapStore.shared.removeKeymap(bundleIdentifier: keymap.mapping.bundleIdentifier)
                }

                // Regenerate config and restart Kanata if we deleted any app rules
                if !keymaps.isEmpty {
                    try await AppConfigGenerator.regenerateFromStore()
                    await AppContextService.shared.reloadMappings()
                    _ = await manager.restartKanata(reason: "All app rules reset")
                }
            } catch {
                AppLogger.shared.log("⚠️ [OverlayMapper] Failed to clear app rules: \(error)")
            }

            // Update UI state on main thread
            await MainActor.run {
                updateConfiguredBehaviorSlots()
            }

            // Play success sound after reset completes
            SoundPlayer.shared.playSuccessSound()
        }
        onKeySelected?(nil)
        // Also update immediately for responsiveness
        updateConfiguredBehaviorSlots()
    }

    /// Open file picker for app condition
    private func pickAppForCondition() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an app for this rule to apply only when it's active"

        if panel.runModal() == .OK, let url = panel.url {
            let displayName = url.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let bundleId = Bundle(url: url)?.bundleIdentifier ?? url.lastPathComponent
            viewModel.selectedAppCondition = AppConditionInfo(bundleIdentifier: bundleId, displayName: displayName, icon: icon)
        }
    }

    /// Toggle recording for the currently selected behavior slot
    private func toggleRecordingForCurrentSlot() {
        switch selectedBehaviorSlot {
        case .tap:
            viewModel.toggleOutputRecording()
        case .hold:
            viewModel.toggleHoldRecording()
        case .combo:
            viewModel.toggleComboOutputRecording()
        }
    }

    /// Clear the action for the currently selected behavior slot
    private func clearCurrentSlot() {
        switch selectedBehaviorSlot {
        case .tap:
            viewModel.revertToKeystroke()
        case .hold:
            viewModel.advancedBehavior.holdAction = ""
        case .combo:
            viewModel.advancedBehavior.comboKeys = []
            viewModel.advancedBehavior.comboOutput = ""
        }
        updateConfiguredBehaviorSlots()
        SoundPlayer.shared.playSuccessSound()
    }

    /// Update which behavior slots have actions configured
    private func updateConfiguredBehaviorSlots() {
        var slots: Set<BehaviorSlot> = []

        // Check tap slot
        let tapHasAction = viewModel.selectedApp != nil ||
            viewModel.selectedSystemAction != nil ||
            viewModel.selectedURL != nil ||
            viewModel.outputLabel.lowercased() != viewModel.inputLabel.lowercased() ||
            hasMultiTapConfigured
        if tapHasAction {
            slots.insert(.tap)
        }

        // Check hold slot
        if !viewModel.holdAction.isEmpty {
            slots.insert(.hold)
        }

        // Check combo slot
        if viewModel.advancedBehavior.hasValidCombo {
            slots.insert(.combo)
        }

        configuredBehaviorSlots = slots
    }

    /// Play animation on the output keycap to demonstrate the selected behavior
    /// Choreography: For non-tap slots, label fades in first, then keycap bounces
    private func playBehaviorAnimation(for slot: BehaviorSlot) {
        // Cancel any existing animation
        behaviorAnimationTask?.cancel()

        // Reset label state when switching slots
        showBehaviorLabel = false
        outputKeycapBounce = false

        behaviorAnimationTask = Task { @MainActor in
            switch slot {
            case .tap:
                // Single press animation - no label needed
                withAnimation(.easeIn(duration: 0.1)) {
                    outputKeycapScale = 0.88
                }
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                    outputKeycapScale = 1.0
                }

            case .hold:
                // Choreography: label first, then keycap animation
                withAnimation(.easeOut(duration: 0.12)) {
                    showBehaviorLabel = true
                }
                try? await Task.sleep(for: .milliseconds(80))
                // Bounce the keycap
                withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                    outputKeycapBounce = true
                }
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                    outputKeycapBounce = false
                }
                // Then press-hold animation
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.easeIn(duration: 0.15)) {
                    outputKeycapScale = 0.85
                }
                try? await Task.sleep(for: .milliseconds(500))
                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                    outputKeycapScale = 1.0
                }

            case .combo:
                // Choreography: label first, then keycap animation
                withAnimation(.easeOut(duration: 0.12)) {
                    showBehaviorLabel = true
                }
                try? await Task.sleep(for: .milliseconds(80))
                // Bounce the keycap
                withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                    outputKeycapBounce = true
                }
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                    outputKeycapBounce = false
                }
                // Combo animation: two quick simultaneous presses
                try? await Task.sleep(for: .milliseconds(100))
                // Simulate pressing multiple keys together
                withAnimation(.easeIn(duration: 0.1)) {
                    outputKeycapScale = 0.85
                }
                try? await Task.sleep(for: .milliseconds(200))
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                    outputKeycapScale = 1.05
                }
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                    outputKeycapScale = 1.0
                }
            }
        }
    }

    /// Output type dropdown - select what happens when the key is triggered
    // MARK: - Hold Variant Picker

    /// Button that opens the hold variant popover
    private var holdVariantButton: some View {
        Button {
            isHoldVariantPopoverOpen = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gearshape")
                    .font(.system(size: 10))
                Text(currentHoldVariant.label)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("hold-variant-button")
        .popover(isPresented: $isHoldVariantPopoverOpen, arrowEdge: .bottom) {
            holdVariantPopover
        }
    }

    /// Popover content for hold variant selection
    private var holdVariantPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(HoldVariant.allCases, id: \.self) { variant in
                holdVariantRow(variant)

                if variant != HoldVariant.allCases.last {
                    Divider().opacity(0.2).padding(.horizontal, 8)
                }
            }

            // Custom keys input (shown when Custom is selected)
            if viewModel.holdBehavior == .customKeys {
                Divider().opacity(0.3).padding(.horizontal, 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tap-trigger keys:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g., a s d f j k l", text: $viewModel.customTapKeysText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit {
                            // Auto-save when custom keys are entered
                            if let manager = kanataViewModel?.underlyingManager, viewModel.inputKeyCode != nil {
                                Task {
                                    await viewModel.save(kanataManager: manager)
                                }
                            }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.2), value: viewModel.holdBehavior)
    }

    /// Single row in hold variant popover
    private func holdVariantRow(_ variant: HoldVariant) -> some View {
        let isSelected = currentHoldVariant == variant

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.holdBehavior = variant.toBehaviorType
            }
            // Auto-save when variant changes
            if let manager = kanataViewModel?.underlyingManager, viewModel.inputKeyCode != nil {
                Task {
                    await viewModel.save(kanataManager: manager)
                }
            }
            // Close popover unless switching to Custom (need to show text field)
            if variant != .custom {
                isHoldVariantPopoverOpen = false
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(variant.label)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(variant.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(LayerPickerItemButtonStyle())
        .accessibilityIdentifier("hold-variant-\(variant.rawValue)")
    }

    /// Current hold variant based on viewModel.holdBehavior
    private var currentHoldVariant: HoldVariant {
        HoldVariant.from(viewModel.holdBehavior)
    }

    /// Hold behavior variants with user-friendly labels and explanations
    private enum HoldVariant: String, CaseIterable {
        case basic
        case press
        case release
        case custom

        var label: String {
            switch self {
            case .basic: "Basic"
            case .press: "Eager"
            case .release: "Permissive"
            case .custom: "Custom Keys"
            }
        }

        var explanation: String {
            switch self {
            case .basic:
                "Hold activates after timeout"
            case .press:
                "Hold activates when another key is pressed (best for home-row mods)"
            case .release:
                "Tap registers even if another key was pressed during timeout"
            case .custom:
                "Only specific keys trigger early tap"
            }
        }

        var toBehaviorType: MapperViewModel.HoldBehaviorType {
            switch self {
            case .basic: .basic
            case .press: .triggerEarly
            case .release: .quickTap
            case .custom: .customKeys
            }
        }

        static func from(_ behaviorType: MapperViewModel.HoldBehaviorType) -> HoldVariant {
            switch behaviorType {
            case .basic: .basic
            case .triggerEarly: .press
            case .quickTap: .release
            case .customKeys: .custom
            }
        }
    }

    // MARK: - Output Type Dropdown

    private var outputTypeDropdown: some View {
        let currentType = outputTypeDisplayInfo

        return Button {
            isSystemActionPickerOpen = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: currentType.icon)
                    .font(.system(size: 10))
                Text(currentType.label)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .font(.caption2)
            .foregroundStyle(currentType.isDefault ? .secondary : .primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(currentType.isDefault ? Color.primary.opacity(0.04) : Color.accentColor.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(currentType.isDefault ? Color.primary.opacity(0.2) : Color.accentColor.opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overlay-mapper-output-type")
        .accessibilityLabel("Select output action type")
        .popover(isPresented: $isSystemActionPickerOpen, arrowEdge: .bottom) {
            systemActionPopover
        }
    }

    /// Info about current output type for display
    private var outputTypeDisplayInfo: (label: String, icon: String, isDefault: Bool) {
        if viewModel.selectedApp != nil {
            ("Launch App", "app.fill", false)
        } else if viewModel.selectedSystemAction != nil {
            (viewModel.selectedSystemAction?.name ?? "System", "gearshape", false)
        } else if viewModel.selectedURL != nil {
            ("Open URL", "link", false)
        } else if selectedLayerOutput != nil {
            ("Go to Layer", "square.stack.3d.up", false)
        } else {
            ("Keystroke", "keyboard", true)
        }
    }

    /// Currently selected layer for "Go to Layer" output
    @State private var selectedLayerOutput: String?

    // MARK: - System Action Groups

    /// System actions grouped for the popover
    private struct SystemActionGroup {
        let title: String
        let actions: [SystemActionInfo]
    }

    private var systemActionGroups: [SystemActionGroup] {
        let all = SystemActionInfo.allActions
        return [
            SystemActionGroup(title: "System", actions: all.filter {
                ["spotlight", "mission-control", "launchpad", "dnd", "notification-center", "dictation", "siri"].contains($0.id)
            }),
            SystemActionGroup(title: "Playback", actions: all.filter {
                ["play-pause", "next-track", "prev-track"].contains($0.id)
            }),
            SystemActionGroup(title: "Volume", actions: all.filter {
                ["mute", "volume-up", "volume-down"].contains($0.id)
            }),
            SystemActionGroup(title: "Display", actions: all.filter {
                ["brightness-up", "brightness-down"].contains($0.id)
            })
        ]
    }

    /// Dynamic max height for the popover based on expansion state
    private var expandedMaxHeight: CGFloat {
        let baseHeight: CGFloat = 270 // Height for collapsed state (5 rows + dividers)
        let systemActionsHeight: CGFloat = 480 // System actions grid when expanded
        let appsHeight: CGFloat = 300 // Apps list when expanded
        let layersHeight: CGFloat = 250 // Layers list when expanded

        var height = baseHeight
        if isSystemActionsExpanded { height += systemActionsHeight }
        if isLaunchAppsExpanded { height += appsHeight }
        if isLayersExpanded { height += layersHeight }

        return min(height, 750) // Cap at reasonable screen height
    }

    private var popoverMaxHeight: CGFloat {
        if isSystemActionsExpanded {
            return min(expandedMaxHeight * 2, 1000)
        }
        return expandedMaxHeight
    }

    /// Popover content for output type picker with collapsible sections
    private var systemActionPopover: some View {
        let isKeystrokeSelected = viewModel.selectedSystemAction == nil && viewModel.selectedApp == nil && selectedLayerOutput == nil
        let isSystemActionSelected = viewModel.selectedSystemAction != nil
        let isAppSelected = viewModel.selectedApp != nil
        let isLayerSelected = selectedLayerOutput != nil
        let isURLSelected = viewModel.selectedURL != nil

        return ScrollView {
            VStack(spacing: 0) {
                // "Keystroke" option
                Button {
                    collapseAllSections()
                    selectedLayerOutput = nil
                    viewModel.revertToKeystroke()
                    isSystemActionPickerOpen = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isKeystrokeSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isKeystrokeSelected ? Color.accentColor : .secondary)
                            .frame(width: 24)
                        Image(systemName: "keyboard")
                            .font(.body)
                            .frame(width: 20)
                        Text("Keystroke")
                            .font(.body)
                        Spacer()
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(LayerPickerItemButtonStyle())
                .focusable(false)

                Divider().opacity(0.2).padding(.horizontal, 8)

                // "System Action" option - clickable to expand/collapse
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if !isSystemActionsExpanded {
                            isLaunchAppsExpanded = false
                            isLayersExpanded = false
                        }
                        isSystemActionsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isSystemActionSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSystemActionSelected ? Color.accentColor : .secondary)
                            .frame(width: 24)
                        Image(systemName: "gearshape")
                            .font(.body)
                            .frame(width: 20)
                        Text("System Action")
                            .font(.body)
                        Spacer()
                        if let action = viewModel.selectedSystemAction {
                            Text(action.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: isSystemActionsExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(LayerPickerItemButtonStyle())
                .focusable(false)

                // Collapsible system actions grid
                if isSystemActionsExpanded {
                    VStack(spacing: 0) {
                        ForEach(systemActionGroups, id: \.title) { group in
                            systemActionGroupView(group)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider().opacity(0.2).padding(.horizontal, 8)

                // "Launch App" option - clickable to expand/collapse
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if !isLaunchAppsExpanded {
                            isSystemActionsExpanded = false
                            isLayersExpanded = false
                        }
                        isLaunchAppsExpanded.toggle()
                        if isLaunchAppsExpanded {
                            loadKnownApps()
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isAppSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isAppSelected ? Color.accentColor : .secondary)
                            .frame(width: 24)
                        if let app = viewModel.selectedApp {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "app.fill")
                                .font(.body)
                                .frame(width: 20)
                        }
                        Text(viewModel.selectedApp?.name ?? "Launch App")
                            .font(.body)
                        Spacer()
                        if let app = viewModel.selectedApp {
                            Text(app.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: isLaunchAppsExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(LayerPickerItemButtonStyle())
                .focusable(false)

                // Collapsible known apps list
                if isLaunchAppsExpanded {
                    launchAppsExpandedContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider().opacity(0.2).padding(.horizontal, 8)

                // "Open URL" option
                Button {
                    collapseAllSections()
                    isSystemActionPickerOpen = false
                    viewModel.showURLInputDialog()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isURLSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isURLSelected ? Color.accentColor : .secondary)
                            .frame(width: 24)
                        Image(systemName: "link")
                            .font(.body)
                            .frame(width: 20)
                        Text("Open URL")
                            .font(.body)
                        Spacer()
                        if let url = viewModel.selectedURL {
                            Text(KeyMappingFormatter.extractDomain(from: url))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(LayerPickerItemButtonStyle())
                .focusable(false)
                .accessibilityIdentifier("overlay-mapper-output-url")

                Divider().opacity(0.2).padding(.horizontal, 8)

                // "Go to Layer" option - clickable to expand/collapse
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if !isLayersExpanded {
                            isSystemActionsExpanded = false
                            isLaunchAppsExpanded = false
                        }
                        isLayersExpanded.toggle()
                        if isLayersExpanded {
                            Task { await viewModel.refreshAvailableLayers() }
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isLayerSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isLayerSelected ? Color.accentColor : .secondary)
                            .frame(width: 24)
                        Image(systemName: "square.stack.3d.up")
                            .font(.body)
                            .frame(width: 20)
                        Text("Go to Layer")
                            .font(.body)
                        Spacer()
                        if let layer = selectedLayerOutput {
                            Text(layer.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: isLayersExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(LayerPickerItemButtonStyle())
                .focusable(false)

                // Collapsible layers list
                if isLayersExpanded {
                    layersExpandedContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, 6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 320)
        .frame(maxHeight: popoverMaxHeight)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.25), value: isSystemActionsExpanded)
        .animation(.easeInOut(duration: 0.25), value: isLaunchAppsExpanded)
        .animation(.easeInOut(duration: 0.25), value: isLayersExpanded)
        .padding(4)
        .onAppear {
            // Auto-expand the relevant section based on current selection
            isSystemActionsExpanded = viewModel.selectedSystemAction != nil
            isLaunchAppsExpanded = viewModel.selectedApp != nil
            isLayersExpanded = selectedLayerOutput != nil
            if isLaunchAppsExpanded {
                loadKnownApps()
            }
        }
        .sheet(isPresented: $showingNewLayerDialog) {
            newLayerDialogContent
        }
    }

    /// Collapse all expandable sections
    private func collapseAllSections() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSystemActionsExpanded = false
            isLaunchAppsExpanded = false
            isLayersExpanded = false
        }
    }

    // MARK: - Launch Apps Expanded Content

    /// Content shown when Launch Apps section is expanded
    private var launchAppsExpandedContent: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("Known Apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // List of known apps
            if knownApps.isEmpty {
                HStack {
                    Text("No apps configured yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else {
                ForEach(knownApps, id: \.name) { app in
                    knownAppRow(app)
                }
            }

            // "Add App..." option
            Button {
                pickAppForOutput()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.body)
                        .frame(width: 20)
                    Text("Add App...")
                        .font(.body)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(LayerPickerItemButtonStyle())
            .focusable(false)
            .accessibilityIdentifier("overlay-add-app-button")
        }
    }

    /// Button for a known app in the list
    private func knownAppRow(_ app: AppLaunchInfo) -> some View {
        let isSelected = viewModel.selectedApp?.bundleIdentifier == app.bundleIdentifier
        let appIdentifier = (app.bundleIdentifier ?? app.name)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return Button {
            viewModel.selectedApp = app
            viewModel.selectedSystemAction = nil
            viewModel.selectedURL = nil
            selectedLayerOutput = nil
            viewModel.outputLabel = app.name
            isSystemActionPickerOpen = false

            // Auto-save if input is set
            if let manager = kanataViewModel?.underlyingManager, viewModel.inputKeyCode != nil {
                Task {
                    await viewModel.save(kanataManager: manager)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(app.name)
                    .font(.body)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(LayerPickerItemButtonStyle())
        .focusable(false)
        .accessibilityIdentifier("overlay-known-app-\(appIdentifier)")
    }

    /// Load known apps from existing mappings
    private func loadKnownApps() {
        Task {
            // Get apps from app-specific keymaps
            let keymaps = await AppKeymapStore.shared.loadKeymaps()
            var apps: [AppLaunchInfo] = []
            var seenAppKeys: Set<String> = []

            for keymap in keymaps {
                let bundleId = keymap.mapping.bundleIdentifier
                let name = keymap.mapping.displayName

                // Get icon
                let icon: NSImage
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                    icon = NSWorkspace.shared.icon(forFile: url.path)
                    icon.size = NSSize(width: 32, height: 32)
                } else {
                    icon = NSImage(systemSymbolName: "app.fill", accessibilityDescription: name) ?? NSImage()
                }

                let appKey = bundleId.isEmpty ? name : bundleId
                if seenAppKeys.insert(appKey).inserted {
                    apps.append(AppLaunchInfo(name: name, bundleIdentifier: bundleId, icon: icon))
                }
            }

            // Add running apps
            let runningApps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular || $0.activationPolicy == .accessory }
            for app in runningApps {
                guard let url = app.bundleURL else { continue }
                guard isUserFacingAppURL(url) else { continue }
                let appInfo = appLaunchInfo(for: url)
                let appKey = appInfo.bundleIdentifier ?? url.path
                if seenAppKeys.insert(appKey).inserted {
                    apps.append(appInfo)
                }
            }

            await MainActor.run {
                knownApps = apps.sorted { $0.name < $1.name }
            }
        }
    }

    private func appLaunchInfo(for url: URL) -> AppLaunchInfo {
        let displayName = url.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        let bundleId = Bundle(url: url)?.bundleIdentifier
        return AppLaunchInfo(name: displayName, bundleIdentifier: bundleId, icon: icon)
    }

    private func isUserFacingAppURL(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.hasPrefix("/Applications/") ||
            path.hasPrefix("/System/Applications/") ||
            path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path)
    }

    // MARK: - Layers Expanded Content

    /// Content shown when Go to Layer section is expanded
    private var layersExpandedContent: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("Available Layers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // List of available layers
            ForEach(viewModel.availableLayers, id: \.self) { layer in
                layerRow(layer)
            }

            // "Create New Layer..." option
            Button {
                newLayerName = ""
                showingNewLayerDialog = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle")
                        .font(.body)
                        .frame(width: 20)
                    Text("Create New Layer...")
                        .font(.body)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(LayerPickerItemButtonStyle())
            .focusable(false)
        }
    }

    /// Button for a layer in the list
    private func layerRow(_ layer: String) -> some View {
        let isSelected = selectedLayerOutput == layer
        let isSystemLayer = viewModel.isSystemLayer(layer)
        let layerIdentifier = layer
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")

        return Button {
            selectLayerOutput(layer)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSystemLayer ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                    .font(.body)
                    .foregroundStyle(isSystemLayer ? .blue : .primary)
                    .frame(width: 20)
                Text(layer.capitalized)
                    .font(.body)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(LayerPickerItemButtonStyle())
        .focusable(false)
        .accessibilityIdentifier("overlay-layer-\(layerIdentifier)")
    }

    /// Select a layer as the output action
    private func selectLayerOutput(_ layer: String) {
        selectedLayerOutput = layer
        viewModel.selectedApp = nil
        viewModel.selectedSystemAction = nil
        viewModel.selectedURL = nil
        viewModel.outputLabel = "→ \(layer.capitalized)"
        isSystemActionPickerOpen = false

        // Save the layer switch mapping
        if let manager = kanataViewModel?.underlyingManager, viewModel.inputKeyCode != nil {
            Task {
                await saveLayerSwitchMapping(layer: layer, kanataManager: manager)
            }
        }
    }

    /// Save a mapping that switches to a layer
    private func saveLayerSwitchMapping(layer: String, kanataManager: RuntimeCoordinator) async {
        guard let inputSeq = viewModel.inputKeyCode else { return }

        let inputKey = OverlayKeyboardView.keyCodeToKanataName(inputSeq)
        let outputKanata = "(layer-switch \(layer))"

        var customRule = kanataManager.makeCustomRule(input: inputKey, output: outputKanata)
        customRule.notes = "Switch to \(layer) layer"

        let success = await kanataManager.saveCustomRule(customRule, skipReload: false)
        if success {
            viewModel.statusMessage = "✓ Saved"
            SoundPlayer.shared.playSuccessSound()
            AppLogger.shared.log("✅ [OverlayMapper] Saved layer switch: \(inputKey) → layer:\(layer)")
        } else {
            viewModel.statusMessage = "Failed to save"
            viewModel.statusIsError = true
        }
    }

    /// Dialog for creating a new layer
    private var newLayerDialogContent: some View {
        VStack(spacing: 16) {
            Text("Create New Layer")
                .font(.headline)

            TextField("Layer name", text: $newLayerName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .accessibilityIdentifier("overlay-layer-dialog-name")

            HStack(spacing: 12) {
                Button("Cancel") {
                    showingNewLayerDialog = false
                }
                .keyboardShortcut(.escape)
                .accessibilityIdentifier("overlay-layer-dialog-cancel")

                Button("Create") {
                    if !newLayerName.isEmpty {
                        viewModel.createLayer(newLayerName)
                        showingNewLayerDialog = false
                        // Select the new layer
                        Task {
                            await viewModel.refreshAvailableLayers()
                            selectLayerOutput(newLayerName.lowercased())
                        }
                    }
                }
                .keyboardShortcut(.return)
                .disabled(newLayerName.isEmpty)
                .accessibilityIdentifier("overlay-layer-dialog-create")
            }
        }
        .padding(20)
        .frame(minWidth: 280)
    }

    /// Open file picker to choose an app for the output action
    private func pickAppForOutput() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an app to launch when this key is pressed"

        if panel.runModal() == .OK, let url = panel.url {
            let displayName = url.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            let bundleId = Bundle(url: url)?.bundleIdentifier ?? url.lastPathComponent
            viewModel.selectedApp = AppLaunchInfo(name: displayName, bundleIdentifier: bundleId, icon: icon)
            isSystemActionPickerOpen = false
        }
    }

    @ViewBuilder
    private func systemActionGroupView(_ group: SystemActionGroup) -> some View {
        // Section header
        HStack {
            Text(group.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)

        // 3-column grid
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(group.actions) { action in
                systemActionButton(action)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func systemActionButton(_ action: SystemActionInfo) -> some View {
        let isSelected = viewModel.selectedSystemAction?.id == action.id
        Button {
            // Use the proper method which handles auto-save
            viewModel.selectSystemAction(action)
            isSystemActionPickerOpen = false
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                        .frame(width: 40, height: 40)
                    Image(systemName: action.sfSymbol)
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                }
                Text(action.name)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityIdentifier("system-action-\(action.id)")
    }

    private var shouldShowHealthGate: Bool {
        if healthIndicatorState == .checking { return true }
        if case .unhealthy = healthIndicatorState { return true }
        return false
    }

    private var healthGateContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.orange)

                Text(healthGateTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Text(healthGateMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: onHealthTap) {
                Text(healthGateButtonTitle)
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier("overlay-mapper-fix-issues")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(isDark ? 0.18 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private var healthGateTitle: String {
        switch healthIndicatorState {
        case .checking:
            "System Not Ready"
        case let .unhealthy(issueCount):
            issueCount == 1 ? "1 Issue Found" : "\(issueCount) Issues Found"
        case .healthy, .dismissed:
            "System Ready"
        }
    }

    private var healthGateMessage: String {
        switch healthIndicatorState {
        case .checking:
            "Checking system health before enabling the mapper."
        case let .unhealthy(issueCount):
            issueCount == 1
                ? "Fix the issue to enable quick remapping in the drawer."
                : "Fix the issues to enable quick remapping in the drawer."
        case .healthy, .dismissed:
            "System health is good."
        }
    }

    private var healthGateButtonTitle: String {
        switch healthIndicatorState {
        case .checking:
            "Open Setup"
        case .unhealthy:
            "Fix Issues"
        case .healthy, .dismissed:
            "Open Setup"
        }
    }
}

// MARK: - Layer Picker Item Button Style

/// Custom button style for layer picker items with hover effect
private struct LayerPickerItemButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovering ? 0.1 : (configuration.isPressed ? 0.15 : 0)))
            )
            .animation(.easeInOut(duration: 0.1), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}
