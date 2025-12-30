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
    /// Callback when a key is selected (to highlight on keyboard)
    var onKeySelected: ((UInt16?) -> Void)?

    @StateObject private var viewModel = MapperViewModel()

    var body: some View {
        VStack(spacing: 8) {
            if shouldShowHealthGate {
                healthGateContent
            } else {
                mapperContent
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

    private let showDebugBorders = true

    private var mapperContent: some View {
        VStack(spacing: 0) {
            // A->B keycap pair - no horizontal padding, should touch drawer edge
            GeometryReader { proxy in
                let availableWidth = max(1, proxy.size.width)
                let keycapWidth: CGFloat = 100
                let arrowWidth: CGFloat = 20
                let spacing: CGFloat = 16
                let shadowBuffer: CGFloat = 8
                let baseWidth = keycapWidth * 2 + spacing * 2 + arrowWidth + shadowBuffer
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
            GeometryReader { proxy in
                layerSwitcherButton
                    .frame(width: proxy.size.width * 0.9, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: 28)
            .padding(.bottom, 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Layer switcher button styled like the Add Shortcut button
    private var layerSwitcherButton: some View {
        Menu {
            ForEach(["base", "nav"], id: \.self) { layer in
                Button {
                    viewModel.setLayer(layer)
                } label: {
                    HStack {
                        Text(layer.lowercased() == "base" ? "Base Layer" : layer.capitalized)
                        Spacer()
                        if viewModel.currentLayer.lowercased() == layer.lowercased() {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "square.3.layers.3d")
                Text(viewModel.currentLayer.lowercased() == "base" ? "Base Layer" : viewModel.currentLayer.capitalized)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("overlay-mapper-layer-switcher")
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
