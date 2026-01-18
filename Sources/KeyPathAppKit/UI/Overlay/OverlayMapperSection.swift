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
    @State private var showingResetAllConfirmation = false

    /// Current behavior state being edited (tap is default)
    @State private var activeBehaviorState: BehaviorState = .tap
    /// Which behavior states have mappings configured for current key
    @State private var configuredStates: Set<BehaviorState> = []

    var body: some View {
        VStack(spacing: 8) {
            if shouldShowHealthGate {
                healthGateContent
            } else {
                mapperContent
                    .saturation(Double(1 - fadeAmount)) // Monochromatic when faded
                    .opacity(Double(1 - fadeAmount * 0.5)) // Fade with keyboard
            }
        }
        .onAppear {
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
            // Notify parent to highlight the A key
            onKeySelected?(viewModel.inputKeyCode)
            // Pre-load running apps for instant popover display
            preloadRunningApps()
        }
        .onDisappear {
            viewModel.stopKeyCapture()
        }
        .onChange(of: viewModel.inputKeyCode) { _, newKeyCode in
            onKeySelected?(newKeyCode)
        }
        .onReceive(NotificationCenter.default.publisher(for: .kanataLayerChanged)) { notification in
            if let layerName = notification.userInfo?["layerName"] as? String {
                viewModel.setLayer(layerName)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mapperDrawerKeySelected)) { notification in
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
        .onReceive(NotificationCenter.default.publisher(for: .openMapperAppConditionPicker)) { _ in
            // Open the app condition picker when requested (e.g., from "New Rule" button in App Rules tab)
            guard !shouldShowHealthGate else { return }
            refreshRunningApps()
            // Small delay to allow tab switch animation to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isAppConditionPickerOpen = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mapperSetAppCondition)) { notification in
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
        // Auto-save when output recording finishes and there's a valid mapping
        .onChange(of: viewModel.isRecordingOutput) { wasRecording, isRecording in
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
            }
        }
        .confirmationDialog(
            "Reset All Mappings?",
            isPresented: $showingResetAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset All", role: .destructive) {
                performResetAll()
            }
            .accessibilityIdentifier("overlay-mapper-reset-all-button")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("overlay-mapper-reset-all-cancel-button")
        } message: {
            Text("This will remove ALL custom key mappings including app-specific rules. Your enabled rule collections (Home Row Mods, etc.) will be preserved.")
        }
    }

    private let showDebugBorders = false

    /// Whether the current mapping has been modified from default (A->A)
    private var hasModifiedMapping: Bool {
        // Show reset if input != output or has an action assigned
        viewModel.inputLabel.lowercased() != viewModel.outputLabel.lowercased() ||
            viewModel.selectedApp != nil ||
            viewModel.selectedSystemAction != nil ||
            viewModel.selectedURL != nil ||
            viewModel.selectedAppCondition != nil
    }

    private var mapperContent: some View {
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
                    // Input column: Label -> Keycap -> Dropdown -> App indicators
                    VStack(spacing: 4) {
                        // Show behavior state in header when not on default "Tap"
                        HStack(spacing: 4) {
                            Text("In")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if activeBehaviorState != .tap {
                                Text("·")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(activeBehaviorState.label)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.accentColor)
                            }
                        }
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

                    // Arrow column with conditional reset below
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 3) {
                                // Triple-tap arrow = reset all with confirmation
                                showingResetAllConfirmation = true
                            }

                        // Reset button - only show if modified, centered under arrow
                        if hasModifiedMapping {
                            Button {
                                handleResetTap()
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Click to reset this key. Triple-click to reset all.")
                            .accessibilityIdentifier("overlay-mapper-reset")
                            .onTapGesture(count: 3) {
                                // Triple-click reset = reset all with confirmation
                                showingResetAllConfirmation = true
                            }
                            .onTapGesture(count: 1) {
                                handleResetTap()
                            }
                        }
                        Spacer()
                    }
                    .frame(width: arrowWidth)

                    // Output column: Label -> Keycap -> Output type dropdown
                    VStack(spacing: 4) {
                        Text("Out")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        MapperKeycapView(
                            label: viewModel.outputLabel,
                            isRecording: viewModel.isRecordingOutput,
                            maxWidth: keycapWidth,
                            appInfo: viewModel.selectedApp,
                            systemActionInfo: viewModel.selectedSystemAction,
                            urlFavicon: viewModel.selectedURLFavicon,
                            onTap: { viewModel.toggleOutputRecording() }
                        )
                        outputTypeDropdown
                    }
                    .frame(width: keycapWidth)
                }
                .border(showDebugBorders ? Color.blue : Color.clear, width: 1)
                .frame(width: baseWidth, height: proxy.size.height, alignment: .leading)
                .scaleEffect(scale, anchor: .leading)
                .frame(width: availableWidth, height: proxy.size.height, alignment: .leading)
            }
            .frame(height: 160)

            // Status message row
            if let status = viewModel.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(viewModel.statusIsError ? .red : (status.contains("✓") ? .green : .secondary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }

            if viewModel.showAdvanced {
                AdvancedBehaviorContent(viewModel: viewModel)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer(minLength: 0)

            // Behavior state icons bar
            behaviorStateBar
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Behavior State Bar

    /// Bar showing tap-dance behavior state icons
    private var behaviorStateBar: some View {
        HStack(spacing: 12) {
            ForEach(BehaviorState.allCases) { state in
                behaviorStateButton(for: state)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    /// Individual behavior state button
    private func behaviorStateButton(for state: BehaviorState) -> some View {
        let isActive = activeBehaviorState == state
        let isConfigured = configuredStates.contains(state)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                activeBehaviorState = state
            }
            // Open the Tap & Hold panel when a non-tap state is selected
            if state != .tap {
                NotificationCenter.default.post(
                    name: .openTapHoldPanel,
                    object: nil,
                    userInfo: [
                        "keyLabel": viewModel.inputLabel,
                        "keyCode": viewModel.inputKeyCode as Any
                    ]
                )
            }
        } label: {
            ZStack {
                // Icon
                Image(systemName: isActive ? state.iconFilled : state.icon)
                    .font(.system(size: 18, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.accentColor : (isConfigured ? .primary : .secondary))

                // Configured indicator dot (only if not active and has mapping)
                if isConfigured && !isActive {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .offset(x: 10, y: -10)
                }
            }
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(state.label)
        .accessibilityIdentifier("mapper-behavior-\(state.rawValue)")
        .accessibilityLabel(state.accessibilityLabel)
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

    /// Handle single tap on reset - clears current mapping with sound feedback
    private func handleResetTap() {
        viewModel.clear()
        onKeySelected?(nil)
        // Play success sound for feedback
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

            // Play success sound after reset completes
            SoundPlayer.shared.playSuccessSound()
        }
        onKeySelected?(nil)
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

    /// Output type dropdown - select what happens when the key is triggered
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
            return ("Launch App", "app.fill", false)
        } else if viewModel.selectedSystemAction != nil {
            return (viewModel.selectedSystemAction?.name ?? "System", "gearshape", false)
        } else if viewModel.selectedURL != nil {
            return ("Open URL", "link", false)
        } else {
            return ("Keystroke", "keyboard", true)
        }
    }

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

    /// Popover content for system action picker
    private var systemActionPopover: some View {
        let isKeystrokeSelected = viewModel.selectedSystemAction == nil
        let isSystemActionSelected = viewModel.selectedSystemAction != nil

        return ScrollView {
            VStack(spacing: 0) {
                // "Keystroke" option with checkmark
                Button {
                    // Revert to keystroke - deletes rule and resets output to match input
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

                // "System Action" header with checkmark (not a button, just indicator)
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
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                // Grouped system actions grid
                ForEach(systemActionGroups, id: \.title) { group in
                    systemActionGroupView(group)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(width: 320)
        .frame(maxHeight: 400)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
        .padding(4)
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

// MARK: - Behavior State

/// Tap-dance behavior states for key mapping
enum BehaviorState: String, CaseIterable, Identifiable {
    case tap
    case hold
    case doubleTap
    case tripleTap

    var id: String { rawValue }

    /// SF Symbol icon for this state
    var icon: String {
        switch self {
        case .tap: "1.circle"
        case .hold: "timer"
        case .doubleTap: "2.circle"
        case .tripleTap: "3.circle"
        }
    }

    /// Filled icon variant for active/configured state
    var iconFilled: String {
        switch self {
        case .tap: "1.circle.fill"
        case .hold: "timer"  // timer doesn't have a fill variant
        case .doubleTap: "2.circle.fill"
        case .tripleTap: "3.circle.fill"
        }
    }

    /// Short label for header
    var label: String {
        switch self {
        case .tap: "Tap"
        case .hold: "Hold"
        case .doubleTap: "Double Tap"
        case .tripleTap: "Triple Tap"
        }
    }

    /// Accessibility label
    var accessibilityLabel: String {
        switch self {
        case .tap: "Single tap behavior"
        case .hold: "Hold behavior"
        case .doubleTap: "Double tap behavior"
        case .tripleTap: "Triple tap behavior"
        }
    }
}
