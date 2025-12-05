import AppKit
import SwiftUI

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
    private let baseHeight: CGFloat = 120 // Output keycap height (emphasized, 20% larger than input)
    private let maxHeightMultiplier: CGFloat = 1.5 // Max height is 1.5x base (180pt)
    private let minWidth: CGFloat = 120 // Minimum width (matches height for square keycaps)
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
        Button {
            withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
                isPressed = true
            }
            Task { @MainActor in
                try await Task.sleep(for: .milliseconds(100))
                withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
                    isPressed = false
                }
            }
            onTap()
        } label: {
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
            .frame(
                width: appInfo != nil ? 120 : (systemActionInfo != nil ? 120 : keycapWidth),
                height: appInfo != nil ? 120 : (systemActionInfo != nil ? 120 : keycapHeight)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: keycapHeight)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: dynamicFontSize)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
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
        Button {
            withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
                isPressed = true
            }
            Task { @MainActor in
                try await Task.sleep(for: .milliseconds(100))
                withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
                    isPressed = false
                }
            }
            onTap()
        } label: {
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
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
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
