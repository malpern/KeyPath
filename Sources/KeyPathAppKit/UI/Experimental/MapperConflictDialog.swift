import AppKit
import KeyPathCore
import SwiftUI

// MARK: - Mapper Conflict Dialog

struct MapperConflictDialog: View {
    let onKeepHold: () -> Void
    let onKeepTapDance: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("Behavior Conflict")
                .font(.headline)

            Text("Kanata cannot detect both hold and tap-count on the same key. You must choose one behavior.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Keep Hold") {
                    onKeepHold()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("mapper-conflict-keep-hold")

                Button("Keep Tap-Dance") {
                    onKeepTapDance()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("mapper-conflict-keep-tap-dance")

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("mapper-conflict-cancel")
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
