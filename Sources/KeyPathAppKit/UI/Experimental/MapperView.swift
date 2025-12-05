import AppKit
import KeyPathCore
import SwiftUI

// MARK: - Notification for preset values

extension Notification.Name {
    /// Posted when Mapper should apply preset values (from overlay click)
    static let mapperPresetValues = Notification.Name("KeyPath.MapperPresetValues")
}

// MARK: - Reset Button with Double-Click Support

/// A button that handles single click (reset current) and double click (reset all).
/// Uses a timer to distinguish between single and double clicks.
private struct ResetButton: View {
    let isEnabled: Bool
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    @State private var clickCount = 0
    @State private var clickTimer: Timer?

    private let doubleClickDelay: TimeInterval = 0.3

    var body: some View {
        Label("Reset", systemImage: "arrow.counterclockwise")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
            )
            .opacity(isEnabled ? 1.0 : 0.3)
            .contentShape(Rectangle())
            .onTapGesture {
                guard isEnabled else { return }
                clickCount += 1

                if clickCount == 1 {
                    // Start timer to wait for potential second click
                    clickTimer = Timer.scheduledTimer(withTimeInterval: doubleClickDelay, repeats: false) { _ in
                        Task { @MainActor in
                            if clickCount == 1 {
                                onSingleClick()
                            }
                            clickCount = 0
                        }
                    }
                } else if clickCount >= 2 {
                    // Double click detected
                    clickTimer?.invalidate()
                    clickTimer = nil
                    clickCount = 0
                    onDoubleClick()
                }
            }
            .help("Click: Reset mapping. Double-click: Reset all to defaults")
    }
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

    /// Error alert state
    @State private var showingErrorAlert = false
    @State private var errorAlertMessage = ""

    /// Reset all confirmation dialog
    @State private var showingResetAllConfirmation = false

    var body: some View {
        VStack(spacing: 12) {
            // Compact toolbar with layer and clear
            HStack(spacing: 8) {
                // Layer indicator (compact)
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.currentLayer.lowercased() == "base" ? Color.secondary.opacity(0.4) : Color.accentColor)
                        .frame(width: 6, height: 6)
                    Text(viewModel.currentLayer.lowercased())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Status message (centered area)
                if let message = viewModel.statusMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(viewModel.statusIsError ? .red : Color.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // System action picker menu
                Menu {
                    ForEach(SystemActionInfo.allActions) { action in
                        Button {
                            viewModel.selectSystemAction(action)
                        } label: {
                            Label(action.name, systemImage: action.sfSymbol)
                        }
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .help("System action")

                // App launcher picker button
                Button {
                    viewModel.pickAppForOutput()
                } label: {
                    Image(systemName: "app.badge")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Pick app to launch")

                // Clear/reset button
                // Single click: reset current mapping
                // Double click: reset entire keyboard to defaults
                ResetButton(
                    isEnabled: viewModel.canSave || viewModel.inputLabel != "a" || viewModel.outputLabel != "a",
                    onSingleClick: { viewModel.clear() },
                    onDoubleClick: { showingResetAllConfirmation = true }
                )
            }
            .padding(.horizontal, 4)

            // Keycaps for input and output
            MapperKeycapPair(
                inputLabel: viewModel.inputLabel,
                inputKeyCode: viewModel.inputKeyCode,
                outputLabel: viewModel.outputLabel,
                isRecordingInput: viewModel.isRecordingInput,
                isRecordingOutput: viewModel.isRecordingOutput,
                outputAppInfo: viewModel.selectedApp,
                outputSystemActionInfo: viewModel.selectedSystemAction,
                onInputTap: { viewModel.toggleInputRecording() },
                onOutputTap: { viewModel.toggleOutputRecording() }
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(minWidth: 340, alignment: .top)
        .animation(.easeInOut(duration: 0.25), value: viewModel.canSave)
        .animation(.easeInOut(duration: 0.25), value: viewModel.statusMessage)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.inputLabel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.outputLabel)
        .onAppear {
            viewModel.configure(kanataManager: kanataManager.underlyingManager)
            // Apply preset values if provided
            if let presetInput, let presetOutput {
                viewModel.applyPresets(input: presetInput, output: presetOutput, layer: presetLayer)
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
               let output = notification.userInfo?["output"] as? String {
                let layer = notification.userInfo?["layer"] as? String
                viewModel.applyPresets(input: input, output: output, layer: layer)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kanataLayerChanged)) { notification in
            // Update layer when it changes (if not opened from overlay with specific layer)
            if let layerName = notification.userInfo?["layerName"] as? String,
               viewModel.originalInputKey == nil { // Only auto-update if not opened from overlay
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
    let onInputTap: () -> Void
    let onOutputTap: () -> Void

    /// Horizontal margin on each side
    private let horizontalMargin: CGFloat = 16

    /// Threshold for switching to vertical layout (character count)
    private let verticalThreshold = 15

    /// Whether to use vertical (stacked) layout
    private var shouldStack: Bool {
        // Don't stack for app icons or system actions
        if outputAppInfo != nil || outputSystemActionInfo != nil { return false }
        // Don't stack when input has keyCode (fixed-size overlay-style keycap)
        if inputKeyCode != nil { return false }
        return inputLabel.count > verticalThreshold || outputLabel.count > verticalThreshold
    }

    /// Label for the output keycap
    private var outputTypeLabel: String {
        if outputAppInfo != nil { return "Launch" }
        if outputSystemActionInfo != nil { return "Action" }
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
                    .foregroundStyle(.secondary)
            }

            // Arrow indicator
            Image(systemName: "arrow.right")
                .font(.title3)
                .foregroundStyle(.secondary)

            // Output keycap - shows result/action
            VStack(spacing: 8) {
                MapperKeycapView(
                    label: outputLabel,
                    isRecording: isRecordingOutput,
                    maxWidth: maxWidth,
                    appInfo: outputAppInfo,
                    systemActionInfo: outputSystemActionInfo,
                    onTap: onOutputTap
                )
                Text(outputTypeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)

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
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)

            // Output keycap with label - shows result/action
            VStack(spacing: 6) {
                MapperKeycapView(
                    label: outputLabel,
                    isRecording: isRecordingOutput,
                    maxWidth: maxWidth,
                    appInfo: outputAppInfo,
                    systemActionInfo: outputSystemActionInfo,
                    onTap: onOutputTap
                )

                Text(outputTypeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Mapper Keycap View

/// Large (2x scale) keycap styled like the overlay keyboard.
/// Click to start/stop recording key input. Width grows to fit content up to maxWidth,
/// then text wraps to multiple lines up to maxHeight, then text shrinks to fit.
/// Can also display an app icon + name for launch actions, or SF Symbol for system actions.
struct MapperKeycapView: View {
    let label: String
    let isRecording: Bool
    var maxWidth: CGFloat = .infinity
    var appInfo: AppLaunchInfo?
    var systemActionInfo: SystemActionInfo?
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    // Sizing constants
    private let baseHeight: CGFloat = 100 // Base keycap height (single line)
    private let maxHeightMultiplier: CGFloat = 1.5 // Max height is 1.5x base (150pt)
    private let minWidth: CGFloat = 100 // Minimum width
    private let horizontalPadding: CGFloat = 20 // Padding for text
    private let verticalPadding: CGFloat = 14 // Padding top/bottom
    private let baseFontSize: CGFloat = 36 // Base font size for text
    private let outputFontSize: CGFloat = 42 // Emphasized size for output content (icons, letters, actions)
    private let minFontSize: CGFloat = 12 // Minimum font size when shrinking
    private let cornerRadius: CGFloat = 16

    /// Maximum height for the keycap
    private var maxHeight: CGFloat {
        baseHeight * maxHeightMultiplier
    }

    /// Calculate the actual width of the keycap
    private var keycapWidth: CGFloat {
        let charWidth: CGFloat = dynamicFontSize * 0.6
        let contentWidth = CGFloat(label.count) * charWidth + horizontalPadding * 2
        let naturalWidth = max(minWidth, contentWidth)
        return min(naturalWidth, maxWidth)
    }

    /// Calculate font size - shrinks if content won't fit in max height (for input keycaps)
    private var dynamicFontSize: CGFloat {
        dynamicFontSizeFor(baseFontSize)
    }

    /// Calculate output font size - shrinks if content won't fit (for output keycaps)
    private var dynamicOutputFontSize: CGFloat {
        dynamicFontSizeFor(outputFontSize)
    }

    /// Calculate dynamic font size based on a given base size
    private func dynamicFontSizeFor(_ baseSize: CGFloat) -> CGFloat {
        guard maxWidth < .infinity else { return baseSize }

        // Calculate how many lines we'd need at base font size
        let availableTextWidth = maxWidth - horizontalPadding * 2
        let charWidth: CGFloat = baseSize * 0.6
        let contentWidth = CGFloat(label.count) * charWidth
        let linesNeeded = ceil(contentWidth / availableTextWidth)

        // Calculate height needed at base font size
        let lineHeight: CGFloat = baseSize * 1.3
        let heightNeeded = linesNeeded * lineHeight + verticalPadding * 2

        // If it fits in max height, use base font size
        if heightNeeded <= maxHeight {
            return baseSize
        }

        // Otherwise, calculate what font size would fit
        // We need to fit the same content in maxHeight
        let availableTextHeight = maxHeight - verticalPadding * 2
        // Estimate: shrink proportionally
        let scaleFactor = availableTextHeight / (linesNeeded * lineHeight)
        let newFontSize = baseSize * scaleFactor

        return max(minFontSize, newFontSize)
    }

    /// Calculate height based on content and font size, capped at max
    private var keycapHeight: CGFloat {
        guard maxWidth < .infinity else { return baseHeight }

        let availableTextWidth = maxWidth - horizontalPadding * 2
        let charWidth: CGFloat = dynamicFontSize * 0.6
        let contentWidth = CGFloat(label.count) * charWidth
        let linesNeeded = max(1, ceil(contentWidth / availableTextWidth))

        let lineHeight: CGFloat = dynamicFontSize * 1.3
        let naturalHeight = linesNeeded * lineHeight + verticalPadding * 2

        return min(max(baseHeight, naturalHeight), maxHeight)
    }

    var body: some View {
        ZStack {
            // Key background - grows with content up to max height
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor)
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowOffset)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, lineWidth: isRecording ? 2 : 1)
                )

            // Content: app icon + name, system action SF Symbol, or key label
            // All output types use outputFontSize for consistent emphasis
            if let app = appInfo {
                // App launch mode: show icon + name
                VStack(spacing: 6) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: outputFontSize * 1.3, height: outputFontSize * 1.3) // Scale with outputFontSize
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)

                    Text(app.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(foregroundColor)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else if let systemAction = systemActionInfo {
                // System action mode: show SF Symbol
                Image(systemName: systemAction.sfSymbol)
                    .font(.system(size: outputFontSize, weight: .medium))
                    .foregroundStyle(foregroundColor)
            } else {
                // Key label - wraps to multiple lines, shrinks if needed
                Text(label)
                    .font(.system(size: dynamicOutputFontSize, weight: .medium))
                    .foregroundStyle(foregroundColor)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .minimumScaleFactor(minFontSize / outputFontSize)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding / 2)
            }
        }
        .frame(width: appInfo != nil ? 120 : keycapWidth, height: appInfo != nil ? 100 : keycapHeight)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: keycapHeight)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: dynamicFontSize)
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
        .accessibilityLabel(isRecording ? "Recording \(label)" : label)
        .accessibilityHint("Click to \(isRecording ? "stop" : "start") recording")
    }

    // MARK: - Styling (matching OverlayKeycapView dark style)

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

// MARK: - Mapper Input Keycap (Overlay Style)

/// Input keycap styled like the overlay keyboard - shows physical key appearance
/// with function key icons, shift symbols, globe+fn, etc.
struct MapperInputKeycap: View {
    let label: String
    let keyCode: UInt16?
    let isRecording: Bool
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    // Scale factor (overlay uses 1.0, mapper uses 2.5x)
    private let scale: CGFloat = 2.5

    // Sizing
    private let baseSize: CGFloat = 100
    private let cornerRadius: CGFloat = 10

    /// Determine layout role from keyCode directly
    private var layoutRole: KeycapLayoutRole {
        guard let keyCode else { return .centered }

        // Function keys: F1-F12 (keyCodes 122,120,99,118,96,97,98,100,101,109,103,111)
        let functionKeyCodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        if functionKeyCodes.contains(keyCode) {
            return .functionKey
        }

        // ESC key (keyCode 53)
        if keyCode == 53 {
            return .escKey
        }

        // Arrow keys (keyCodes 123,124,125,126)
        let arrowKeyCodes: Set<UInt16> = [123, 124, 125, 126]
        if arrowKeyCodes.contains(keyCode) {
            return .arrow
        }

        // fn key (keyCode 63)
        if keyCode == 63 {
            return .narrowModifier
        }

        // Control/Option/Command (keyCodes 59,58,55,62,61,54)
        let narrowModKeyCodes: Set<UInt16> = [59, 58, 55, 62, 61, 54]
        if narrowModKeyCodes.contains(keyCode) {
            return .narrowModifier
        }

        // Shift keys (keyCodes 56, 60)
        let shiftKeyCodes: Set<UInt16> = [56, 60]
        if shiftKeyCodes.contains(keyCode) {
            return .bottomAligned
        }

        // Return/Delete/Tab/CapsLock - wide modifiers
        let wideModKeyCodes: Set<UInt16> = [36, 51, 48, 57] // return, delete, tab, caps
        if wideModKeyCodes.contains(keyCode) {
            return .bottomAligned
        }

        // Default: centered
        return .centered
    }

    private var labelMetadata: LabelMetadata {
        LabelMetadata.forLabel(label)
    }

    var body: some View {
        ZStack {
            // Key background
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor)
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowOffset)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, lineWidth: isRecording ? 2 : 1)
                )

            // Content based on layout role
            keyContent
        }
        .frame(width: baseSize, height: baseSize)
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

    // MARK: - Content Routing

    @ViewBuilder
    private var keyContent: some View {
        switch layoutRole {
        case .functionKey:
            functionKeyContent
        case .narrowModifier:
            narrowModifierContent
        case .escKey:
            escKeyContent
        case .bottomAligned:
            bottomAlignedContent
        case .arrow:
            arrowContent
        case .centered, .touchId:
            centeredContent
        }
    }

    // MARK: - Layout: Function Key (icon + label)

    @ViewBuilder
    private var functionKeyContent: some View {
        let sfSymbol = keyCode.flatMap { LabelMetadata.sfSymbol(forKeyCode: $0) }

        VStack(spacing: 4) {
            if let symbol = sfSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(foregroundColor)
            }
            Spacer()
            Text(label.uppercased())
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(foregroundColor.opacity(0.6))
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Layout: Narrow Modifier (fn with globe)

    @ViewBuilder
    private var narrowModifierContent: some View {
        if label.lowercased() == "fn" {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 20, weight: .regular))
                Text("fn")
                    .font(.system(size: 16, weight: .regular))
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Other narrow modifiers (ctrl, opt, cmd)
            Text(label)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Layout: ESC Key (left-aligned + LED)

    @ViewBuilder
    private var escKeyContent: some View {
        VStack {
            // LED indicator (top-left)
            HStack {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 8, height: 8)
                Spacer()
            }
            .padding(.leading, 12)
            .padding(.top, 10)

            Spacer()

            // Bottom-left aligned text
            HStack {
                Text("esc")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(foregroundColor)
                Spacer()
            }
            .padding(.leading, 12)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Layout: Bottom Aligned (wide modifiers)

    @ViewBuilder
    private var bottomAlignedContent: some View {
        let wordLabel = labelMetadata.wordLabel ?? label

        VStack {
            Spacer()
            HStack {
                Text(wordLabel.lowercased())
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(foregroundColor)
                Spacer()
            }
            .padding(.leading, 12)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Layout: Arrow

    @ViewBuilder
    private var arrowContent: some View {
        Text(label)
            .font(.system(size: 24, weight: .regular))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Layout: Centered (with optional shift symbol)

    @ViewBuilder
    private var centeredContent: some View {
        if let shiftSymbol = labelMetadata.shiftSymbol {
            // Dual symbol: shift above, main below
            VStack(spacing: 6) {
                Text(shiftSymbol)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(foregroundColor.opacity(0.6))
                Text(label.uppercased())
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(foregroundColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Single centered content
            Text(label.uppercased())
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Styling

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

// MARK: - Mapper View Model

/// Info about a selected app for launch action
struct AppLaunchInfo: Equatable {
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage

    /// The kanata output string for this app launch
    var kanataOutput: String {
        // Use bundle identifier if available, otherwise app name
        let appId = bundleIdentifier ?? name
        return "(push-msg \"launch:\(appId)\")"
    }
}

/// Info about a selected system action or media key
struct SystemActionInfo: Equatable, Identifiable {
    let id: String // The action identifier (e.g., "dnd", "spotlight", "pp" for play/pause)
    let name: String // Human-readable name
    let sfSymbol: String // SF Symbol icon name
    /// If non-nil, this is a direct keycode output (e.g., "pp", "prev", "next")
    /// If nil, this is a push-msg system action
    let kanataKeycode: String?
    /// Canonical name returned by kanata simulator (e.g., "MediaTrackPrevious", "MediaPlayPause")
    let simulatorName: String?

    init(id: String, name: String, sfSymbol: String, kanataKeycode: String? = nil, simulatorName: String? = nil) {
        self.id = id
        self.name = name
        self.sfSymbol = sfSymbol
        self.kanataKeycode = kanataKeycode
        self.simulatorName = simulatorName
    }

    /// The kanata output string for this action
    var kanataOutput: String {
        if let keycode = kanataKeycode {
            return keycode
        }
        return "(push-msg \"system:\(id)\")"
    }

    /// Whether this is a media key (direct keycode) vs push-msg action
    var isMediaKey: Bool {
        kanataKeycode != nil
    }

    /// All available system actions and media keys
    /// SF Symbols match macOS function key icons (non-filled variants)
    static let allActions: [SystemActionInfo] = [
        // Push-msg system actions
        SystemActionInfo(id: "spotlight", name: "Spotlight", sfSymbol: "magnifyingglass"),
        SystemActionInfo(id: "mission-control", name: "Mission Control", sfSymbol: "rectangle.3.group"),
        SystemActionInfo(id: "launchpad", name: "Launchpad", sfSymbol: "square.grid.3x3"),
        SystemActionInfo(id: "dnd", name: "Do Not Disturb", sfSymbol: "moon"),
        SystemActionInfo(id: "notification-center", name: "Notification Center", sfSymbol: "bell"),
        SystemActionInfo(id: "dictation", name: "Dictation", sfSymbol: "mic"),
        SystemActionInfo(id: "siri", name: "Siri", sfSymbol: "waveform.circle"),
        // Media keys (direct keycodes)
        // simulatorName is the canonical name returned by kanata simulator (from keyberon KeyCode enum)
        SystemActionInfo(id: "play-pause", name: "Play/Pause", sfSymbol: "playpause", kanataKeycode: "pp", simulatorName: "MediaPlayPause"),
        SystemActionInfo(id: "next-track", name: "Next Track", sfSymbol: "forward", kanataKeycode: "next", simulatorName: "MediaNextSong"),
        SystemActionInfo(id: "prev-track", name: "Previous Track", sfSymbol: "backward", kanataKeycode: "prev", simulatorName: "MediaPreviousSong"),
        SystemActionInfo(id: "mute", name: "Mute", sfSymbol: "speaker.slash", kanataKeycode: "mute", simulatorName: "Mute"),
        SystemActionInfo(id: "volume-up", name: "Volume Up", sfSymbol: "speaker.wave.3", kanataKeycode: "volu", simulatorName: "VolUp"),
        SystemActionInfo(id: "volume-down", name: "Volume Down", sfSymbol: "speaker.wave.1", kanataKeycode: "voldwn", simulatorName: "VolDown"),
        SystemActionInfo(id: "brightness-up", name: "Brightness Up", sfSymbol: "sun.max", kanataKeycode: "brup", simulatorName: "BrightnessUp"),
        SystemActionInfo(id: "brightness-down", name: "Brightness Down", sfSymbol: "sun.min", kanataKeycode: "brdown", simulatorName: "BrightnessDown")
    ]

    /// Look up a SystemActionInfo by its kanata output (keycode, display name, or simulator name)
    static func find(byOutput output: String) -> SystemActionInfo? {
        // Check by name first (for display labels from overlay)
        if let action = allActions.first(where: { $0.name == output }) {
            return action
        }
        // Check by kanata keycode (for direct key outputs like "pp", "next")
        if let action = allActions.first(where: { $0.kanataKeycode == output }) {
            return action
        }
        // Check by simulator canonical name (e.g., "MediaTrackPrevious", "MediaPlayPause")
        if let action = allActions.first(where: { $0.simulatorName == output }) {
            return action
        }
        return nil
    }
}

@MainActor
class MapperViewModel: ObservableObject {
    @Published var inputLabel: String = "a"
    @Published var outputLabel: String = "a"
    @Published var isRecordingInput = false
    @Published var isRecordingOutput = false
    @Published var isSaving = false
    @Published var statusMessage: String?
    @Published var statusIsError = false
    @Published var currentLayer: String = "base"
    /// Selected app for launch action (nil = normal key output)
    @Published var selectedApp: AppLaunchInfo?
    /// Selected system action (nil = normal key output)
    @Published var selectedSystemAction: SystemActionInfo?
    /// Key code of the captured input (for overlay-style rendering)
    @Published var inputKeyCode: UInt16?

    private var inputSequence: KeySequence?
    private var outputSequence: KeySequence?
    private var keyboardCapture: KeyboardCapture?
    private var kanataManager: RuntimeCoordinator?
    private var finalizeTimer: Timer?
    /// ID of the last saved custom rule (for clearing/deleting)
    private var lastSavedRuleID: UUID?
    /// Original key context from overlay click (for reset after clear)
    var originalInputKey: String?
    private var originalOutputKey: String?
    /// Original layer from overlay click
    private var originalLayer: String?

    /// State saved before starting output recording (for restore on cancel)
    private var savedOutputLabel: String?
    private var savedOutputSequence: KeySequence?
    private var savedSelectedApp: AppLaunchInfo?
    private var savedSelectedSystemAction: SystemActionInfo?

    /// Delay before finalizing a sequence capture (allows for multi-key sequences)
    private let sequenceFinalizeDelay: TimeInterval = 0.8

    var canSave: Bool {
        inputSequence != nil && (outputSequence != nil || selectedApp != nil || selectedSystemAction != nil)
    }

    func configure(kanataManager: RuntimeCoordinator) {
        self.kanataManager = kanataManager
    }

    /// Set the current layer
    func setLayer(_ layer: String) {
        currentLayer = layer
        AppLogger.shared.log("🗂️ [MapperViewModel] Layer set to: \(layer)")
    }

    /// Apply preset values from overlay click
    func applyPresets(input: String, output: String, layer: String? = nil) {
        // Stop any active recording
        stopRecording()

        // Store original context for reset after clear
        originalInputKey = input
        originalOutputKey = output
        originalLayer = layer

        // Clear any previously saved rule ID since we're starting fresh
        lastSavedRuleID = nil
        selectedApp = nil
        selectedSystemAction = nil

        // Set the layer
        if let layer {
            currentLayer = layer
        }

        // Set the input label and sequence
        inputLabel = formatKeyForDisplay(input)
        inputSequence = KeySequence(
            keys: [KeyPress(baseKey: input, modifiers: [], keyCode: 0)],
            captureMode: .single
        )

        // Check if output is a system action or media key
        if let systemAction = SystemActionInfo.find(byOutput: output) {
            // It's a system action/media key - set selectedSystemAction for SF Symbol rendering
            selectedSystemAction = systemAction
            outputLabel = systemAction.name
            outputSequence = nil
            AppLogger.shared.log("🗺️ [MapperViewModel] Preset output is system action: \(systemAction.name)")
        } else {
            // Regular key mapping
            outputLabel = formatKeyForDisplay(output)
            outputSequence = KeySequence(
                keys: [KeyPress(baseKey: output, modifiers: [], keyCode: 0)],
                captureMode: .single
            )
        }

        statusMessage = nil
        statusIsError = false

        AppLogger.shared.log("📝 [MapperViewModel] Applied presets: \(input) → \(output) [layer: \(currentLayer)]")
    }

    /// Format a kanata key name for display (e.g., "leftmeta" -> "⌘")
    private func formatKeyForDisplay(_ key: String) -> String {
        let displayMap: [String: String] = [
            "leftmeta": "⌘",
            "rightmeta": "⌘",
            "leftalt": "⌥",
            "rightalt": "⌥",
            "leftshift": "⇧",
            "rightshift": "⇧",
            "leftctrl": "⌃",
            "rightctrl": "⌃",
            "capslock": "⇪",
            "space": "␣",
            "enter": "↩",
            "tab": "⇥",
            "backspace": "⌫",
            "esc": "⎋",
            "left": "←",
            "right": "→",
            "up": "↑",
            "down": "↓"
        ]
        return displayMap[key.lowercased()] ?? key.uppercased()
    }

    func toggleInputRecording() {
        if isRecordingInput {
            stopRecording()
        } else {
            // Stop output recording if active
            if isRecordingOutput {
                stopRecording()
            }
            startInputRecording()
        }
    }

    func toggleOutputRecording() {
        if isRecordingOutput {
            stopRecording()
        } else {
            // Stop input recording if active
            if isRecordingInput {
                stopRecording()
            }
            startOutputRecording()
        }
    }

    private func startInputRecording() {
        isRecordingInput = true
        inputSequence = nil
        inputKeyCode = nil
        inputLabel = "..."
        statusMessage = "Press keys (sequence supported)"
        statusIsError = false
        startCapture(isInput: true)
    }

    private func startOutputRecording() {
        // Save current output state before recording (for restore on cancel)
        savedOutputLabel = outputLabel
        savedOutputSequence = outputSequence
        savedSelectedApp = selectedApp
        savedSelectedSystemAction = selectedSystemAction

        isRecordingOutput = true
        outputSequence = nil
        outputLabel = "..."
        // Clear system action/app so keycap shows recording state
        selectedSystemAction = nil
        selectedApp = nil
        statusMessage = "Press keys (sequence supported)"
        statusIsError = false
        startCapture(isInput: false)
    }

    private func startCapture(isInput: Bool) {
        // Create keyboard capture if needed
        if keyboardCapture == nil {
            keyboardCapture = KeyboardCapture()
        }

        guard let capture = keyboardCapture else {
            AppLogger.shared.error("❌ [MapperViewModel] Failed to create KeyboardCapture")
            stopRecording()
            return
        }

        // Use sequence mode for multi-key support
        capture.startSequenceCapture(mode: .sequence) { [weak self] sequence in
            guard let self else { return }

            Task { @MainActor in
                // Update the captured sequence (streaming updates)
                if isInput {
                    self.inputSequence = sequence
                    self.inputLabel = sequence.displayString
                    // Store first key's keyCode for overlay-style rendering
                    if let firstKey = sequence.keys.first {
                        let keyCode = UInt16(firstKey.keyCode)
                        self.inputKeyCode = keyCode

                        // Look up current mapping for this key and update output
                        self.lookupAndSetOutput(forKeyCode: keyCode)
                    }
                } else {
                    self.outputSequence = sequence
                    self.outputLabel = sequence.displayString
                }

                // Reset finalize timer - wait for more keys
                self.finalizeTimer?.invalidate()
                self.finalizeTimer = Timer.scheduledTimer(
                    withTimeInterval: self.sequenceFinalizeDelay,
                    repeats: false
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.finalizeCapture()
                    }
                }
            }
        }
    }

    /// Look up the current output for a key code from the overlay's layer map
    private func lookupAndSetOutput(forKeyCode keyCode: UInt16) {
        // Clear any selected app/system action since we're switching keys
        selectedApp = nil
        selectedSystemAction = nil

        // Look up the current mapping from the overlay controller
        if let mapping = LiveKeyboardOverlayController.shared.lookupCurrentMapping(forKeyCode: keyCode) {
            // Check if this is a system action or media key
            if let systemAction = SystemActionInfo.find(byOutput: mapping.output) {
                // It's a system action/media key - set selectedSystemAction for SF Symbol rendering
                selectedSystemAction = systemAction
                outputLabel = systemAction.name
                outputSequence = nil
                AppLogger.shared.log("🔍 [MapperViewModel] Key \(keyCode) is system action: \(systemAction.name)")
            } else {
                // Regular key mapping
                outputLabel = formatKeyForDisplay(mapping.output)
                outputSequence = KeySequence(
                    keys: [KeyPress(baseKey: mapping.output, modifiers: [], keyCode: 0)],
                    captureMode: .single
                )
            }

            // Store original context for reset
            originalInputKey = mapping.inputKey
            originalOutputKey = mapping.output
            originalLayer = LiveKeyboardOverlayController.shared.currentLayerName
            currentLayer = originalLayer ?? "base"

            AppLogger.shared.log("🔍 [MapperViewModel] Key \(keyCode) maps to: \(mapping.output) in layer \(currentLayer)")
        } else {
            // No mapping found - default to key maps to itself
            let inputKey = OverlayKeyboardView.keyCodeToKanataName(keyCode)
            outputLabel = formatKeyForDisplay(inputKey)
            outputSequence = KeySequence(
                keys: [KeyPress(baseKey: inputKey, modifiers: [], keyCode: 0)],
                captureMode: .single
            )
            originalInputKey = inputKey
            originalOutputKey = inputKey
        }
    }

    private func finalizeCapture() {
        finalizeTimer?.invalidate()
        finalizeTimer = nil

        // Stop recording but keep the captured sequence
        keyboardCapture?.stopCapture()
        isRecordingInput = false
        isRecordingOutput = false
        statusMessage = nil

        AppLogger.shared.log("🎯 [MapperViewModel] finalizeCapture: canSave=\(canSave) selectedApp=\(selectedApp?.name ?? "nil") inputSeq=\(inputSequence?.displayString ?? "nil")")

        // Auto-save when input is captured and we have either output or app
        if canSave, let manager = kanataManager {
            Task {
                if selectedApp != nil {
                    // App launch mapping
                    AppLogger.shared.log("🎯 [MapperViewModel] Calling saveAppLaunchMapping")
                    await saveAppLaunchMapping(kanataManager: manager)
                } else {
                    // Key-to-key mapping
                    await save(kanataManager: manager)
                }
            }
        }
    }

    func stopRecording() {
        finalizeTimer?.invalidate()
        finalizeTimer = nil
        keyboardCapture?.stopCapture()

        let wasRecordingOutput = isRecordingOutput
        isRecordingInput = false
        isRecordingOutput = false

        // If we stopped without capturing anything, restore previous state
        if inputSequence == nil {
            inputLabel = "a"
            inputKeyCode = nil
        }

        // For output: restore saved state if nothing was captured during this recording session
        if wasRecordingOutput, outputSequence == nil {
            // Restore previous output state
            if let savedLabel = savedOutputLabel {
                outputLabel = savedLabel
                outputSequence = savedOutputSequence
                selectedApp = savedSelectedApp
                selectedSystemAction = savedSelectedSystemAction
            } else {
                // No saved state, default to "a"
                outputLabel = "a"
            }
        }

        // Clear saved state
        savedOutputLabel = nil
        savedOutputSequence = nil
        savedSelectedApp = nil
        savedSelectedSystemAction = nil

        statusMessage = nil
    }

    func stopKeyCapture() {
        stopRecording()
        keyboardCapture = nil
    }

    func save(kanataManager: RuntimeCoordinator) async {
        guard let inputSeq = inputSequence,
              let outputSeq = outputSequence,
              !inputSeq.isEmpty,
              !outputSeq.isEmpty
        else {
            statusMessage = "Capture both input and output first"
            statusIsError = true
            return
        }

        isSaving = true
        statusMessage = nil

        do {
            // Use the existing config generator for complex sequences
            let configGenerator = KanataConfigGenerator(kanataManager: kanataManager)
            let generatedConfig = try await configGenerator.generateMapping(
                input: inputSeq,
                output: outputSeq
            )
            try await kanataManager.saveGeneratedConfiguration(generatedConfig)

            // Also save as custom rule for UI visibility
            let inputKanata = convertSequenceToKanataFormat(inputSeq)
            let outputKanata = convertSequenceToKanataFormat(outputSeq)

            // Convert currentLayer string to RuleCollectionLayer
            let targetLayer = layerFromString(currentLayer)

            // Use makeCustomRule to reuse existing rule ID for the same input key
            // This prevents duplicate keys in defsrc which causes Kanata validation errors
            var customRule = kanataManager.makeCustomRule(input: inputKanata, output: outputKanata)
            customRule.notes = "Created via Mapper [\(currentLayer) layer]"
            customRule.targetLayer = targetLayer

            _ = await kanataManager.saveCustomRule(customRule, skipReload: true)

            // Track the saved rule ID for potential clearing
            lastSavedRuleID = customRule.id

            // Notify overlay to refresh with new mapping
            NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)

            statusMessage = "✓ Saved"
            statusIsError = false
            AppLogger.shared.log("✅ [MapperViewModel] Saved mapping: \(inputSeq.displayString) → \(outputSeq.displayString) [layer: \(currentLayer)] (ruleID: \(customRule.id))")
        } catch {
            statusMessage = "Failed: \(error.localizedDescription)"
            statusIsError = true
            AppLogger.shared.error("❌ [MapperViewModel] Save failed: \(error)")
        }

        isSaving = false
    }

    private func reset() {
        inputLabel = "a"
        outputLabel = "a"
        inputSequence = nil
        outputSequence = nil
        inputKeyCode = nil
        selectedApp = nil
        selectedSystemAction = nil
        statusMessage = nil
    }

    /// Clear all values, delete the saved rule, and reset to original key context (or default)
    func clear() {
        stopRecording()
        selectedApp = nil
        selectedSystemAction = nil

        // Delete the saved rule if we have one
        if let ruleID = lastSavedRuleID, let manager = kanataManager {
            Task {
                await manager.removeCustomRule(withID: ruleID)
                // Notify overlay to refresh
                NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)
                AppLogger.shared.log("🧹 [MapperViewModel] Deleted rule \(ruleID) and refreshed overlay")
            }
            lastSavedRuleID = nil
        }

        // Reset to original key context if opened from overlay, otherwise default
        if let origInput = originalInputKey, let origOutput = originalOutputKey {
            // Re-apply the original presets
            inputLabel = formatKeyForDisplay(origInput)
            inputSequence = KeySequence(
                keys: [KeyPress(baseKey: origInput, modifiers: [], keyCode: 0)],
                captureMode: .single
            )

            // Check if original output is a system action or media key
            if let systemAction = SystemActionInfo.find(byOutput: origOutput) {
                selectedSystemAction = systemAction
                outputLabel = systemAction.name
                outputSequence = nil
            } else {
                outputLabel = formatKeyForDisplay(origOutput)
                outputSequence = KeySequence(
                    keys: [KeyPress(baseKey: origOutput, modifiers: [], keyCode: 0)],
                    captureMode: .single
                )
            }

            statusMessage = nil
            AppLogger.shared.log("🧹 [MapperViewModel] Reset to original key: \(origInput) → \(origOutput)")
        } else {
            // No context - reset to default
            reset()
            AppLogger.shared.log("🧹 [MapperViewModel] Cleared mapping (no key context)")
        }
    }

    /// Reset entire keyboard to default mappings (clears all custom rules and collections)
    func resetAllToDefaults(kanataManager: RuntimeCoordinator) async {
        stopRecording()

        do {
            try await kanataManager.resetToDefaultConfig()

            // Reset local state
            reset()
            lastSavedRuleID = nil
            originalInputKey = nil
            originalOutputKey = nil
            originalLayer = nil
            currentLayer = "base"

            // Notify overlay to refresh
            NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)

            statusMessage = "✓ Reset to defaults"
            statusIsError = false
            AppLogger.shared.log("🔄 [MapperViewModel] Reset entire keyboard to defaults")
        } catch {
            statusMessage = "Reset failed: \(error.localizedDescription)"
            statusIsError = true
            AppLogger.shared.error("❌ [MapperViewModel] Reset all failed: \(error)")
        }
    }

    /// Open file picker to select an app for launch action
    func pickAppForOutput() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Select an application to launch"
        panel.prompt = "Select"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }

            Task { @MainActor in
                self?.handleSelectedApp(at: url)
            }
        }
    }

    /// Process the selected app and update output
    private func handleSelectedApp(at url: URL) {
        let appName = url.deletingPathExtension().lastPathComponent
        let bundle = Bundle(url: url)
        let bundleIdentifier = bundle?.bundleIdentifier

        // Get the app icon
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64) // Reasonable size for display

        let appInfo = AppLaunchInfo(
            name: appName,
            bundleIdentifier: bundleIdentifier,
            icon: icon
        )

        selectedApp = appInfo
        selectedSystemAction = nil // Clear any system action selection
        outputLabel = appName
        outputSequence = nil // Clear any key sequence output

        AppLogger.shared.log("📱 [MapperViewModel] Selected app: \(appName) (\(bundleIdentifier ?? "no bundle ID"))")
        AppLogger.shared.log("📱 [MapperViewModel] kanataOutput will be: \(appInfo.kanataOutput)")

        // Auto-save if input is already set
        if let manager = kanataManager, inputSequence != nil {
            AppLogger.shared.log("📱 [MapperViewModel] Input already set, auto-saving...")
            Task {
                await saveAppLaunchMapping(kanataManager: manager)
            }
        } else {
            AppLogger.shared.log("📱 [MapperViewModel] Waiting for input to be recorded (inputSequence=\(inputSequence?.displayString ?? "nil"), manager=\(kanataManager != nil ? "set" : "nil"))")
        }
    }

    /// Save a mapping that launches an app
    private func saveAppLaunchMapping(kanataManager: RuntimeCoordinator) async {
        AppLogger.shared.log("🚀 [MapperViewModel] saveAppLaunchMapping called")

        guard let inputSeq = inputSequence, let app = selectedApp else {
            AppLogger.shared.log("⚠️ [MapperViewModel] saveAppLaunchMapping: missing input or app")
            statusMessage = "Set input key first"
            statusIsError = true
            return
        }

        isSaving = true
        statusMessage = nil

        let inputKanata = convertSequenceToKanataFormat(inputSeq)
        let targetLayer = layerFromString(currentLayer)

        AppLogger.shared.log("🚀 [MapperViewModel] Creating rule: input='\(inputKanata)' output='\(app.kanataOutput)' layer=\(targetLayer)")

        // Use makeCustomRule to reuse existing rule ID for the same input key
        // This prevents duplicate keys in defsrc which causes Kanata validation errors
        var customRule = kanataManager.makeCustomRule(input: inputKanata, output: app.kanataOutput)
        customRule.notes = "Launch \(app.name) [\(currentLayer) layer]"
        customRule.targetLayer = targetLayer

        let success = await kanataManager.saveCustomRule(customRule, skipReload: false)
        AppLogger.shared.log("🚀 [MapperViewModel] saveCustomRule returned: \(success)")

        if success {
            lastSavedRuleID = customRule.id
            // Notify overlay to refresh
            NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)
            statusMessage = "✓ Saved"
            statusIsError = false
            AppLogger.shared.log("✅ [MapperViewModel] Saved app launch: \(inputSeq.displayString) → launch:\(app.name) [layer: \(currentLayer)]")
        } else {
            statusMessage = "Failed to save"
            statusIsError = true
            AppLogger.shared.error("❌ [MapperViewModel] saveCustomRule returned false")
        }

        isSaving = false
    }

    /// Select a system action for the output
    func selectSystemAction(_ action: SystemActionInfo) {
        selectedSystemAction = action
        selectedApp = nil // Clear any app selection
        outputSequence = nil // Clear any key sequence output
        outputLabel = action.name

        AppLogger.shared.log("⚙️ [MapperViewModel] Selected system action: \(action.name) (\(action.id))")

        // Auto-save if input is already set
        if let manager = kanataManager, inputSequence != nil {
            AppLogger.shared.log("⚙️ [MapperViewModel] Input already set, auto-saving...")
            Task {
                await saveSystemActionMapping(kanataManager: manager)
            }
        }
    }

    /// Save a mapping that triggers a system action
    private func saveSystemActionMapping(kanataManager: RuntimeCoordinator) async {
        AppLogger.shared.log("⚙️ [MapperViewModel] saveSystemActionMapping called")

        guard let inputSeq = inputSequence, let action = selectedSystemAction else {
            statusMessage = "Set input key first"
            statusIsError = true
            return
        }

        isSaving = true
        statusMessage = nil

        let inputKanata = convertSequenceToKanataFormat(inputSeq)
        let targetLayer = layerFromString(currentLayer)

        AppLogger.shared.log("⚙️ [MapperViewModel] Creating rule: input='\(inputKanata)' output='\(action.kanataOutput)' layer=\(targetLayer)")

        var customRule = kanataManager.makeCustomRule(input: inputKanata, output: action.kanataOutput)
        customRule.notes = "\(action.name) [\(currentLayer) layer]"
        customRule.targetLayer = targetLayer

        let success = await kanataManager.saveCustomRule(customRule, skipReload: false)
        AppLogger.shared.log("⚙️ [MapperViewModel] saveCustomRule returned: \(success)")

        if success {
            lastSavedRuleID = customRule.id
            NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)
            statusMessage = "✓ Saved"
            statusIsError = false
            AppLogger.shared.log("✅ [MapperViewModel] Saved system action: \(inputSeq.displayString) → \(action.name) [layer: \(currentLayer)]")
        } else {
            statusMessage = "Failed to save"
            statusIsError = true
            AppLogger.shared.error("❌ [MapperViewModel] saveCustomRule returned false")
        }

        isSaving = false
    }

    /// Convert layer name string to RuleCollectionLayer
    private func layerFromString(_ name: String) -> RuleCollectionLayer {
        let lowercased = name.lowercased()
        switch lowercased {
        case "base": return .base
        case "nav", "navigation": return .navigation
        default: return .custom(name)
        }
    }

    /// Convert KeySequence to kanata format string
    private func convertSequenceToKanataFormat(_ sequence: KeySequence) -> String {
        let keyStrings = sequence.keys.map { keyPress -> String in
            var result = keyPress.baseKey.lowercased()

            // Handle special key names
            let keyMap: [String: String] = [
                "space": "spc",
                "return": "ret",
                "enter": "ret",
                "escape": "esc",
                "backspace": "bspc",
                "delete": "del"
            ]

            if let mapped = keyMap[result] {
                result = mapped
            }

            // Add modifiers
            if keyPress.modifiers.contains(.control) { result = "C-" + result }
            if keyPress.modifiers.contains(.option) { result = "A-" + result }
            if keyPress.modifiers.contains(.shift) { result = "S-" + result }
            if keyPress.modifiers.contains(.command) { result = "M-" + result }

            return result
        }

        return keyStrings.joined(separator: " ")
    }
}

// MARK: - Window Controller

@MainActor
class MapperWindowController {
    private var window: NSWindow?
    private weak var viewModel: KanataViewModel?
    /// Pending preset values to apply when view appears
    private var pendingPresetInput: String?
    private var pendingPresetOutput: String?
    private var pendingLayer: String?

    static let shared = MapperWindowController()

    /// Show the Mapper window, optionally with preset input/output values and layer from overlay click
    func showWindow(viewModel: KanataViewModel, presetInput: String? = nil, presetOutput: String? = nil, layer: String? = nil) {
        self.viewModel = viewModel
        pendingPresetInput = presetInput
        pendingPresetOutput = presetOutput
        pendingLayer = layer

        if let existingWindow = window, existingWindow.isVisible {
            // Window already visible - apply presets to existing view
            if let presetInput, let presetOutput {
                var userInfo: [String: Any] = ["input": presetInput, "output": presetOutput]
                if let layer {
                    userInfo["layer"] = layer
                }
                NotificationCenter.default.post(
                    name: .mapperPresetValues,
                    object: nil,
                    userInfo: userInfo
                )
            }
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = MapperView(presetInput: presetInput, presetOutput: presetOutput, presetLayer: layer)
            .environmentObject(viewModel)

        // Window height calculation:
        // - Header: ~30pt
        // - Input keycap (max): 150pt + label 20pt = 170pt
        // - Arrow: ~25pt
        // - Output keycap (max): 150pt + label 20pt = 170pt
        // - Bottom bar: ~35pt
        // - Padding: ~30pt
        // Total: ~460pt for vertical layout with max-height keycaps
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mapper"
        window.minSize = NSSize(width: 340, height: 300)
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false

        // Persistent window position
        window.setFrameAutosaveName("MapperWindow")
        if !window.setFrameUsingName("MapperWindow") {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)

        self.window = window
    }
}

// MARK: - Preview

#Preview {
    MapperView()
        .environmentObject(KanataViewModel(manager: RuntimeCoordinator()))
        .frame(height: 500)
}
