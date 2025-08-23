import SwiftUI

struct EmergencyStopDialog: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)

                Text("Emergency Stop")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("If Kanata stops responding or you need to disable all keyboard remapping immediately")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Divider()

            // Key combination explanation
            VStack(spacing: 20) {
                Text("Press these 3 keys simultaneously:")
                    .font(.headline)

                // Visual key representation
                HStack(spacing: 12) {
                    EmergencyStopKeyView(
                        keyLabel: "Left Control",
                        keySymbol: "⌃",
                        description: "Left Control key\n(bottom-left corner)"
                    )

                    Text("+")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    EmergencyStopKeyView(
                        keyLabel: "Space",
                        keySymbol: "⎵",
                        description: "Space bar\n(bottom center)"
                    )

                    Text("+")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    EmergencyStopKeyView(
                        keyLabel: "Escape",
                        keySymbol: "⎋",
                        description: "Escape key\n(top-left corner)"
                    )
                }

                // Sequence explanation
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Hold all three keys at the same time")
                            .font(.subheadline)
                        Spacer()
                    }

                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Kanata will immediately stop all remapping")
                            .font(.subheadline)
                        Spacer()
                    }

                    HStack {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundColor(.orange)
                        Text("Restart KeyPath to re-enable remapping")
                            .font(.subheadline)
                        Spacer()
                    }
                }
                .padding(.horizontal)
            }

            Divider()

            // Safety note
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "shield.fill")
                        .foregroundColor(.blue)
                    Text("Safety Feature")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }

                Text("This emergency stop works even when Kanata is completely frozen or unresponsive. It's built into the keyboard monitoring system itself.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)

            // OK button
            HStack {
                Spacer()
                Button("OK") {
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 540)
        .background(.regularMaterial)
    }
}

struct EmergencyStopKeyView: View {
    let keyLabel: String
    let keySymbol: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            // Key cap
            VStack(spacing: 4) {
                Text(keySymbol)
                    .font(.title)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text(keyLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .frame(width: 80, height: 60)
            .background(.quaternary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.tertiary, lineWidth: 1)
            )

            // Description
            Text(description)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
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
