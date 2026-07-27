import SwiftUI

struct SwiftUIKeyboardStageView: View {
    let frame: KeyboardStagePresentedFrame

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
                    KeyboardStageSwiftUIKeySurface(
                        frame: projection.projectKey(key),
                        rotationRadians: key.rotationRadians,
                        style: palette.style(for: key.role),
                        opacity: key.opacity,
                        pressure: key.pressure,
                        glow: key.glow,
                        lighting: lighting.lighting(for: key)
                    )
                    .zIndex(0)
                }

                ForEach(scene.decorations) { decoration in
                    KeyboardStageSwiftUIDecorationSurface(
                        decoration: decoration,
                        frame: projection.projectDecoration(decoration),
                        style: palette.style(for: decoration.role),
                        lighting: lighting.lighting(for: decoration)
                    )
                    .zIndex(zIndex(for: decoration.kind))
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func zIndex(for kind: KeyboardStageDecoration.Kind) -> Double {
        switch kind {
        case .keyboardDeck:
            -1
        case .capsEcho:
            -0.5
        case .modifierToken,
             .launcherCandidateMarker,
             .applicationTarget,
             .launcherChoiceTarget,
             .handoffTarget:
            1
        }
    }
}

private struct KeyboardStageSwiftUIKeySurface: View {
    let frame: CGRect
    let rotationRadians: Float
    let style: KeyboardStageSurfaceStyle
    let opacity: Float
    let pressure: Float
    let glow: Float
    let lighting: KeyboardStageSurfaceLighting

    var body: some View {
        let cornerRadius = max(4, min(frame.width, frame.height) * 0.16)
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(style.fill.color)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        Color(red: 0.015, green: 0.018, blue: 0.026)
                            .opacity(Double(1 - lighting.illumination) * 0.88)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        style.accent.color.opacity(
                            Double(style.borderStrength)
                                * Double(0.18 + lighting.illumination * 0.82)
                        ),
                        lineWidth: 0.8 + CGFloat(style.borderStrength)
                    )
            }
            .shadow(
                color: style.glow.color.opacity(
                    min(1, Double(glow) * 0.48 + Double(lighting.transientGlow) * 0.42)
                ),
                radius: 6 + CGFloat(max(glow, lighting.transientGlow)) * 8
            )
            .shadow(
                color: Color(red: 0.18, green: 0.16, blue: 0.14)
                    .opacity(
                        (0.18 - Double(pressure) * 0.08)
                            * Double(lighting.shadowStrength)
                    ),
                radius: 5 - CGFloat(pressure) * 2,
                y: 4 - CGFloat(pressure) * 2
            )
            .frame(width: frame.width, height: frame.height)
            .rotationEffect(.radians(Double(rotationRadians)))
            .position(x: frame.midX, y: frame.midY)
            .opacity(Double(opacity))
    }
}

private struct KeyboardStageSwiftUIDecorationSurface: View {
    let decoration: KeyboardStageDecoration
    let frame: CGRect
    let style: KeyboardStageSurfaceStyle
    let lighting: KeyboardStageSurfaceLighting

    var body: some View {
        let cornerRadius = switch decoration.kind {
        case .keyboardDeck:
            min(frame.height * 0.075, 24)
        case .applicationTarget, .launcherChoiceTarget, .handoffTarget:
            min(frame.height * 0.34, 18)
        case .capsEcho:
            min(frame.width, frame.height) * 0.16
        case .modifierToken:
            min(frame.width, frame.height) * 0.3
        case .launcherCandidateMarker:
            min(frame.width, frame.height) * 0.5
        }

        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(style.fill.color)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        Color(red: 0.015, green: 0.018, blue: 0.026)
                            .opacity(Double(1 - lighting.illumination) * 0.88)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        style.accent.color.opacity(
                            Double(style.borderStrength)
                                * Double(0.18 + lighting.illumination * 0.82)
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: style.glow.color.opacity(
                    min(
                        1,
                        Double(decoration.glow) * 0.48
                            + Double(lighting.transientGlow) * 0.42
                    )
                ),
                radius: 7 + CGFloat(max(decoration.glow, lighting.transientGlow)) * 7
            )
            .shadow(
                color: Color(red: 0.18, green: 0.16, blue: 0.14)
                    .opacity(
                        (decoration.kind == .keyboardDeck ? 0.18 : 0.10)
                            * Double(lighting.shadowStrength)
                    ),
                radius: decoration.kind == .keyboardDeck ? 12 : 4,
                y: decoration.kind == .keyboardDeck ? 7 : 2
            )
            .frame(width: frame.width, height: frame.height)
            .rotationEffect(.radians(Double(decoration.rotationRadians)))
            .position(x: frame.midX, y: frame.midY)
            .opacity(Double(decoration.opacity))
    }
}
