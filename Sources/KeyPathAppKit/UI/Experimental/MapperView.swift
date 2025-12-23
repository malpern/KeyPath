import AppKit
import KeyPathCore
import SwiftUI

// MARK: - Notification for preset values

extension Notification.Name {
    /// Posted when Mapper should apply preset values (from overlay click)
    static let mapperPresetValues = Notification.Name("KeyPath.MapperPresetValues")
}

// MARK: - Mapper View

/// Experimental key mapping page with visual keycap-based input/output capture.
/// Accessible from File menu as "Mapper".
struct MapperView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @StateObject private var viewModel = MapperViewModel()

    /// Optional preset input from overlay click
    var presetInput: String?
    /// Optional preset output from overlay click
    var presetOutput: String?
    /// Optional preset layer from overlay click
    var presetLayer: String?
    /// Optional input keyCode from overlay click (for proper keycap rendering)
    var presetInputKeyCode: UInt16?
    /// Optional app identifier from overlay click
    var presetAppIdentifier: String?
    /// Optional system action identifier from overlay click
    var presetSystemActionIdentifier: String?
    /// Optional URL identifier from overlay click
    var presetURLIdentifier: String?

    /// Error alert state
    @State private var showingErrorAlert = false
    @State private var errorAlertMessage = ""

    /// Reset all confirmation dialog
    @State private var showingResetAllConfirmation = false

    /// Inspector panel visibility
    @State private var isInspectorOpen = false

    var body: some View {
        HStack(spacing: 0) {
            // Main content area
            VStack(spacing: 12) {
                // Keycaps for input and output
                MapperKeycapPair(
                    inputLabel: viewModel.inputLabel,
                    inputKeyCode: viewModel.inputKeyCode,
                    outputLabel: viewModel.outputLabel,
                    isRecordingInput: viewModel.isRecordingInput,
                    isRecordingOutput: viewModel.isRecordingOutput,
                    outputAppInfo: viewModel.selectedApp,
                    outputSystemActionInfo: viewModel.selectedSystemAction,
                    outputURLFavicon: viewModel.selectedURLFavicon,
                    onInputTap: { viewModel.toggleInputRecording() },
                    onOutputTap: { viewModel.toggleOutputRecording() }
                )

                // Advanced behavior content (shown when toggle in sidebar is ON)
                if viewModel.showAdvanced {
                    AdvancedBehaviorContent(viewModel: viewModel)
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer(minLength: 8)

                // Bottom bar: layer indicator (left), reset button (right)
                HStack {
                    Text(viewModel.currentLayer.lowercased() == "base" ? "Base Layer" : viewModel.currentLayer.lowercased())
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(minWidth: 300, alignment: .top)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    ResetMappingButton(
                        onSingleClick: { viewModel.clear() },
                        onDoubleClick: { showingResetAllConfirmation = true }
                    )
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isInspectorOpen.toggle() }
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .help(isInspectorOpen ? "Hide Inspector" : "Show Inspector")
                }
            }

            // Inspector panel (slides in from right)
            if isInspectorOpen {
                MapperInspectorPanel(viewModel: viewModel)
                    .frame(width: 240)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(minWidth: isInspectorOpen ? 540 : 300, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: isInspectorOpen)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showAdvanced)
        .animation(.easeInOut(duration: 0.25), value: viewModel.canSave)
        .animation(.easeInOut(duration: 0.25), value: viewModel.statusMessage)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.inputLabel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.outputLabel)
        .onAppear {
            viewModel.configure(kanataManager: kanataManager.underlyingManager)
            // Apply preset values if provided
            if let presetInput, let presetOutput {
                viewModel.applyPresets(
                    input: presetInput,
                    output: presetOutput,
                    layer: presetLayer,
                    inputKeyCode: presetInputKeyCode,
                    appIdentifier: presetAppIdentifier,
                    systemActionIdentifier: presetSystemActionIdentifier,
                    urlIdentifier: presetURLIdentifier
                )
            } else {
                // No preset - use current layer from kanataManager
                viewModel.setLayer(kanataManager.currentLayerName)
            }
        }
        .onDisappear {
            viewModel.stopKeyCapture()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mapperPresetValues)) { notification in
            // Handle preset updates when window is already open
            if let input = notification.userInfo?["input"] as? String,
               let output = notification.userInfo?["output"] as? String
            {
                let layer = notification.userInfo?["layer"] as? String
                let inputKeyCode = notification.userInfo?["inputKeyCode"] as? UInt16
                let appIdentifier = notification.userInfo?["appIdentifier"] as? String
                let systemActionIdentifier = notification.userInfo?["systemActionIdentifier"] as? String
                let urlIdentifier = notification.userInfo?["urlIdentifier"] as? String
                viewModel.applyPresets(
                    input: input,
                    output: output,
                    layer: layer,
                    inputKeyCode: inputKeyCode,
                    appIdentifier: appIdentifier,
                    systemActionIdentifier: systemActionIdentifier,
                    urlIdentifier: urlIdentifier
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kanataLayerChanged)) { notification in
            // Update layer when it changes (if not opened from overlay with specific layer)
            if let layerName = notification.userInfo?["layerName"] as? String,
               viewModel.originalInputKey == nil
            { // Only auto-update if not opened from overlay
                viewModel.setLayer(layerName)
            }
        }
        .onChange(of: kanataManager.lastError) { _, newError in
            if let error = newError {
                errorAlertMessage = error
                showingErrorAlert = true
                // Clear the error so it doesn't re-trigger
                kanataManager.lastError = nil
            }
        }
        .alert("Configuration Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorAlertMessage)
        }
        .alert("Reset Entire Layout?", isPresented: $showingResetAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Yes, Reset", role: .destructive) {
                Task {
                    await viewModel.resetAllToDefaults(kanataManager: kanataManager.underlyingManager)
                }
            }
        } message: {
            Text("This will remove all custom rules and restore the keyboard to its default mappings.")
        }
        .sheet(isPresented: $viewModel.showingURLDialog) {
            URLInputDialog(
                urlText: $viewModel.urlInputText,
                onSubmit: { viewModel.submitURL() },
                onCancel: { viewModel.showingURLDialog = false }
            )
        }
    }
}

