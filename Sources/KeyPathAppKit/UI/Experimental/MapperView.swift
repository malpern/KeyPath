import AppKit
import KeyPathCore
import SwiftUI

// MARK: - Mapper View

/// Experimental key mapping page with visual keycap-based input/output capture.
/// Accessible from File menu as "Mapper".
struct MapperView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @StateObject private var viewModel = MapperViewModel()

    var body: some View {
        VStack(spacing: 12) {
            // Keycaps for input and output
            MapperKeycapPair(
                inputLabel: viewModel.inputLabel,
                outputLabel: viewModel.outputLabel,
                isRecordingInput: viewModel.isRecordingInput,
                isRecordingOutput: viewModel.isRecordingOutput,
                onInputTap: { viewModel.toggleInputRecording() },
                onOutputTap: { viewModel.toggleOutputRecording() }
            )

            // Status message (centered)
            if let message = viewModel.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(viewModel.statusIsError ? .red : .secondary)
                    .lineLimit(1)
            }
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
        }
        .onDisappear {
            viewModel.stopKeyCapture()
        }
    }
}

// MARK: - Mapper Keycap Pair

/// Responsive container that shows input/output keycaps side-by-side when they fit,
/// or stacked vertically when content is too wide.
private struct MapperKeycapPair: View {
    let inputLabel: String
    let outputLabel: String
    let isRecordingInput: Bool
    let isRecordingOutput: Bool
    let onInputTap: () -> Void
    let onOutputTap: () -> Void

    /// Horizontal margin on each side
    private let horizontalMargin: CGFloat = 16

    /// Threshold for switching to vertical layout (character count)
    private let verticalThreshold = 15

