import SwiftUI

struct KarabinerConflictStep: View {
    @State private var isKarabinerRunning = false
    @State private var hasChecked = false
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: isKarabinerRunning ? "exclamationmark.triangle.fill" :
                  hasChecked ? "checkmark.circle.fill" : "magnifyingglass")
                .font(.system(size: 80))
                .foregroundColor(isKarabinerRunning ? .orange :
                               hasChecked ? .green : .blue)
                .symbolEffect(.pulse, isActive: isChecking)

            Text(isKarabinerRunning ? "Karabiner-Elements Detected" :
                 hasChecked ? "No Conflicts Found" : "Checking for Conflicts")
                .font(.system(.title, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)

            if isChecking {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Scanning for keyboard software conflicts...")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else if isKarabinerRunning {
                VStack(spacing: 16) {
                    Text("Karabiner-Elements is currently running and will conflict with Kanata.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("To use KeyPath, please:")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        HStack(alignment: .top, spacing: 12) {
                            Text("1.")
                                .fontWeight(.medium)
                            Text("Quit Karabiner-Elements from the menu bar")
                        }

                        HStack(alignment: .top, spacing: 12) {
                            Text("2.")
                                .fontWeight(.medium)
                            Text("Click \"Check Again\" below")
                        }

                        HStack(alignment: .top, spacing: 12) {
                            Text("3.")
                                .fontWeight(.medium)
                            Text("You can re-enable Karabiner after using KeyPath")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                    .background(.orange.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)

                    Button("Check Again") {
                        checkForKarabiner()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else if hasChecked {
                VStack(spacing: 12) {
                    Text("Great! No conflicting keyboard software detected.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("KeyPath can safely manage your keyboard remappings")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 40)
                }
            }

            Spacer()
        }
        .padding(.vertical, 20)
        .onAppear {
            if !hasChecked {
                checkForKarabiner()
            }
        }
    }

    private func checkForKarabiner() {
        isChecking = true

        DispatchQueue.global(qos: .userInitiated).async {
            let installer = KanataInstaller()
            let karabinerDetected = installer.isKarabinerRunning()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.isChecking = false
                self.isKarabinerRunning = karabinerDetected
                self.hasChecked = true
            }
        }
    }
}
