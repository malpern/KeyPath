import SwiftUI

struct EmergencyStopDialog: View {
    @Environment(\.dismiss) private var dismiss
    let isActivated: Bool

    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: isActivated ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(isActivated ? .green : .orange)

                Text(isActivated ? "Emergency Stop Activated" : "Emergency Stop")
                    .font(.system(size: 32, weight: .bold))

                if isActivated {
                    Text(
                        "The emergency stop sequence was detected and Kanata has been stopped. Keyboard remapping is now paused."
                    )
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                } else {
                    Text(
                        "For Kanata (the keyboard remapper) the emergency stop shortcut is Left Control + Space + Escape (using their physical key positions, not after any remapping)."
                    )
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                }
            }

            Divider()

            if isActivated {
                // Activated state - show success message
                VStack(spacing: 24) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                        Text("Keyboard remapping has been safely stopped")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                        Text(
                            "You can restart the service when ready by clicking the restart button in the main window"
                        )
                        .font(.body)
                        Spacer()
                    }

                    // Visual key buttons (smaller when activated)
                    VStack(spacing: 16) {
                        Text("Emergency stop sequence used:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            EmergencyStopKeyButton(
                                keyLabel: "Left Control",
                                keySymbol: "⌃",
                                description: "Bottom-left",
                                isSmall: true
                            )

                            Text("+")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)

                            EmergencyStopKeyButton(
                                keyLabel: "Space",
                                keySymbol: "⎵",
                                description: "Bottom center",
                                isSmall: true
                            )

                            Text("+")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)

                            EmergencyStopKeyButton(
                                keyLabel: "Escape",
                                keySymbol: "⎋",
                                description: "Top-left",
                                isSmall: true
                            )
                        }
                    }
                }
            } else {
                // Instructions state - show how to use emergency stop
                // Big visual key buttons
                VStack(spacing: 24) {
                    Text("Press these 3 keys simultaneously:")
                        .font(.title3)
                        .fontWeight(.semibold)

                    HStack(spacing: 24) {
                        EmergencyStopKeyButton(
                            keyLabel: "Left Control",
                            keySymbol: "⌃",
                            description: "Bottom-left corner",
                            isSmall: false
                        )

                        Text("+")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.vertical)

                        EmergencyStopKeyButton(
                            keyLabel: "Space",
                            keySymbol: "⎵",
                            description: "Bottom center",
                            isSmall: false
                        )

                        Text("+")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.vertical)

                        EmergencyStopKeyButton(
                            keyLabel: "Escape",
                            keySymbol: "⎋",
                            description: "Top-left corner",
                            isSmall: false
                        )
                    }

                    // Important note
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                            Text("Important: Use physical key positions, not after any remapping")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                        }

                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.green)
                            Text("Kanata will immediately stop all remapping")
                                .font(.body)
                            Spacer()
                        }

                        HStack(spacing: 12) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                            Text("Restart KeyPath to re-enable remapping")
                                .font(.body)
                            Spacer()
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 12))
                }
            }

            // OK button
            Button(
                action: {
                    dismiss()
                },
                label: {
                    Text("Got it")
                        .font(.headline)
                        .frame(minWidth: 200)
                        .padding(.vertical, 12)
                }
            )
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .frame(minWidth: 700, maxWidth: 700, minHeight: 650)
        .background(.regularMaterial)
    }
}

struct EmergencyStopKeyButton: View {
    let keyLabel: String
    let keySymbol: String
    let description: String
    let isSmall: Bool

    var body: some View {
        VStack(spacing: isSmall ? 6 : 12) {
            // Large key cap
            VStack(spacing: isSmall ? 4 : 8) {
                Text(keySymbol)
                    .font(.system(size: isSmall ? 32 : 48, weight: .medium))
                    .foregroundStyle(.primary)

                Text(keyLabel)
                    .font(isSmall ? .subheadline : .headline)
                    .foregroundStyle(.primary)
            }
            .frame(width: isSmall ? 100 : 140, height: isSmall ? 70 : 100)
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
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// Preview
#Preview {
    EmergencyStopDialog(isActivated: false)
        .preferredColorScheme(.light)
}

#Preview("Activated") {
    EmergencyStopDialog(isActivated: true)
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    EmergencyStopDialog(isActivated: false)
        .preferredColorScheme(.dark)
}