    /// Whether to use vertical (stacked) layout
    private var shouldStack: Bool {
        inputLabel.count > verticalThreshold || outputLabel.count > verticalThreshold
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

            // Input keycap
            VStack(spacing: 8) {
                MapperKeycapView(
                    label: inputLabel,
                    isRecording: isRecordingInput,
                    maxWidth: maxWidth,
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

            // Output keycap
            VStack(spacing: 8) {
                MapperKeycapView(
                    label: outputLabel,
                    isRecording: isRecordingOutput,
                    maxWidth: maxWidth,
                    onTap: onOutputTap
                )
                Text("Output")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func verticalLayout(maxWidth: CGFloat) -> some View {
        VStack(spacing: 8) {
            // Input keycap with label
            VStack(spacing: 6) {
                Text("Input")
                    .font(.caption)
                    .foregroundColor(.secondary)

                MapperKeycapView(
                    label: inputLabel,
                    isRecording: isRecordingInput,
                    maxWidth: maxWidth,
                    onTap: onInputTap
                )
            }

            // Arrow indicator
            Image(systemName: "arrow.down")
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.vertical, 2)

            // Output keycap with label
            VStack(spacing: 6) {
                MapperKeycapView(
                    label: outputLabel,
                    isRecording: isRecordingOutput,
                    maxWidth: maxWidth,
                    onTap: onOutputTap
                )

                Text("Output")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Mapper Keycap View

/// Large (2x scale) keycap styled like the overlay keyboard.
/// Click to start/stop recording key input. Width grows to fit content up to maxWidth,
/// then text wraps to multiple lines up to maxHeight, then text shrinks to fit.
struct MapperKeycapView: View {
    let label: String
    let isRecording: Bool
    var maxWidth: CGFloat = .infinity
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    // Sizing constants
    private let baseHeight: CGFloat = 100 // Base keycap height (single line)
    private let maxHeightMultiplier: CGFloat = 1.5 // Max height is 1.5x base (150pt)
    private let minWidth: CGFloat = 100 // Minimum width
    private let horizontalPadding: CGFloat = 20 // Padding for text
    private let verticalPadding: CGFloat = 14 // Padding top/bottom
    private let baseFontSize: CGFloat = 36 // Large base font size
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

    /// Calculate font size - shrinks if content won't fit in max height
    private var dynamicFontSize: CGFloat {
        guard maxWidth < .infinity else { return baseFontSize }

        // Calculate how many lines we'd need at base font size
        let availableTextWidth = maxWidth - horizontalPadding * 2
        let charWidth: CGFloat = baseFontSize * 0.6
        let contentWidth = CGFloat(label.count) * charWidth
        let linesNeeded = ceil(contentWidth / availableTextWidth)

        // Calculate height needed at base font size
        let lineHeight: CGFloat = baseFontSize * 1.3
        let heightNeeded = linesNeeded * lineHeight + verticalPadding * 2

        // If it fits in max height, use base font size
        if heightNeeded <= maxHeight {
            return baseFontSize
        }

        // Otherwise, calculate what font size would fit
        // We need to fit the same content in maxHeight
        let availableTextHeight = maxHeight - verticalPadding * 2
        // Estimate: shrink proportionally
        let scaleFactor = availableTextHeight / (linesNeeded * lineHeight)
        let newFontSize = baseFontSize * scaleFactor

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

            // Key label - wraps to multiple lines, shrinks if needed
            Text(label)
                .font(.system(size: dynamicFontSize, weight: .medium))
                .foregroundStyle(foregroundColor)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .minimumScaleFactor(minFontSize / baseFontSize)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding / 2)
        }
        .frame(width: keycapWidth, height: keycapHeight)
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

// MARK: - Mapper View Model

@MainActor
class MapperViewModel: ObservableObject {
    @Published var inputLabel: String = "a"
    @Published var outputLabel: String = "a"
    @Published var isRecordingInput = false
    @Published var isRecordingOutput = false
    @Published var isSaving = false
    @Published var statusMessage: String?
    @Published var statusIsError = false

    private var inputSequence: KeySequence?
    private var outputSequence: KeySequence?
    private var keyboardCapture: KeyboardCapture?
    private var kanataManager: RuntimeCoordinator?
    private var finalizeTimer: Timer?

    /// Delay before finalizing a sequence capture (allows for multi-key sequences)
    private let sequenceFinalizeDelay: TimeInterval = 0.8

    var canSave: Bool {
        inputSequence != nil && outputSequence != nil
    }

    func configure(kanataManager: RuntimeCoordinator) {
        self.kanataManager = kanataManager
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
        inputLabel = "..."
        statusMessage = "Press keys (sequence supported)"
        statusIsError = false
        startCapture(isInput: true)
    }

    private func startOutputRecording() {
        isRecordingOutput = true
        outputSequence = nil
        outputLabel = "..."
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

    private func finalizeCapture() {
        finalizeTimer?.invalidate()
        finalizeTimer = nil

        // Stop recording but keep the captured sequence
        keyboardCapture?.stopCapture()
        isRecordingInput = false
        isRecordingOutput = false
        statusMessage = nil

        // Auto-save when both input and output are captured
        if canSave, let manager = kanataManager {
            Task {
                await save(kanataManager: manager)
            }
        }
    }

    func stopRecording() {
        finalizeTimer?.invalidate()
        finalizeTimer = nil
        keyboardCapture?.stopCapture()
        isRecordingInput = false
        isRecordingOutput = false

        // If we stopped without capturing anything, restore default label
        if inputSequence == nil {
            inputLabel = "a"
        }
        if outputSequence == nil {
            outputLabel = "a"
        }
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
            let customRule = CustomRule(
                input: inputKanata,
                output: outputKanata,
                isEnabled: true,
                notes: "Created via Mapper"
            )
            _ = await kanataManager.saveCustomRule(customRule, skipReload: true)

            // Notify overlay to refresh with new mapping
            NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)

            statusMessage = "✓ Saved"
            statusIsError = false
            AppLogger.shared.log("✅ [MapperViewModel] Saved mapping: \(inputSeq.displayString) → \(outputSeq.displayString)")

            // Clear after successful save
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.reset()
            }
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
        statusMessage = nil
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

    static let shared = MapperWindowController()

    func showWindow(viewModel: KanataViewModel) {
        self.viewModel = viewModel

        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = MapperView()
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
