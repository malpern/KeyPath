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
    }

    private let showDebugBorders = false

    private var mapperContent: some View {
        VStack(spacing: 0) {
            // A->B keycap pair - no horizontal padding, should touch drawer edge
            GeometryReader { proxy in
                let availableWidth = max(1, proxy.size.width)
                let keycapWidth: CGFloat = 100
                let arrowWidth: CGFloat = 20
                let spacing: CGFloat = 16
                // No shadow buffer - flush right edge
                let baseWidth = keycapWidth * 2 + spacing * 2 + arrowWidth
                let scale = min(1, availableWidth / baseWidth)

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
                    onOutputTap: { viewModel.toggleOutputRecording() },

                    compactNoSidePadding: true
                )
                .border(showDebugBorders ? Color.blue : Color.clear, width: 1)
                .frame(width: baseWidth, height: proxy.size.height, alignment: .leading)
                .scaleEffect(scale, anchor: .leading)
                .frame(width: availableWidth, height: proxy.size.height, alignment: .leading)
            }
            .frame(height: 120)

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
    }

    /// Layer switcher menu styled like the Add Shortcut button
    /// - Parameter width: Explicit width for the menu button
    @ViewBuilder
    private func layerSwitcherMenu(width: CGFloat) -> some View {
        let layerDisplayName = viewModel.currentLayer.lowercased() == "base" ? "Base Layer" : viewModel.currentLayer.capitalized
        let availableLayers = ["base", "nav"]

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

                    Button {
                        viewModel.setLayer(layer)
                        isLayerPickerOpen = false
                    } label: {
                        HStack(spacing: 8) {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                            } else {
                                // Invisible placeholder to maintain alignment
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .opacity(0)
                            }
                            Text(displayName)
                                .font(.subheadline)
                            Spacer()
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
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
