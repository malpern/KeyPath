import AppKit
import SwiftUI

/// App icon grid for the Context HUD launcher layer
struct ContextHUDLauncherView: View {
    let entries: [HUDKeyEntry]

    private let columns = [
        GridItem(.adaptive(minimum: 52, maximum: 64), spacing: 8),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(entries) { entry in
                LauncherIconCell(entry: entry)
            }
        }
        .accessibilityLabel("App launcher")
    }
}

/// A single app icon cell in the launcher grid
private struct LauncherIconCell: View {
    let entry: HUDKeyEntry

    var body: some View {
        VStack(spacing: 3) {
            // App icon or SF Symbol
            iconView
                .frame(width: 32, height: 32)

            // Keycap label
            Text(entry.keycap)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(width: 52)
    }

    @ViewBuilder
    private var iconView: some View {
        if let appIdentifier = entry.appIdentifier,
           let icon = IconResolverService.shared.resolveAppIcon(for: appIdentifier)
        {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else if let sfSymbol = entry.sfSymbol {
            Image(systemName: sfSymbol)
                .font(.system(size: 20))
                .foregroundStyle(.cyan)
        } else {
            // Fallback: show action text
            Text(String(entry.action.prefix(3)))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.cyan.opacity(0.8))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.cyan.opacity(0.15))
                )
        }
    }
}
