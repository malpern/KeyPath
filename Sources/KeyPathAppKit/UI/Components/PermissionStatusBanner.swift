import SwiftUI

// MARK: - Permission Status Banner

/// Shows a warning banner if Accessibility permission is not granted
struct PermissionStatusBanner: View {
    @State private var hasPermission = WindowManager.shared.hasAccessibilityPermission

    var body: some View {
        if !hasPermission {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.body)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility Permission Required")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.primary)

                    Text("Enable in System Settings > Privacy & Security > Accessibility, then restart KeyPath.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("window-snapping-open-settings-button")
                .accessibilityLabel("Open accessibility settings")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
    }
}
