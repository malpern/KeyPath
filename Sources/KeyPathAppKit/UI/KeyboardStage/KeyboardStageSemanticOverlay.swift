import AppKit
import SwiftUI

struct KeyboardStageSemanticOverlay: View {
    let frame: KeyboardStagePresentedFrame
    var rendersKeyLegends = true
    let onPointerPressChange: @MainActor @Sendable (UInt16, Bool) -> Void

    var body: some View {
        GeometryReader { geometry in
            let scene = frame.scene
            let projection = KeyboardStageProjection(scene: scene, size: geometry.size)
            let palette = KeyboardStagePalette(displayMode: scene.displayMode)
            let lighting = KeyboardStageLightingResolver(
                scene: scene,
                entrance: frame.entrance
            )
            ZStack(alignment: .topLeading) {
                ForEach(scene.keys) { key in
                    let keyFrame = projection.projectKey(key)
                    KeyboardStageKeyLegendOverlay(
                        key: key,
                        frame: keyFrame,
                        style: palette.style(
                            for: key.role,
                            interactionLevel: key.interactionLevel
                        ),
                        lighting: lighting.lighting(for: key),
                        rendersVisualLegend: rendersKeyLegends,
                        visibility: keyLegendVisibility(
                            frame: keyFrame,
                            projection: projection
                        )
                    )
                    .zIndex(0)

                    KeyboardStageKeyHitTarget(
                        keyCode: key.keyCode,
                        frame: keyFrame,
                        onPressChange: onPointerPressChange
                    )
                    .zIndex(2)
                }

                ForEach(scene.decorations) { decoration in
                    KeyboardStageDecorationLegendOverlay(
                        decoration: decoration,
                        frame: projection.projectDecoration(decoration),
                        style: palette.style(for: decoration.role),
                        lighting: lighting.lighting(for: decoration)
                    )
                    .zIndex(decoration.kind.isCapsEcho ? -0.5 : 1)
                }
            }
        }
    }

    private var scene: KeyboardStageScene {
        frame.scene
    }

    private func keyLegendVisibility(
        frame: CGRect,
        projection: KeyboardStageProjection
    ) -> Double {
        let area = max(1, frame.width * frame.height)
        var occlusion: Float = 0

        for decoration in scene.decorations where decoration.kind.occludesKeyLegends {
            let decorationFrame = projection.projectDecoration(decoration)
            let intersection = frame.intersection(decorationFrame)
            guard !intersection.isNull,
                  intersection.width * intersection.height / area > 0.22
            else {
                continue
            }
            occlusion = max(occlusion, decoration.opacity)
        }

        return Double(max(0, 1 - occlusion))
    }
}

private struct KeyboardStageKeyHitTarget: View {
    let keyCode: UInt16
    let frame: CGRect
    let onPressChange: @MainActor @Sendable (UInt16, Bool) -> Void

    @State private var isPressed = false

    var body: some View {
        Color.clear
            .frame(width: frame.width, height: frame.height)
            .contentShape(RoundedRectangle(
                cornerRadius: max(4, min(frame.width, frame.height) * 0.16),
                style: .continuous
            ))
            .position(x: frame.midX, y: frame.midY)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let bounds = CGRect(origin: .zero, size: frame.size)
                        updatePress(bounds.contains(value.location))
                    }
                    .onEnded { _ in
                        updatePress(false)
                    }
            )
            .onDisappear {
                updatePress(false)
            }
            .accessibilityHidden(true)
            .accessibilityIdentifier("keyboard-stage-pointer-key-\(keyCode)")
    }

    private func updatePress(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        onPressChange(keyCode, pressed)
    }
}

private extension KeyboardStageDecoration.Kind {
    var isCapsEcho: Bool {
        if case .capsEcho = self { return true }
        return false
    }

    var occludesKeyLegends: Bool {
        switch self {
        case .applicationTarget, .launcherChoiceTarget, .handoffTarget:
            true
        case .keyboardDeck, .capsEcho, .modifierToken, .launcherCandidateMarker:
            false
        }
    }
}

