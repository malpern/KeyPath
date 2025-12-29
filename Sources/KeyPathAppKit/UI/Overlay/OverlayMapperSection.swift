import AppKit
import KeyPathCore
import SwiftUI

/// Mapper section for the overlay drawer.
/// Allows quick key remapping directly from the keyboard overlay.
struct OverlayMapperSection: View {
    let isDark: Bool
    /// Callback when a key is selected (to highlight on keyboard)
    var onKeySelected: ((UInt16?) -> Void)?

    @StateObject private var viewModel = MapperViewModel()
    @EnvironmentObject private var kanataViewModel: KanataViewModel
    @State private var mode: MapperMode = .basic

    enum MapperMode: String, CaseIterable {
        case basic = "Basic"
        case advanced = "Advanced"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with layer indicator on far right
            HStack {
                Text("Mapper")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                // Layer indicator
                LayerIndicatorPill(
                    layerName: viewModel.currentLayer,
                    isDark: isDark
                )
            }

            // Segmented control for Basic/Advanced
            Picker("Mode", selection: $mode) {
                ForEach(MapperMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Content based on mode
            if mode == .basic {
                basicContent
            } else {
                advancedContent
            }
        }
        .onAppear {
            viewModel.configure(kanataManager: kanataViewModel.underlyingManager)
            // Notify parent to highlight the A key
            onKeySelected?(viewModel.inputKeyCode)
        }
        .onChange(of: viewModel.inputKeyCode) { _, newKeyCode in
            onKeySelected?(newKeyCode)
        }
    }

    // MARK: - Basic Content

    @ViewBuilder
    private var basicContent: some View {
        VStack(spacing: 16) {
            // Keycap pair (scaled down for drawer)
            DrawerMapperKeycapPair(
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

            // Status message
            if let message = viewModel.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(viewModel.statusIsError ? .red : .secondary)
            }

            // Action buttons
            HStack(spacing: 12) {
                // Clear button
                Button {
                    viewModel.clear()
                } label: {
                    Label("Clear", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("overlay-mapper-clear")

                Spacer()

                // Output type picker menu
                Menu {
                    Button {
                        viewModel.pickAppForOutput()
                    } label: {
                        Label("Launch App...", systemImage: "app")
                    }

                    Button {
                        viewModel.showURLInputDialog()
                    } label: {
                        Label("Open URL...", systemImage: "link")
                    }

                    Divider()

                    // System actions
                    ForEach(SystemActionInfo.allActions) { action in
                        Button {
                            viewModel.selectSystemAction(action)
                        } label: {
                            Label(action.name, systemImage: action.sfSymbol)
                        }
                    }
                } label: {
                    Label("Output", systemImage: "ellipsis.circle")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .accessibilityIdentifier("overlay-mapper-output-menu")
            }
        }
    }

    // MARK: - Advanced Content

    @ViewBuilder
    private var advancedContent: some View {
        VStack(spacing: 12) {
            // Same keycap pair
            DrawerMapperKeycapPair(
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

            // Hold behavior section
            VStack(alignment: .leading, spacing: 8) {
                Text("Hold Action")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack {
                    Text(viewModel.holdAction.isEmpty ? "None" : viewModel.holdAction)
                        .font(.subheadline)
                        .foregroundStyle(viewModel.holdAction.isEmpty ? .secondary : .primary)

                    Spacer()

                    Button(viewModel.isRecordingHold ? "Stop" : "Record") {
                        viewModel.toggleHoldRecording()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: isDark ? 0.15 : 0.95))
            )

            // Double tap section
            VStack(alignment: .leading, spacing: 8) {
                Text("Double Tap Action")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack {
                    Text(viewModel.doubleTapAction.isEmpty ? "None" : viewModel.doubleTapAction)
                        .font(.subheadline)
                        .foregroundStyle(viewModel.doubleTapAction.isEmpty ? .secondary : .primary)

                    Spacer()

                    Button(viewModel.isRecordingDoubleTap ? "Stop" : "Record") {
                        viewModel.toggleDoubleTapRecording()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: isDark ? 0.15 : 0.95))
            )

            // Status message
            if let message = viewModel.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(viewModel.statusIsError ? .red : .secondary)
            }
        }
    }
}

// MARK: - Layer Indicator Pill

private struct LayerIndicatorPill: View {
    let layerName: String
    let isDark: Bool

    private var displayName: String {
        layerName.lowercased() == "base" ? "Base" : layerName.capitalized
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 9, weight: .medium))
            Text(displayName)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(white: isDark ? 0.2 : 0.9))
        )
    }
}

