import AppKit
import KeyPathCore
import SwiftUI

// MARK: - Reset Mapping Button

/// Toolbar button that resets current mapping on single click, shows reset all confirmation on double click.
struct ResetMappingButton: View {
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
        .accessibilityIdentifier("mapper-reset-button")
        .accessibilityLabel("Reset mapping")
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
struct MiniActionKeycap: View {
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
struct AdvancedBehaviorContent: View {
    @ObservedObject var viewModel: MapperViewModel

    var body: some View {
        VStack(spacing: 16) {
            // On Hold row
            VStack(alignment: .leading, spacing: 8) {
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
                            viewModel.holdBehavior = .basic
                            viewModel.customTapKeysText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .help("Clear hold action")
                        .accessibilityIdentifier("mapper-clear-hold-button")
                        .accessibilityLabel("Clear hold action")
                    }

                    Spacer()
                }

                // Hold behavior options (shown when hold action is set)
                if !viewModel.holdAction.isEmpty {
                    holdBehaviorPicker
                        .padding(.leading, 86) // Align with keycap
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
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
                    .accessibilityIdentifier("mapper-clear-double-tap-button")
                    .accessibilityLabel("Clear double tap action")
                }

                Spacer()
            }

            // Triple+ Tap rows (dynamically added)
            ForEach(Array(viewModel.tapDanceSteps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 16) {
                    Text(step.label)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .trailing)

                    MiniActionKeycap(
                        label: step.action.isEmpty ? "" : formatKeyForDisplay(step.action),
                        isRecording: step.isRecording,
                        onTap: { viewModel.toggleTapDanceRecording(at: index) }
                    )

                    if !step.action.isEmpty {
                        Button {
                            viewModel.clearTapDanceStep(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .help("Clear \(step.label.lowercased()) action")
                    }

                    // Remove button for this step
                    Button {
                        viewModel.removeTapDanceStep(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Remove \(step.label.lowercased())")

                    Spacer()
                }
            }

            // "+ Triple Tap" link (only if we can add more)
            if viewModel.tapDanceSteps.count < MapperViewModel.tapDanceLabels.count {
                HStack(spacing: 16) {
                    Text("")
                        .frame(width: 70)

                    Button {
                        viewModel.addTapDanceStep()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.caption)
                            Text(nextTapDanceLabel)
                                .font(.subheadline)
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Add \(nextTapDanceLabel.lowercased())")
                    .accessibilityIdentifier("mapper-add-tap-dance-button")
                    .accessibilityLabel("Add \(nextTapDanceLabel.lowercased())")

                    Spacer()
                }
            }

            // Timing row
            HStack(spacing: 16) {
                Text("Timing")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .trailing)

                if viewModel.showTimingAdvanced {
                    // Separate timing fields
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tap")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                TextField("", value: $viewModel.tapTimeout, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hold")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                TextField("", value: $viewModel.holdTimeout, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                            }
                            Text("ms")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    // Single timing value
                    HStack(spacing: 8) {
                        TextField("", value: $viewModel.tappingTerm, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)

                        Text("ms")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                // Gear icon to toggle advanced timing
                Button {
                    viewModel.showTimingAdvanced.toggle()
                    if viewModel.showTimingAdvanced {
                        // Initialize separate values from single
                        viewModel.tapTimeout = viewModel.tappingTerm
                        viewModel.holdTimeout = viewModel.tappingTerm
                    } else {
                        // Sync single value from tap timeout
                        viewModel.tappingTerm = viewModel.tapTimeout
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.subheadline)
                        .foregroundColor(viewModel.showTimingAdvanced ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(viewModel.showTimingAdvanced ? "Use single timing" : "Separate tap/hold timing")
                .accessibilityIdentifier("mapper-timing-advanced-button")
                .accessibilityLabel("Toggle advanced timing")

                Spacer()
            }
        }
        .padding(.leading, 8)
        .animation(.easeInOut(duration: 0.2), value: viewModel.holdAction.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: viewModel.tapDanceSteps.count)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showTimingAdvanced)
    }

    // MARK: - Hold Behavior Picker

    private var holdBehaviorPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MapperViewModel.HoldBehaviorType.allCases, id: \.self) { behaviorType in
                HStack(spacing: 10) {
                    Button {
                        viewModel.holdBehavior = behaviorType
                    } label: {
                        Image(systemName: viewModel.holdBehavior == behaviorType ? "checkmark.circle.fill" : "circle")
                            .font(.body)
                            .foregroundColor(viewModel.holdBehavior == behaviorType ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(behaviorType.rawValue)
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        if viewModel.holdBehavior == behaviorType {
                            Text(behaviorType.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityIdentifier("mapper-hold-behavior-\(behaviorType.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))")
                .accessibilityLabel(behaviorType.rawValue)

                // Custom keys input (shown when Custom keys is selected)
                if behaviorType == .customKeys, viewModel.holdBehavior == .customKeys {
                    TextField("e.g., a s d f", text: $viewModel.customTapKeysText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .font(.subheadline)
                        .padding(.leading, 26)
                        .accessibilityIdentifier("mapper-custom-tap-keys-field")
                        .accessibilityLabel("Custom tap keys")
                }
            }
        }
    }

    // MARK: - Helpers

    private var nextTapDanceLabel: String {
        let index = viewModel.tapDanceSteps.count
        guard index < MapperViewModel.tapDanceLabels.count else { return "More Taps" }
        return MapperViewModel.tapDanceLabels[index]
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
            "left": "←", "right": "→", "up": "↑", "down": "↓"
        ]
        return displayMap[key.lowercased()] ?? key.uppercased()
    }
}

// MARK: - Mapper Conflict Dialog

struct MapperConflictDialog: View {
    let onKeepHold: () -> Void
    let onKeepTapDance: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("Behavior Conflict")
                .font(.headline)

            Text("Kanata cannot detect both hold and tap-count on the same key. You must choose one behavior.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Keep Hold") {
                    onKeepHold()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("mapper-conflict-keep-hold")

                Button("Keep Tap-Dance") {
                    onKeepTapDance()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("mapper-conflict-keep-tap-dance")

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("mapper-conflict-cancel")
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

/// A rounded rectangle with only the left corners rounded.
struct LeftRoundedRectangle: Shape {
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
struct MapperKeycapPair: View {
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

    /// When true, remove outer centering/margins so the pair can sit flush to a leading edge.
    /// Used by the overlay drawer, where the input keycap should align to the drawer edge.
    var compactNoSidePadding: Bool = false

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
        return "Out"
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
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: compactNoSidePadding ? .leading : .center
            )
        }
    }

    private func horizontalLayout(maxWidth: CGFloat) -> some View {
        HStack(spacing: 16) {
            if !compactNoSidePadding {
                Spacer(minLength: 0)
            }

            // Input keycap - uses overlay-style rendering
            VStack(spacing: 8) {
                MapperInputKeycap(
                    label: inputLabel,
                    keyCode: inputKeyCode,
                    isRecording: isRecordingInput,
                    onTap: onInputTap
                )
                Text("In")
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

            if !compactNoSidePadding {
                Spacer(minLength: 0)
            }
        }
    }

    private func verticalLayout(maxWidth: CGFloat) -> some View {
        VStack(spacing: 8) {
            // Input keycap with label - uses overlay-style rendering
            VStack(spacing: 6) {
                Text("In")
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

// MARK: - Layer Switcher Button

/// Button that shows current layer and opens a menu to switch layers
struct LayerSwitcherButton: View {
    let currentLayer: String
    let onSelectLayer: (String) -> Void
    let onCreateLayer: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var displayName: String {
        currentLayer.lowercased() == "base" ? "Base Layer" : currentLayer.capitalized
    }

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Menu {
            // Available layers
            ForEach(["base", "nav"], id: \.self) { layer in
                Button {
                    onSelectLayer(layer)
                } label: {
                    HStack {
                        Text(layer.lowercased() == "base" ? "Base Layer" : layer.capitalized)
                        Spacer()
                        if currentLayer.lowercased() == layer.lowercased() {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            // Create new layer
            Button {
                onCreateLayer()
            } label: {
                Label("New Layer...", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text(displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.secondary.opacity(0.15) : Color.clear)
            )
        }
        .menuStyle(.borderlessButton)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("mapper-layer-switcher")
        .accessibilityLabel("Current layer: \(displayName). Click to change layer.")
    }
}

// MARK: - New Layer Sheet

/// Sheet for creating a new layer
struct NewLayerSheet: View {
    @Binding var layerName: String
    let existingLayers: [String]
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var isNameFocused: Bool

    private var isValidName: Bool {
        let sanitized = layerName.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }

        return !sanitized.isEmpty && !existingLayers.contains { $0.lowercased() == sanitized }
    }

    private var validationMessage: String? {
        guard !layerName.isEmpty else { return nil }

        let sanitized = layerName.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }

        if sanitized.isEmpty {
            return "Name must contain letters or numbers"
        }

        if existingLayers.contains(where: { $0.lowercased() == sanitized }) {
            return "A layer with this name already exists"
        }

        return nil
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Create New Layer")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Layer name", text: $layerName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit {
                        if isValidName {
                            onSubmit(layerName)
                        }
                    }
                    .accessibilityIdentifier("new-layer-name-field")

                if let message = validationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("new-layer-cancel-button")

                Button("Create") {
                    onSubmit(layerName)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidName)
                .accessibilityIdentifier("new-layer-create-button")
            }
        }
        .padding(24)
        .frame(width: 300)
        .onAppear {
            isNameFocused = true
        }
    }
}

// MARK: - URL Input Dialog

/// Dialog for entering a web URL to map to a key
struct URLInputDialog: View {
    @Binding var urlText: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Enter Web URL")
                .font(.headline)

            TextField("example.com or https://...", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit { onSubmit() }
                .accessibilityIdentifier("mapper-url-input-field")
                .accessibilityLabel("URL input")

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                .accessibilityIdentifier("mapper-dialog-cancel-button")
                .accessibilityLabel("Cancel")

                Button("OK") {
                    onSubmit()
                }
                .keyboardShortcut(.return)
                .accessibilityIdentifier("mapper-dialog-ok-button")
                .accessibilityLabel("OK")
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