// MARK: - Mapper Inspector Panel

/// Inspector panel with Liquid Glass styling for the Mapper window.
/// Contains output type selection (key, app, system action, URL).
private struct MapperInspectorPanel: View {
    @ObservedObject var viewModel: MapperViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Output Type Options
                outputTypeSection

                Divider()
                    .padding(.vertical, 4)

                // Advanced Behavior Toggle (own section, before system actions)
                advancedBehaviorSection

                Divider()
                    .padding(.vertical, 4)

                // System Actions Section
                systemActionsSection
            }
            .padding(16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(panelBackground)
        .overlay(
            LeftRoundedRectangle(radius: 10)
                .stroke(Color(white: isDark ? 0.3 : 0.75), lineWidth: 1)
        )
        .clipShape(LeftRoundedRectangle(radius: 10))
    }

    // MARK: - Output Type Section

    private var outputTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output Type")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            // Key output (default)
            InspectorButton(
                icon: "keyboard",
                title: "Send Keystroke",
                isSelected: viewModel.selectedApp == nil && viewModel.selectedSystemAction == nil && viewModel.selectedURL == nil
            ) {
                // Clear special outputs, allow normal key recording
                viewModel.selectedApp = nil
                viewModel.selectedSystemAction = nil
                viewModel.selectedURL = nil
            }

            // App launcher
            InspectorButton(
                icon: "app.badge",
                title: "Launch App",
                isSelected: viewModel.selectedApp != nil
            ) {
                viewModel.pickAppForOutput()
            }

            // URL
            InspectorButton(
                icon: "link",
                title: "Open Link",
                isSelected: viewModel.selectedURL != nil
            ) {
                viewModel.showURLInputDialog()
            }
        }
    }

    // MARK: - System Actions Section

    private var systemActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Actions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(SystemActionInfo.allActions) { action in
                    SystemActionButton(
                        action: action,
                        isSelected: viewModel.selectedSystemAction?.id == action.id
                    ) {
                        viewModel.selectSystemAction(action)
                    }
                }
            }
        }
    }

    // MARK: - Advanced Behavior Section

    private var advancedBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label on its own line
            HStack(spacing: 8) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 14))
                    .foregroundStyle(viewModel.showAdvanced ? Color.accentColor : .secondary)
                Text("Hold, Double Tap, etc.")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }

            // Toggle on its own line
            Toggle("Different actions for tap vs hold", isOn: $viewModel.showAdvanced)
                .toggleStyle(.switch)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var panelBackground: some View {
        if reduceTransparency {
            LeftRoundedRectangle(radius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        } else if #available(macOS 26.0, *) {
            LeftRoundedRectangle(radius: 10)
                .fill(.clear)
                .glassEffect(.regular, in: LeftRoundedRectangle(radius: 10))
        } else {
            LeftRoundedRectangle(radius: 10)
                .fill(Color(white: isDark ? 0.12 : 0.92))
        }
    }
}

// MARK: - Inspector Button

/// Button style for inspector panel options.
private struct InspectorButton: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, subtitle == nil ? 8 : 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.secondary.opacity(0.1) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - System Action Button