private struct KeyboardStageKeyLegendOverlay: View {
    let key: KeyboardStageKey
    let frame: CGRect
    let style: KeyboardStageSurfaceStyle
    let lighting: KeyboardStageSurfaceLighting
    let rendersVisualLegend: Bool
    let visibility: Double

    var body: some View {
        let primarySize = max(8, min(22, frame.height * 0.34))
        let secondarySize = max(6, min(12, frame.height * 0.17))
        let primaryWeight: Font.Weight = switch key.role {
        case .standard, .modifier, .dimmed: .regular
        case .deck, .recommended, .escape, .hyper, .launcher, .installed: .medium
        }
        VStack(spacing: max(1, frame.height * 0.025)) {
            ZStack {
                if let previous = key.legend.previous {
                    Text(verbatim: previous)
                        .opacity(Double(1 - key.legend.transitionProgress))
                        .scaleEffect(1 + CGFloat(key.legend.transitionProgress) * 0.08)
                }

                Text(verbatim: key.legend.primary)
                    .opacity(key.legend.previous == nil ? 1 : Double(key.legend.transitionProgress))
                    .scaleEffect(0.92 + CGFloat(key.legend.transitionProgress) * 0.08)
            }
            .font(.system(size: primarySize, weight: primaryWeight, design: .default))
            .lineLimit(1)
            .minimumScaleFactor(0.55)

            if let secondary = key.legend.secondary {
                Text(verbatim: secondary)
                    .font(.system(size: secondarySize, weight: .medium, design: .default))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .opacity(0.86)
            }
        }
        .foregroundStyle(legendColor)
        .shadow(
            color: Color.white.opacity(Double(lighting.legendGlow) * 0.52),
            radius: 0.7
        )
        .shadow(
            color: Color(red: 0.68, green: 0.82, blue: 1)
                .opacity(Double(lighting.legendGlow) * 0.28),
            radius: 2.4
        )
        .shadow(
            color: Color(red: 0.40, green: 0.62, blue: 1)
                .opacity(Double(lighting.legendGlow) * 0.06),
            radius: 6.5
        )
        .padding(.horizontal, max(2, frame.width * 0.08))
        .frame(width: frame.width, height: frame.height)
        .rotationEffect(.radians(Double(key.rotationRadians)))
        .position(x: frame.midX, y: frame.midY)
        // Metal renders the visible glyph mask so its emissive light can take
        // part in the same linear-light pipeline as the keycap. The native
        // text remains present at zero visual opacity as the accessibility
        // authority and the SwiftUI fallback continues to render it normally.
        .opacity(
            Double(key.opacity * lighting.legendOpacity)
                * visibility
                * (rendersVisualLegend ? 1 : 0)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(key.accessibilityRole == nil)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("keyboard-stage-key-\(key.keyCode)")
        .allowsHitTesting(false)
    }

    private var legendColor: Color {
        lighting.legendColor(settledColor: style.legend).color
    }

    private var accessibilityLabel: Text {
        switch key.accessibilityRole {
        case .capsToEscape:
            Text("Caps Lock changes to Escape", bundle: KeyPathAppKitResources.bundle)
        case .capsToHyper:
            Text(
                "Holding Caps Lock produces Hyper: Control, Option, Shift, and Command",
                bundle: KeyPathAppKitResources.bundle
            )
        case let .launcherKey(letter, application):
            Text(
                "Hyper plus \(letter) launches \(application.name)",
                bundle: KeyPathAppKitResources.bundle
            )
        case nil:
            Text(verbatim: "")
        }
    }
}

private struct KeyboardStageDecorationLegendOverlay: View {
    let decoration: KeyboardStageDecoration
    let frame: CGRect
    let style: KeyboardStageSurfaceStyle
    let lighting: KeyboardStageSurfaceLighting

