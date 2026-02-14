import AppKit
import SwiftUI

/// Minimal main-window surface. KeyPath’s primary UI is the live overlay.
struct SplashView: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 156, height: 156)
                .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)

            Text("KeyPath")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .tracking(0.2)

            Spacer()

            // Keep the surface minimal; primary controls live in the menu bar + Settings.
            Text("Live keyboard overlay is running.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .opacity(0.85)

            Spacer().frame(height: 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("main-window-splash")
    }
}