// MARK: - Drawer Mapper Keycap Pair

/// Scaled-down keycap pair for the overlay drawer
private struct DrawerMapperKeycapPair: View {
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

    private let keycapSize: CGFloat = 60

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            // Input keycap
            VStack(spacing: 4) {
                DrawerKeycap(
                    label: inputLabel,
                    isRecording: isRecordingInput,
                    size: keycapSize,
                    onTap: onInputTap
                )
                Text("Input")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Arrow
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundColor(.secondary)

            // Output keycap
            VStack(spacing: 4) {
                if let app = outputAppInfo {
                    DrawerAppKeycap(
                        appInfo: app,
                        isRecording: isRecordingOutput,
                        size: keycapSize,
                        onTap: onOutputTap
                    )
                } else if let systemAction = outputSystemActionInfo {
                    DrawerSystemActionKeycap(
                        action: systemAction,
                        isRecording: isRecordingOutput,
                        size: keycapSize,
                        onTap: onOutputTap
                    )
                } else if let favicon = outputURLFavicon {
                    DrawerURLKeycap(
                        label: outputLabel,
                        favicon: favicon,
                        isRecording: isRecordingOutput,
                        size: keycapSize,
                        onTap: onOutputTap
                    )
                } else {
                    DrawerKeycap(
                        label: outputLabel,
                        isRecording: isRecordingOutput,
                        size: keycapSize,
                        onTap: onOutputTap
                    )
                }
                Text("Output")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Drawer Keycaps

private struct DrawerKeycap: View {
    let label: String
    let isRecording: Bool
    let size: CGFloat
    let onTap: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(borderColor, lineWidth: isRecording ? 2 : 1)
                    )

                Text(label)
                    .font(.system(size: size * 0.35, weight: .medium, design: .rounded))
                    .foregroundStyle(isRecording ? Color.accentColor : .primary)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var backgroundColor: Color {
        if isRecording {
            return Color.accentColor.opacity(0.15)
        }
        if isHovered {
            return Color(white: isDark ? 0.25 : 0.92)
        }
        return Color(white: isDark ? 0.2 : 0.95)
    }

    private var borderColor: Color {
        if isRecording {
            return Color.accentColor
        }
        return Color(white: isDark ? 0.35 : 0.8)
    }
}

private struct DrawerAppKeycap: View {
    let appInfo: AppLaunchInfo
    let isRecording: Bool
    let size: CGFloat
    let onTap: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(borderColor, lineWidth: isRecording ? 2 : 1)
                    )

                VStack(spacing: 2) {
                    Image(nsImage: appInfo.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size * 0.5, height: size * 0.5)

                    Text(appInfo.name)
                        .font(.system(size: 8, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var backgroundColor: Color {
        if isRecording { return Color.accentColor.opacity(0.15) }
        if isHovered { return Color(white: isDark ? 0.25 : 0.92) }
        return Color(white: isDark ? 0.2 : 0.95)
    }

    private var borderColor: Color {
        isRecording ? Color.accentColor : Color(white: isDark ? 0.35 : 0.8)
    }
}

private struct DrawerSystemActionKeycap: View {
    let action: SystemActionInfo
    let isRecording: Bool
    let size: CGFloat
    let onTap: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(borderColor, lineWidth: isRecording ? 2 : 1)
                    )

                Image(systemName: action.sfSymbol)
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(isRecording ? Color.accentColor : .primary)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var backgroundColor: Color {
        if isRecording { return Color.accentColor.opacity(0.15) }
        if isHovered { return Color(white: isDark ? 0.25 : 0.92) }
        return Color(white: isDark ? 0.2 : 0.95)
    }

    private var borderColor: Color {
        isRecording ? Color.accentColor : Color(white: isDark ? 0.35 : 0.8)
    }
}

private struct DrawerURLKeycap: View {
    let label: String
    let favicon: NSImage
    let isRecording: Bool
    let size: CGFloat
    let onTap: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(borderColor, lineWidth: isRecording ? 2 : 1)
                    )

                VStack(spacing: 2) {
                    Image(nsImage: favicon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size * 0.4, height: size * 0.4)

                    Text(label)
                        .font(.system(size: 8, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var backgroundColor: Color {
        if isRecording { return Color.accentColor.opacity(0.15) }
        if isHovered { return Color(white: isDark ? 0.25 : 0.92) }
        return Color(white: isDark ? 0.2 : 0.95)
    }

    private var borderColor: Color {
        isRecording ? Color.accentColor : Color(white: isDark ? 0.35 : 0.8)
    }
}