/// Compact button for system actions in the grid.
private struct SystemActionButton: View {
    let action: SystemActionInfo
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: action.sfSymbol)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)

                Text(action.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.secondary.opacity(0.1) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Reset Mapping Button

/// Toolbar button that resets current mapping on single click, shows reset all confirmation on double click.
private struct ResetMappingButton: View {
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    @State private var clickCount = 0
    @State private var clickTimer: Timer?
    private let doubleClickDelay: TimeInterval = 0.3

    var body: some View {
        Button {
            // Handle via gesture below for double-click support
        } label: {
            Image(systemName: "arrow.counterclockwise")
        }
        .help("Click: Reset mapping. Double-click: Reset all to defaults")
        .simultaneousGesture(
            TapGesture().onEnded {
                clickCount += 1

                if clickCount == 1 {
                    clickTimer = Timer.scheduledTimer(withTimeInterval: doubleClickDelay, repeats: false) { _ in
                        Task { @MainActor in
                            if clickCount == 1 {
                                onSingleClick()
                            }
                            clickCount = 0
                        }
                    }
                } else if clickCount >= 2 {
                    clickTimer?.invalidate()
                    clickTimer = nil
                    clickCount = 0
                    onDoubleClick()
                }
            }
        )
    }
}

// MARK: - Mini Action Keycap (for advanced section)

/// Smaller keycap for hold/double-tap actions in the advanced section.
private struct MiniActionKeycap: View {
    let label: String
    let isRecording: Bool
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    private let size: CGFloat = 60
    private let cornerRadius: CGFloat = 8
    private let fontSize: CGFloat = 20

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor)
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowOffset)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, lineWidth: isRecording ? 2 : 1)
                )

            if isRecording {
                Text("...")
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(foregroundColor)
            } else if label.isEmpty {
                Image(systemName: "plus")
                    .font(.system(size: fontSize * 0.7, weight: .light))
                    .foregroundStyle(foregroundColor.opacity(0.4))
            } else {
                Text(label.uppercased())
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(foregroundColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
                    isPressed = false
                }
            }
            onTap()
        }
    }

    private var foregroundColor: Color {
        Color(red: 0.88, green: 0.93, blue: 1.0)
            .opacity(isPressed ? 1.0 : 0.88)
    }

    private var backgroundColor: Color {
        if isRecording {
            Color.accentColor
        } else if isHovered {
            Color(white: 0.15)
        } else {
            Color(white: 0.08)
        }
    }

    private var borderColor: Color {
        if isRecording {
            Color.accentColor.opacity(0.8)
        } else if isHovered {
            Color.white.opacity(0.3)
        } else {
            Color.white.opacity(0.15)
        }
    }

    private var shadowColor: Color {
        Color.black.opacity(0.5)
    }

    private var shadowRadius: CGFloat {
        isPressed ? 1 : 2
    }

    private var shadowOffset: CGFloat {
        isPressed ? 1 : 2
    }
}

// MARK: - Advanced Behavior Content

/// Content showing hold and double-tap options with mini keycaps (toggle is in sidebar).
private struct AdvancedBehaviorContent: View {
    @ObservedObject var viewModel: MapperViewModel

