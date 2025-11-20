import SwiftUI

/// Dialog shown before starting the Kanata service, with emergency stop instructions
struct StartConfirmationDialog: View {
    @Binding var isPresented: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    // Don't dismiss on background tap - this is an important confirmation
                }

            // Dialog content
            VStack(spacing: 0) {
                // Header with icon
                VStack(spacing: 16) {
                    // App icon
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.blue.gradient)
                        .frame(width: 80, height: 80)
                        .overlay {
                            Image(systemName: "keyboard")
                                .font(.system(size: 36, weight: .medium))
                                .foregroundColor(.white)
                        }

                    Text("Ready to Start KeyPath")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text("KeyPath will now start the keyboard remapping service.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)
                .padding(.horizontal, 32)

                // Emergency stop section
                VStack(spacing: 20) {
                    Divider()
                        .padding(.horizontal, 32)

                    VStack(spacing: 16) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.shield")
                                .font(.title3)
                                .foregroundColor(.orange)

                            Text("Emergency Stop")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }

                        Text("If the keyboard becomes unresponsive, press:")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        // Visual keyboard keys
                        HStack(spacing: 12) {
                            KeyCapView(text: "⌃", label: "Ctrl")

                            Text("+")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            KeyCapView(text: "␣", label: "Space")

                            Text("+")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            KeyCapView(text: "⎋", label: "Esc")
                        }

                        Text("(Press all three keys at the same time)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()

                        Text(
                            "This will immediately stop the remapping service and restore normal keyboard function."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 32)
                }
                .padding(.vertical, 24)

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPresented = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onConfirm()
                        }
                    }, label: {
                        HStack {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .medium))
                            Text("Start KeyPath")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.blue.gradient)
                        .cornerRadius(12)
                    })
                    .buttonStyle(.plain)

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPresented = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onCancel()
                        }
                    }, label: {
                        Text("Cancel")
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    })
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .frame(width: 420)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            }
        }
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.8).combined(with: .opacity),
                removal: .scale(scale: 0.9).combined(with: .opacity)
            )
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isPresented)
    }
}

/// Visual representation of a keyboard key
struct KeyCapView: View {
    let text: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .foregroundColor(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
                .frame(width: 50, height: 44)
                .overlay(
                    Text(text)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                )
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

struct StartConfirmationDialog_Previews: PreviewProvider {
    static var previews: some View {
        StartConfirmationDialog(
            isPresented: .constant(true),
            onConfirm: {},
            onCancel: {}
        )
    }
}
