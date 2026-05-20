import AppKit
import SwiftUI

/// The visual content of the drag-to-authorize floating panel.
/// Uses NSVisualEffectView for glass material and drives animations
/// from DragToAuthorizeStateModel.
struct DragToAuthorizeOverlayView: View {
    @Bindable var model: DragToAuthorizeStateModel

    var body: some View {
        ZStack {
            // Background glass material
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

            // Content
            contentLayer
                .opacity(model.dismissOpacity)
                .offset(y: model.dismissOffset)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .onAppear {
            model.arrowPulsing = true
        }
    }

    @ViewBuilder
    private var contentLayer: some View {
        if model.showSuccess {
            successView
                .transition(.scale.combined(with: .opacity))
        } else {
            dragPromptView
                .offset(x: model.retryShakeOffset)
        }
    }

    // MARK: - Drag Prompt (Normal State)

    private var dragPromptView: some View {
        VStack(spacing: 14) {
            // Animated arrow pointing up
            arrowView

            // Instruction text
            instructionText

            // Draggable tile
            draggableTile
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var arrowView: some View {
        Image(systemName: "chevron.up")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.secondary)
            .scaleEffect(model.arrowPulsing ? 1.15 : 1.0)
            .opacity(model.arrowPulsing ? 1.0 : 0.6)
            .animation(
                model.arrowPulsing
                    ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                    : .default,
                value: model.arrowPulsing
            )
    }

    private var instructionText: some View {
        Group {
            if model.showRetryShake {
                Text("Try again — drag into the list above")
                    .foregroundStyle(.orange)
            } else {
                Text("Drag into the \(model.target.displayName) list above")
                    .foregroundStyle(.primary)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .animation(.easeInOut(duration: 0.2), value: model.showRetryShake)
    }

    private var draggableTile: some View {
        HStack(spacing: 12) {
            Image(nsImage: model.launcherIcon)
                .resizable()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("kanata-launcher")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("KeyPath Engine")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(
                    color: .black.opacity(model.dragLifted ? 0.2 : 0.08),
                    radius: model.dragLifted ? 12 : 4,
                    y: model.dragLifted ? 4 : 2
                )
        )
        .scaleEffect(model.dragLifted ? 1.03 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: model.dragLifted)
    }

    // MARK: - Success State

    private var successView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.green.opacity(0.15))
                    .frame(width: 64, height: 64)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: model.showSuccess)
            }

            Text("\(model.target.displayName) granted")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - NSVisualEffectView Wrapper

private struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 16
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context _: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
