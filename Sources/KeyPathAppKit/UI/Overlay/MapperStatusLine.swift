import SwiftUI

/// The overlay Mapper's one line of status. The overlay saves on capture and
/// has no Save button, so a refusal, a declined save or "✓ Saved" must be said
/// here; without it a declined mapping just seems to vanish.
struct MapperStatusLine: View {
    let message: String?
    let isError: Bool

    var body: some View {
        if let message {
            Text(message)
                .font(.caption)
                .foregroundStyle(isError ? Color.red : Color.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("overlay-mapper-status")
                .transition(.opacity)
        }
    }
}
