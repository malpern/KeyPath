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

    private var mapperContent: some View {
        VStack(spacing: 8) {
            VStack(spacing: 8) {
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
                        onOutputTap: { viewModel.toggleOutputRecording() }
                    )
                    .frame(width: baseWidth, height: proxy.size.height, alignment: .center)
                    .scaleEffect(scale, anchor: .center)
                    .frame(width: availableWidth, height: proxy.size.height, alignment: .center)
                }
                .frame(height: 120)

                if viewModel.showAdvanced {
                    AdvancedBehaviorContent(viewModel: viewModel)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer(minLength: 0)

                HStack {
                    Spacer(minLength: 0)

                    LayerSwitcherButton(
                        currentLayer: viewModel.currentLayer,
                        onSelectLayer: { layer in
                            viewModel.setLayer(layer)
                        },
                        onCreateLayer: {}
                    )
                    .accessibilityIdentifier("overlay-mapper-layer-switcher")

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 0)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, alignment: .center)
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
            return "System Not Ready"
        case let .unhealthy(issueCount):
            return issueCount == 1 ? "1 Issue Found" : "\(issueCount) Issues Found"
        case .healthy, .dismissed:
            return "System Ready"
        }
    }

    private var healthGateMessage: String {
        switch healthIndicatorState {
        case .checking:
            return "Checking system health before enabling the mapper."
        case let .unhealthy(issueCount):
            return issueCount == 1
                ? "Fix the issue to enable quick remapping in the drawer."
                : "Fix the issues to enable quick remapping in the drawer."
        case .healthy, .dismissed:
            return "System health is good."
        }
    }

    private var healthGateButtonTitle: String {
        switch healthIndicatorState {
        case .checking:
            return "Open Setup"
        case .unhealthy:
            return "Fix Issues"
        case .healthy, .dismissed:
            return "Open Setup"
        }
    }
}
