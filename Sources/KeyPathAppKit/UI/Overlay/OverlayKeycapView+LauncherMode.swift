import AppKit
import KeyPathCore
import SwiftUI

extension OverlayKeycapView {
    /// Label to display in launcher mode
    var launcherKeyLabel: String {
        if key.keyCode == 57 {
            return "✦"
        }
        return holdLabel ?? baseLabel
    }

    /// Content for launcher mode: app icon centered, key letter in top-left corner
    @ViewBuilder
    var launcherModeContent: some View {
        let labelFontSize = lerp(from: 11, to: 8, progress: launcherTransition) * scale
        let labelOpacity = lerp(from: 0.85, to: 0.55, progress: launcherTransition)
        let labelOffsetX = lerp(from: 0, to: -10, progress: launcherTransition) * scale
        let labelOffsetY = lerp(from: 0, to: -10, progress: launcherTransition) * scale
        let fadeFactor = 1 - fadeAmount * 0.7

        if let mapping = launcherMapping {
            ZStack {
                if iconVisible {
                    if let icon = launcherAppIcon {
                        ZStack(alignment: .bottomTrailing) {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20 * scale, height: 20 * scale)
                                .clipShape(RoundedRectangle(cornerRadius: 4 * scale))

                            if !mapping.target.isApp {
                                launcherLinkBadge(size: 6 * scale)
                            }
                        }
                        .scaleEffect(iconVisible ? 1.0 : 0.3)
                        .opacity((iconVisible ? 1.0 : 0) * fadeFactor)
                        .offset(x: 2 * scale)
                    } else {
                        Image(systemName: mapping.target.isApp ? "app.fill" : "globe")
                            .font(.system(size: 14 * scale))
                            .foregroundStyle(foregroundColor.opacity(0.6))
                            .scaleEffect(iconVisible ? 1.0 : 0.3)
                            .opacity((iconVisible ? 1.0 : 0) * fadeFactor)
                            .offset(x: 2 * scale)
                    }
                }

                Text(launcherKeyLabel.uppercased())
                    .font(.system(size: labelFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(labelOpacity * fadeFactor))
                    .offset(x: labelOffsetX, y: labelOffsetY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                Text(launcherKeyLabel.uppercased())
                    .font(.system(size: labelFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(lerp(from: 0.85, to: 0.4, progress: launcherTransition) * fadeFactor))
                    .offset(x: labelOffsetX, y: labelOffsetY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Linear interpolation helper
    func lerp(from: CGFloat, to: CGFloat, progress: CGFloat) -> CGFloat {
        from + (to - from) * progress
    }

    func launcherLinkBadge(size: CGFloat) -> some View {
        Image(systemName: "link")
            .font(.system(size: size * 1.2, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 1, y: 0.5)
            .offset(x: size * 0.3, y: size * 0.3)
    }

    var launcherAppIcon: NSImage? {
        appIcon ?? faviconImage
    }
}