    var body: some View {
        VStack(spacing: 20) {
            // On Hold row
            HStack(spacing: 16) {
                Text("On Hold")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .trailing)

                MiniActionKeycap(
                    label: viewModel.holdAction.isEmpty ? "" : formatKeyForDisplay(viewModel.holdAction),
                    isRecording: viewModel.isRecordingHold,
                    onTap: { viewModel.toggleHoldRecording() }
                )

                if !viewModel.holdAction.isEmpty {
                    Button {
                        viewModel.holdAction = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Clear hold action")
                }

                Spacer()
            }

            // Double Tap row
            HStack(spacing: 16) {
                Text("Double Tap")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .trailing)

                MiniActionKeycap(
                    label: viewModel.doubleTapAction.isEmpty ? "" : formatKeyForDisplay(viewModel.doubleTapAction),
                    isRecording: viewModel.isRecordingDoubleTap,
                    onTap: { viewModel.toggleDoubleTapRecording() }
                )

                if !viewModel.doubleTapAction.isEmpty {
                    Button {
                        viewModel.doubleTapAction = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Clear double tap action")
                }

                Spacer()
            }

            // Timing row
            HStack(spacing: 16) {
                Text("Timing")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .trailing)

                HStack(spacing: 8) {
                    TextField("", value: $viewModel.tappingTerm, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)

                    Text("ms")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
        .padding(.leading, 8)
    }

    private func formatKeyForDisplay(_ key: String) -> String {
        let displayMap: [String: String] = [
            "lctl": "⌃", "rctl": "⌃", "leftctrl": "⌃", "rightctrl": "⌃",
            "lalt": "⌥", "ralt": "⌥", "leftalt": "⌥", "rightalt": "⌥",
            "lsft": "⇧", "rsft": "⇧", "leftshift": "⇧", "rightshift": "⇧",
            "lmet": "⌘", "rmet": "⌘", "leftmeta": "⌘", "rightmeta": "⌘",
            "caps": "⇪", "capslock": "⇪",
            "spc": "⎵", "space": "⎵",
            "ret": "↩", "enter": "↩",
            "tab": "⇥",
            "bspc": "⌫", "backspace": "⌫",
            "esc": "⎋", "escape": "⎋",
            "left": "←", "right": "→", "up": "↑", "down": "↓",
        ]
        return displayMap[key.lowercased()] ?? key.uppercased()
    }
}

/// A rounded rectangle with only the left corners rounded.
private struct LeftRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topLeft = CGPoint(x: rect.minX, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)

        path.move(to: CGPoint(x: topLeft.x + radius, y: topLeft.y))
        path.addLine(to: topRight)
        path.addLine(to: bottomRight)
        path.addLine(to: CGPoint(x: bottomLeft.x + radius, y: bottomLeft.y))
        path.addArc(
            center: CGPoint(x: bottomLeft.x + radius, y: bottomLeft.y - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: topLeft.x, y: topLeft.y + radius))
        path.addArc(
            center: CGPoint(x: topLeft.x + radius, y: topLeft.y + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Mapper Keycap Pair

/// Responsive container that shows input/output keycaps side-by-side when they fit,
/// or stacked vertically when content is too wide.
private struct MapperKeycapPair: View {
    let inputLabel: String
    let inputKeyCode: UInt16?
    let outputLabel: String
    let isRecordingInput: Bool
    let isRecordingOutput: Bool
    var outputAppInfo: AppLaunchInfo?
    var outputSystemActionInfo: SystemActionInfo?
    var outputURLFavicon: NSImage?
    let onInputTap: () -> Void
    let onOutputTap: () -> Void

    /// Horizontal margin on each side
    private let horizontalMargin: CGFloat = 16

    /// Threshold for switching to vertical layout (character count)
    private let verticalThreshold = 15

    /// Whether to use vertical (stacked) layout
    private var shouldStack: Bool {
        // Don't stack for app icons, system actions, or URL favicons
        if outputAppInfo != nil || outputSystemActionInfo != nil || outputURLFavicon != nil { return false }
        // Don't stack when input has keyCode (fixed-size overlay-style keycap)
        if inputKeyCode != nil { return false }
        return inputLabel.count > verticalThreshold || outputLabel.count > verticalThreshold
    }

    /// Label for the output keycap
    private var outputTypeLabel: String {
        if outputAppInfo != nil { return "Launch" }
        if outputSystemActionInfo != nil { return "Action" }
        if outputURLFavicon != nil { return "URL" }
        return "Output"
    }

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let maxKeycapWidth = availableWidth - horizontalMargin * 2
            let maxKeycapWidthHorizontal = (availableWidth - horizontalMargin * 2 - 60) / 2

            Group {
                if shouldStack {
                    verticalLayout(maxWidth: maxKeycapWidth)
                } else {
                    horizontalLayout(maxWidth: maxKeycapWidthHorizontal)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func horizontalLayout(maxWidth: CGFloat) -> some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)

            // Input keycap - uses overlay-style rendering
            VStack(spacing: 8) {
                MapperInputKeycap(
                    label: inputLabel,
                    keyCode: inputKeyCode,
                    isRecording: isRecordingInput,
                    onTap: onInputTap
                )
                Text("Input")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Arrow indicator
            Image(systemName: "arrow.right")
                .font(.title3)
                .foregroundColor(.secondary)

            // Output keycap - shows result/action
            VStack(spacing: 8) {
                MapperKeycapView(
                    label: outputLabel,
                    isRecording: isRecordingOutput,
                    maxWidth: maxWidth,
                    appInfo: outputAppInfo,
                    systemActionInfo: outputSystemActionInfo,
                    urlFavicon: outputURLFavicon,
                    onTap: onOutputTap
                )
                Text(outputTypeLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func verticalLayout(maxWidth: CGFloat) -> some View {
        VStack(spacing: 8) {
            // Input keycap with label - uses overlay-style rendering
            VStack(spacing: 6) {
                Text("Input")
                    .font(.caption)
                    .foregroundColor(.secondary)

                MapperInputKeycap(
                    label: inputLabel,
                    keyCode: inputKeyCode,
                    isRecording: isRecordingInput,
                    onTap: onInputTap
                )
            }

            // Arrow indicator
            Image(systemName: "arrow.down")
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.vertical, 2)

            // Output keycap with label - shows result/action
            VStack(spacing: 6) {
                MapperKeycapView(
                    label: outputLabel,
                    isRecording: isRecordingOutput,
                    maxWidth: maxWidth,
                    appInfo: outputAppInfo,
                    systemActionInfo: outputSystemActionInfo,
                    urlFavicon: outputURLFavicon,
                    onTap: onOutputTap
                )

                Text(outputTypeLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
