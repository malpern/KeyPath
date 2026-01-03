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

    @StateObject private var viewModel = MapperViewModel()
    @State private var isLayerPickerOpen = false
    @State private var showingNewLayerSheet = false
    @State private var newLayerName = ""
    @State private var isSystemActionPickerOpen = false
    @State private var isAppConditionPickerOpen = false
    @State private var cachedRunningApps: [NSRunningApplication] = []
    @State private var isLoadingRunningApps = false

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
            // Notify parent to highlight the A key
            onKeySelected?(viewModel.inputKeyCode)
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

            // Update the mapper's input to the clicked key
            viewModel.setInputFromKeyClick(keyCode: keyCode, inputLabel: inputKey, outputLabel: outputKey)
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
                    // Input column: Label -> Keycap -> Dropdown
                    VStack(spacing: 4) {
                        Text("In")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        MapperInputKeycap(
                            label: viewModel.inputLabel,
                            keyCode: viewModel.inputKeyCode,
                            isRecording: viewModel.isRecordingInput,
                            onTap: { viewModel.toggleInputRecording() }
                        )
                        appConditionDropdown
                    }
                    .frame(width: keycapWidth)

                    // Arrow column with conditional reset below
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.title3)
                            .foregroundColor(.secondary)

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
                            .help("Click to reset this key. Double-click to reset all.")
                            .accessibilityIdentifier("overlay-mapper-reset")
                            .onTapGesture(count: 2) {
                                handleDoubleClickReset()
                            }
                            .onTapGesture(count: 1) {
                                handleResetTap()
                            }
                        }
                        Spacer()
                    }
                    .frame(width: arrowWidth)

                    // Output column: Label -> Keycap -> Dropdown
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
                        systemActionDropdown
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

            // Layer switcher styled like Add Shortcut button, pinned to bottom
            // Full width to match blue debug box
            GeometryReader { geo in
                layerSwitcherMenu(width: geo.size.width)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: 28) // Match button height
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingNewLayerSheet) {
            NewLayerSheet(
                layerName: $newLayerName,
                existingLayers: viewModel.getAvailableLayers(),
                onSubmit: { name in
                    viewModel.createLayer(name)
                    viewModel.setLayer(name)
                    newLayerName = ""
                    showingNewLayerSheet = false
                },
                onCancel: {
                    newLayerName = ""
                    showingNewLayerSheet = false
                }
            )
        }
    }

    /// App condition dropdown - subtle when not set, shows app icon when set
    private var appConditionDropdown: some View {
        let hasCondition = viewModel.selectedAppCondition != nil
        let displayText = viewModel.selectedAppCondition?.displayName ?? "Everywhere"

        return Button {
            isAppConditionPickerOpen.toggle()
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
            .opacity(hasCondition ? 1.0 : 0.6)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hasCondition ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(hasCondition ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overlay-mapper-app-condition")
        .popover(isPresented: $isAppConditionPickerOpen, arrowEdge: .bottom) {
            appConditionPopover
        }
        .onChange(of: isAppConditionPickerOpen) { _, isOpen in
            if isOpen {
                refreshRunningApps()
            }
        }
    }

    /// Refresh the cached running apps list asynchronously
    private func refreshRunningApps() {
        isLoadingRunningApps = true
        // Use Task to load apps off the main thread's blocking path
        Task {
            let apps = NSWorkspace.shared.runningApplications
                .filter { app in
                    app.activationPolicy == .regular &&
                    app.bundleIdentifier != Bundle.main.bundleIdentifier &&
                    app.localizedName != nil
                }
                .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            await MainActor.run {
                cachedRunningApps = apps
                isLoadingRunningApps = false
            }
        }
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
        if isLoadingRunningApps {
            HStack {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 12)
                Spacer()
            }
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
    }

    private func selectRunningApp(_ app: NSRunningApplication) {
        if let bundleId = app.bundleIdentifier,
           let name = app.localizedName {
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

    /// Handle single tap on reset - clears current mapping
    private func handleResetTap() {
        viewModel.clear()
        onKeySelected?(nil)
    }

    /// Handle double-click on reset - resets entire keyboard to defaults
    private func handleDoubleClickReset() {
        guard let manager = kanataViewModel?.underlyingManager else { return }
        Task {
            await viewModel.resetAllToDefaults(kanataManager: manager)
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

    /// System action dropdown - subtle when using keystroke, shows action when set
    private var systemActionDropdown: some View {
        let hasAction = viewModel.selectedSystemAction != nil
        let displayText = viewModel.selectedSystemAction?.name ?? "Keystroke"
        let displayIcon = viewModel.selectedSystemAction?.sfSymbol ?? "keyboard"

        return Button {
            isSystemActionPickerOpen.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: displayIcon)
                    .font(.system(size: 10))
                Text(displayText)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .font(.caption2)
            .foregroundStyle(hasAction ? .primary : .secondary)
            .opacity(hasAction ? 1.0 : 0.6)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hasAction ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(hasAction ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overlay-mapper-system-action")
        .popover(isPresented: $isSystemActionPickerOpen, arrowEdge: .bottom) {
            systemActionPopover
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
        ScrollView {
            VStack(spacing: 0) {
                // "Keystroke" option (clear system action)
                Button {
                    viewModel.selectedSystemAction = nil
                    isSystemActionPickerOpen = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: viewModel.selectedSystemAction == nil ? "checkmark" : "keyboard")
                            .font(.title2)
                            .frame(width: 28)
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

                // Grouped system actions
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
            viewModel.selectedSystemAction = action
            viewModel.outputLabel = action.name
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

    /// Returns an SF Symbol icon for a layer name
    private func iconForLayer(_ layer: String) -> String {
        switch layer.lowercased() {
        case "base":
            return "keyboard"
        case "nav", "navigation":
            return "arrow.up.arrow.down.square"
        case "num", "number", "numbers":
            return "number.square"
        case "sym", "symbol", "symbols":
            return "textformat.abc"
        case "fn", "function":
            return "fn"
        case "media":
            return "play.rectangle"
        case "mouse":
            return "cursorarrow.click"
        default:
            return "square.stack.3d.up"
        }
    }

    /// Layer switcher menu styled like the Add Shortcut button
    /// - Parameter width: Explicit width for the menu button
    @ViewBuilder
    private func layerSwitcherMenu(width: CGFloat) -> some View {
        let layerDisplayName = viewModel.currentLayer.lowercased() == "base" ? "Base Layer" : viewModel.currentLayer.capitalized
        let availableLayers = viewModel.getAvailableLayers()

        // Custom button that triggers popover
        Button {
            isLayerPickerOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.3.layers.3d")
                Text(layerDisplayName)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .rotationEffect(.degrees(isLayerPickerOpen ? 180 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isLayerPickerOpen)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(width: width)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overlay-mapper-layer-switcher")
        .popover(isPresented: $isLayerPickerOpen, arrowEdge: .top) {
            // Custom styled popover matching the button appearance
            VStack(spacing: 0) {
                ForEach(Array(availableLayers.enumerated()), id: \.element) { index, layer in
                    let displayName = layer.lowercased() == "base" ? "Base Layer" : layer.capitalized
                    let isSelected = viewModel.currentLayer.lowercased() == layer.lowercased()
                    let layerIcon = iconForLayer(layer)

                    Button {
                        viewModel.setLayer(layer)
                        isLayerPickerOpen = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: layerIcon)
                                .font(.body)
                                .frame(width: 20)
                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            Text(displayName)
                                .font(.body)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(LayerPickerItemButtonStyle())
                    .focusable(false) // Remove focus ring
                    .accessibilityIdentifier("layer-picker-\(layer)")

                    // Add separator between items (not after last)
                    if index < availableLayers.count - 1 {
                        Divider()
                            .opacity(0.2)
                            .padding(.horizontal, 8)
                    }
                }

                // New Layer option
                Divider()
                    .opacity(0.2)
                    .padding(.horizontal, 8)

                Button {
                    isLayerPickerOpen = false
                    showingNewLayerSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.semibold))
                        Text("New Layer...")
                            .font(.subheadline)
                        Spacer()
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(LayerPickerItemButtonStyle())
                .focusable(false)
                .accessibilityIdentifier("layer-picker-new")
            }
            .padding(.vertical, 6)
            .frame(minWidth: width)
            .background(.ultraThinMaterial) // Use material for consistent dark appearance
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            )
            .padding(4)
            .presentationCompactAdaptation(.none) // Prevent compact mode adaptation
        }
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
