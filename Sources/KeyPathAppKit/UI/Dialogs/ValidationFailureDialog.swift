import SwiftUI

struct ValidationFailureDialog: View {
    let errors: [String]
    let configPath: String
    let onCopyErrors: () -> Void
    let onOpenConfig: () -> Void
    let onOpenDiagnostics: () -> Void
    let onDismiss: () -> Void

    // AI Repair support
    let onRepairWithAI: (() -> Void)?
    @Binding var isRepairing: Bool
    var repairError: String?
    var backupPath: String?

    private var normalizedErrors: [String] {
        errors.isEmpty
            ? ["Kanata returned an unknown validation error."]
            : errors
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Configuration Validation Failed")
                        .font(.title2.weight(.semibold))
                    Text(
                        "Kanata refused to load the generated config. KeyPath left the previous configuration in place until you fix the issues below."
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(normalizedErrors.indices, id: \.self) { index in
                        let error = normalizedErrors[index]
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.body.bold())
                                .foregroundStyle(.secondary)
                            Text(error)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 180, maxHeight: 260)

            if let repairError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Repair Failed")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(repairError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
            }

            if let backupPath {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Original Config Backed Up")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(backupPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.green.opacity(0.3), lineWidth: 1)
                        )
                )
            }

            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(configPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Spacer()
            }

            Divider()

            HStack(spacing: 12) {
                Button("Copy Errors") {
                    onCopyErrors()
                }
                .accessibilityIdentifier("validation-copy-errors-button")
                .accessibilityLabel("Copy Errors")

                Button("Open Config in Zed") {
                    onOpenConfig()
                }
                .accessibilityIdentifier("validation-open-config-button")
                .accessibilityLabel("Open Config in Zed")

                if let onRepairWithAI {
                    Button {
                        onRepairWithAI()
                    } label: {
                        if isRepairing {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Repairing...")
                            }
                        } else {
                            Label("Repair with AI", systemImage: "wand.and.stars")
                        }
                    }
                    .disabled(isRepairing)
                    .help("Uses Claude AI to fix config errors. Your original config is backed up first.")
                    .accessibilityIdentifier("validation-ai-repair-button")
                    .accessibilityLabel("Repair with AI")
                }

                Spacer()

                Button("Diagnostics") {
                    onOpenDiagnostics()
                }
                .accessibilityIdentifier("validation-diagnostics-button")
                .accessibilityLabel("View Diagnostics")

                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("validation-done-button")
                .accessibilityLabel("Done")
            }
        }
        .frame(minWidth: 520, idealWidth: 580, maxWidth: 640)
        .padding(24)
    }
}

#Preview("ValidationFailureDialog") {
    ValidationFailureDialog(
        errors: [
            "Line 12: expected ')'",
            "Line 34: unknown key 'foo_bar'"
        ],
        configPath: "/Users/example/.config/kanata/kanata.kbd",
        onCopyErrors: {},
        onOpenConfig: {},
        onOpenDiagnostics: {},
        onDismiss: {},
        onRepairWithAI: {},
        isRepairing: .constant(false),
        repairError: nil,
        backupPath: "/Users/example/.config/kanata/kanata.kbd.backup"
    )
    .customizeSheetWindow()
}
