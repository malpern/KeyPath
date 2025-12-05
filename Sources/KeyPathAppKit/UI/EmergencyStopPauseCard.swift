import SwiftUI

/// Pause card shown in main UI when emergency stop is activated
struct EmergencyStopPauseCard: View {
    let onRestart: () -> Void
    @State private var isRestarting = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 48, height: 48)

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text("Emergency Stop Activated")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(
                        "Keyboard remapping has been paused for safety. Press the restart button below to resume."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Restart button
                Button(
                    action: {
                        isRestarting = true
                        Task { @MainActor in
                            onRestart()
                            try await Task.sleep(for: .seconds(1))
                            isRestarting = false
                        }
                    },
                    label: {
                        HStack(spacing: 8) {
                            if isRestarting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "play.circle.fill")
                                    .font(.title3)
                            }
                            Text(isRestarting ? "Restarting..." : "Restart Service")
                                .font(.headline)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(8)
                    }
                )
                .buttonStyle(.plain)
                .disabled(isRestarting)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                )
        )
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    EmergencyStopPauseCard(onRestart: {})
        .padding()
        .preferredColorScheme(.light)
}
