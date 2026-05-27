import AppKit
import KeyPathCore
import SwiftUI

struct LauncherModeKeycap: View {
    let keyCode: UInt16
    let baseLabel: String
    let holdLabel: String?
    let scale: CGFloat
    let fadeAmount: CGFloat
    let foregroundColor: Color
    let launcherMapping: LauncherMapping?
    let appIcon: NSImage?
    let faviconImage: NSImage?
    let launcherTransition: CGFloat
    let iconVisible: Bool

    private var keyLabel: String {
        if keyCode == 57 { return "✦" }
        return holdLabel ?? baseLabel
    }

    private var resolvedIcon: NSImage? {
        appIcon ?? faviconImage
    }

    private var fadeFactor: CGFloat {
        1 - fadeAmount * 0.7
    }

    var body: some View {
        let labelFontSize = lerp(from: 11, to: 8, progress: launcherTransition) * scale
        let labelOpacity = lerp(from: 0.85, to: 0.55, progress: launcherTransition)
        let labelOffsetX = lerp(from: 0, to: 10, progress: launcherTransition) * scale
        let labelOffsetY = lerp(from: 0, to: -10, progress: launcherTransition) * scale

        if let mapping = launcherMapping {
            ZStack(alignment: .topTrailing) {
                if iconVisible {
                    if let icon = resolvedIcon {
                        ZStack(alignment: .bottomTrailing) {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 22 * scale, height: 22 * scale)
                                .clipShape(RoundedRectangle(cornerRadius: 4 * scale))

                            if !mapping.action.isLaunchApp {
                                linkBadge(size: 6 * scale)
                            }
                        }
                        .scaleEffect(iconVisible ? 1.0 : 0.3)
                        .opacity((iconVisible ? 1.0 : 0) * fadeFactor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Image(systemName: fallbackSymbol(for: mapping))
                            .font(.system(size: 14 * scale))
                            .foregroundStyle(foregroundColor.opacity(0.6))
                            .scaleEffect(iconVisible ? 1.0 : 0.3)
                            .opacity((iconVisible ? 1.0 : 0) * fadeFactor)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                if iconVisible {
                    Text(keyLabel.uppercased())
                        .font(.system(size: 7 * scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.5 * fadeFactor))
                        .padding(2.5 * scale)
                } else {
                    Text(keyLabel.uppercased())
                        .font(.system(size: labelFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(labelOpacity * fadeFactor))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .help(mapping.tooltip)
        } else {
            ZStack {
                Text(keyLabel.uppercased())
                    .font(.system(size: labelFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(lerp(from: 0.85, to: 0.4, progress: launcherTransition) * fadeFactor))
                    .offset(x: labelOffsetX, y: labelOffsetY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func lerp(from: CGFloat, to: CGFloat, progress: CGFloat) -> CGFloat {
        from + (to - from) * progress
    }

    private func linkBadge(size: CGFloat) -> some View {
        Image(systemName: "link")
            .font(.system(size: size * 1.2, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 1, y: 0.5)
            .offset(x: size * 0.3, y: size * 0.3)
    }

    private func fallbackSymbol(for mapping: LauncherMapping) -> String {
        if case let .systemAction(id) = mapping.action, id == "window-snapping" {
            return "rectangle.split.2x2"
        }
        return mapping.action.isLaunchApp ? "app.fill" : "globe"
    }
}