    var body: some View {
        ZStack {
            switch decoration.kind {
            case .keyboardDeck:
                Color.clear
                    .accessibilityHidden(true)

            case let .capsEcho(label):
                Text(verbatim: label)
                    .font(.system(size: max(7, frame.height * 0.30), weight: .medium, design: .default))
                    .foregroundStyle(legendColor)
                    .accessibilityHidden(true)

            case let .modifierToken(symbol):
                Text(verbatim: symbol)
                    .font(.system(size: max(8, frame.height * 0.42), weight: .semibold, design: .default))
                    .foregroundStyle(legendColor)
                    .accessibilityHidden(true)

            case .launcherCandidateMarker:
                Circle()
                    .fill(legendColor.opacity(0.88))
                    .frame(
                        width: max(3, frame.width * 0.42),
                        height: max(3, frame.height * 0.42)
                    )
                    .accessibilityHidden(true)

            case let .applicationTarget(application):
                KeyboardStageApplicationTargetLabel(
                    application: application,
                    foregroundColor: legendColor,
                    availableWidth: frame.width
                )
                .accessibilityHidden(true)

            case .launcherChoiceTarget:
                HStack(spacing: 7) {
                    Image(systemName: "app.fill")
                    Text("Choose a letter + app", bundle: KeyPathAppKitResources.bundle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .font(.system(size: max(10, frame.height * 0.2), weight: .semibold, design: .default))
                .foregroundStyle(legendColor)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    Text(
                        "Choose a letter and favorite app here",
                        bundle: KeyPathAppKitResources.bundle
                    )
                )
                .accessibilityIdentifier("keyboard-stage-launcher-choice")

            case .handoffTarget:
                HStack(spacing: 7) {
                    Image(systemName: "square.grid.2x2.fill")
                    Text("Rules", bundle: KeyPathAppKitResources.bundle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(.system(size: max(10, frame.height * 0.22), weight: .semibold, design: .default))
                .foregroundStyle(legendColor)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    Text(
                        "Continue in Rules to discover more keyboard changes",
                        bundle: KeyPathAppKitResources.bundle
                    )
                )
                .accessibilityIdentifier("keyboard-stage-rules-handoff")
            }
        }
        .frame(width: frame.width, height: frame.height)
        .rotationEffect(.radians(Double(decoration.rotationRadians)))
        .position(x: frame.midX, y: frame.midY)
        .opacity(Double(decoration.opacity * lighting.legendOpacity))
        .shadow(
            color: Color.white.opacity(Double(lighting.legendGlow) * 0.66),
            radius: 0.8
        )
        .shadow(
            color: Color(red: 0.58, green: 0.76, blue: 1)
                .opacity(Double(lighting.legendGlow) * 0.46),
            radius: 3.5
        )
        .allowsHitTesting(false)
    }

    private var legendColor: Color {
        lighting.legendColor(settledColor: style.legend).color
    }
}

private struct KeyboardStageApplicationTargetLabel: View {
    let application: KeyboardStageApplicationTarget
    let foregroundColor: Color
    let availableWidth: CGFloat

    @State private var icon: NSImage?

    var body: some View {
        HStack(spacing: max(6, availableWidth * 0.035)) {
            KeyboardStageApplicationIcon(
                image: icon,
                fallbackSystemImage: application.fallbackSystemImage,
                size: max(18, min(30, availableWidth * 0.12))
            )
            Text(verbatim: application.name)
                .font(.system(size: max(10, min(15, availableWidth * 0.055)), weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, max(8, availableWidth * 0.06))
        .task(id: application.bundleIdentifier) {
            icon = loadIcon(bundleIdentifier: application.bundleIdentifier)
        }
    }

    @MainActor
    private func loadIcon(bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier,
              let applicationURL = NSWorkspace.shared.urlForApplication(
                  withBundleIdentifier: bundleIdentifier
              )
        else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: applicationURL.path)
    }
}

private struct KeyboardStageApplicationIcon: View {
    let image: NSImage?
    let fallbackSystemImage: String
    let size: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSystemImage)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
