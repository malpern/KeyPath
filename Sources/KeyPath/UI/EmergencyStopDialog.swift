import SwiftUI

struct EmergencyStopDialog: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.orange)

                Text("Emergency Stop")
                    .font(.system(size: 32, weight: .bold))

                Text("For Kanata (the keyboard remapper) the emergency stop shortcut is Left Control + Space + Escape (using their physical key positions, not after any remapping).")
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Divider()

            // Big visual key buttons
            VStack(spacing: 24) {
                Text("Press these 3 keys simultaneously:")
                    .font(.title3)
                    .fontWeight(.semibold)

                HStack(spacing: 24) {
                    EmergencyStopKeyButton(
                        keyLabel: "Left Control",
                        keySymbol: "⌃",
                        description: "Bottom-left corner"
                    )

                    Text("+")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.vertical)

                    EmergencyStopKeyButton(
                        keyLabel: "Space",
                        keySymbol: "⎵",
                        description: "Bottom center"
                    )

                    Text("+")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.vertical)

                    EmergencyStopKeyButton(
                        keyLabel: "Escape",
                        keySymbol: "⎋",
                        description: "Top-left corner"
                    )
                }

                // Important note
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                        Text("Important: Use physical key positions, not after any remapping")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.green)
                        Text("Kanata will immediately stop all remapping")
                            .font(.body)
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.title3)
                            .foregroundColor(.orange)
                        Text("Restart KeyPath to re-enable remapping")
                            .font(.body)
                        Spacer()
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }

            // OK button
            Button(action: {
                dismiss()
            }) {
                Text("Got it")
                    .font(.headline)
                    .frame(minWidth: 200)
                    .padding(.vertical, 12)
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 700)
        .background(.regularMaterial)
    }
}

struct EmergencyStopKeyButton: View {
    let keyLabel: String
    let keySymbol: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            // Large key cap
            VStack(spacing: 8) {
                Text(keySymbol)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(.primary)

                Text(keyLabel)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .frame(width: 140, height: 100)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.secondary, lineWidth: 2)
            )

            // Description
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// Preview
#Preview {
    EmergencyStopDialog()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    EmergencyStopDialog()
        .preferredColorScheme(.dark)
}
