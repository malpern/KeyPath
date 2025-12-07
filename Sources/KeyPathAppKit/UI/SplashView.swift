import SwiftUI

/// Splash screen shown on app launch before transitioning to Create Rule dialog
struct SplashView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Poster image
            if let posterImage = NSImage(named: "keypath-poster") {
                Image(nsImage: posterImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 500)
            } else {
                // Fallback if image not found
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 80, weight: .ultraLight))
                    .foregroundStyle(.primary.opacity(0.6))

                Text("KeyPath")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Keyboard Remapping")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Subtle loading indicator
            ProgressView()
                .scaleEffect(0.8)
                .opacity(0.6)

            Spacer()
                .frame(height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
