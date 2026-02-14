import AppKit
import KeyPathCore
import SwiftUI

// MARK: - App Rule Row

/// A row displaying an app-specific rule override
struct AppRuleRow: View {
    let keymap: AppKeymap
    let override: AppKeyOverride
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Key mapping display
            HStack(spacing: 8) {
                KeyCapChip(text: override.inputKey.uppercased())

                Text("→")
                    .font(.caption)
                    .foregroundColor(.secondary)

                KeyCapChip(text: override.outputAction.uppercased())
            }

            Spacer()

            // Delete button
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("app-rule-delete-\(override.id)")
            .accessibilityLabel("Delete rule \(override.inputKey) to \(override.outputAction)")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("app-rule-row-\(override.id)")
    }
}
