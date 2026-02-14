import AppKit
import SwiftUI

/// Minimal main-window surface. KeyPath’s primary UI is the live overlay.
struct SplashView: View {
    private var posterImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "keypath-poster-hor", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(nsImage: posterImage ?? NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 560)
                .padding(.horizontal, 28)
                .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
                .accessibilityIdentifier("main-window-splash-poster")

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
