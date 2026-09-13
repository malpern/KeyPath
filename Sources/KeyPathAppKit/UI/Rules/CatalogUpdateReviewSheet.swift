import SwiftUI

/// Explicit review for catalog changes. Nothing is selected initially: keeping
/// the local rule is the default, and only collision-free candidates can be
/// applied from this sheet.
struct CatalogUpdateReviewSheet: View {
    let previews: [CatalogUpdatePreview]
    let onApply: (Set<UUID>) async -> CatalogUpdateApplicationResult

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<UUID> = []
    @State private var isApplying = false
    @State private var feedback: String?

    private var selectableIDs: Set<UUID> {
        Set(previews.filter(\.canApply).map(\.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Catalog Updates")
                .font(.title2.weight(.semibold))

            Text("Your local rules stay in place unless you select an update. Applying an update creates a restorable backup first.")
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(previews) { preview in
                        updateRow(preview)
                    }
                }
            }
            .frame(minHeight: 160, maxHeight: 360)

            if let feedback {
                Text(feedback)
                    .font(.callout)
                    .foregroundColor(feedback.hasPrefix("Could not") ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Keep Mine") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("catalog-update-keep-mine-button")

                Spacer()

                Button("Apply Catalog Update") {
                    applySelectedUpdates()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIDs.isEmpty || isApplying)
                .accessibilityIdentifier("catalog-update-apply-button")
            }
        }
        .padding(24)
        .frame(width: 580)
    }

    private func updateRow(_ preview: CatalogUpdatePreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: selectionBinding(for: preview)) {
                Text(preview.existing.name)
                    .font(.headline)
            }
            .disabled(!preview.canApply || isApplying)
            .accessibilityIdentifier("catalog-update-select-\(preview.id)")
            .accessibilityLabel("Apply catalog update for \(preview.existing.name)")

            if !preview.affectedKeys.isEmpty {
                Text("Affected keys: \(preview.affectedKeys.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text("Affected layers: \(preview.affectedLayers.joined(separator: ", "))")
                .font(.caption)
                .foregroundColor(.secondary)

            if preview.isPackManaged {
                Label("Managed by its pack; update it through the pack.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else if let conflict = preview.conflictDescription {
                Label("Keep Mine required: \(conflict)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Collision-free merge: your supported settings are retained.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    private func selectionBinding(for preview: CatalogUpdatePreview) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(preview.id) },
            set: { selected in
                if selected { selectedIDs.insert(preview.id) }
                else { selectedIDs.remove(preview.id) }
            }
        )
    }

    private func applySelectedUpdates() {
        let ids = selectedIDs.intersection(selectableIDs)
        guard !ids.isEmpty else { return }
        isApplying = true
        feedback = nil
        Task {
            let result = await onApply(ids)
            await MainActor.run {
                isApplying = false
                guard result.saveResult.success else {
                    feedback = CatalogUpdateFeedback.failureMessage(for: result.saveResult)
                    return
                }
                let disposition = switch result.saveResult.reloadResult?.disposition {
                case .applied: "Applied and running."
                case .pending: "Saved; it will apply when the engine is available."
                case .rejected: "The engine rejected the update; your prior rules were restored."
                case .failed: "The engine could not apply the update; your prior rules were restored."
                case nil: "Saved."
                }
                let backup = result.backupPath.map { " Backup: \($0)" } ?? ""
                feedback = "\(disposition)\(backup)"
                selectedIDs = []
            }
        }
    }
}

enum CatalogUpdateFeedback {
    static func failureMessage(for result: SaveResult) -> String {
        switch result.recoveryResult {
        case let .restoredPreviousRuleState(reloadResult):
            "The catalog update was not accepted. Your previous rules were restored.\(runtimeRecoveryMessage(reloadResult))"
        case .ruleStateRecoveryFailed:
            "The catalog update was not accepted, and restoring your previous rules also failed. Please review your configuration and backup."
        default:
            "Could not apply the catalog update: \(result.error?.localizedDescription ?? "Unknown error")"
        }
    }

    private static func runtimeRecoveryMessage(_ result: ReloadResult?) -> String {
        switch result?.disposition {
        case .applied: " The restored rules are running."
        case .pending: " The restored rules are saved and will apply when the engine is available."
        case .rejected: " The engine rejected the restored rules."
        case .failed: " The restored rules could not be applied to the engine."
        case nil: ""
        }
    }
}
