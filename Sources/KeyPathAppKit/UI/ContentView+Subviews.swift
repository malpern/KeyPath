import AppKit
import KeyPathCore
import SwiftUI

// MARK: - ContentView Subviews

struct ContentViewMainTab: View {
    @ObservedObject var stateController: MainAppStateController
    @ObservedObject var recordingCoordinator: RecordingCoordinator
    @ObservedObject var kanataManager: KanataViewModel
    @Binding var showSetupBanner: Bool
    @Binding var showingInstallationWizard: Bool
    let onInputRecord: () -> Void
    let onOutputRecord: () -> Void
    let onSave: () -> Void
    let onOpenSystemStatus: () -> Void
    let onShowMessage: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if FeatureFlags.allowOptionalWizard, showSetupBanner {
                SetupBanner {
                    showingInstallationWizard = true
                }
                .padding(.horizontal, 8)
            }
            // Header
            let hasLayeredCollections = kanataManager.ruleCollections.contains {
                $0.isEnabled && $0.targetLayer != .base
            }
            ContentViewHeader(
                validator: stateController, // 🎯 Phase 3: New controller
                showingInstallationWizard: $showingInstallationWizard,
                onWizardRequest: { showingInstallationWizard = true },
                layerIndicatorVisible: hasLayeredCollections,
                currentLayerName: kanataManager.currentLayerName
            )

            // Recording Section (no solid wrapper; let glass show through)
            RecordingSection(
                coordinator: recordingCoordinator,
                onInputRecord: onInputRecord,
                onOutputRecord: onOutputRecord,
                onShowMessage: onShowMessage
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 2)

            saveButtonSection

            // Emergency Stop Pause Card (similar to low battery pause)
            if kanataManager.emergencyStopActivated {
                EmergencyStopPauseCard(
                    onRestart: {
                        Task { @MainActor in
                            kanataManager.emergencyStopActivated = false
                            let restarted = await kanataManager.restartKanata(
                                reason: "Emergency stop recovery"
                            )
                            if !restarted {
                                onShowMessage("❌ Failed to restart Kanata after emergency stop")
                            }
                            await kanataManager.updateStatus()
                        }
                    }
                )
            }

            diagnosticSummarySection

            Spacer()
        }
    }

    @ViewBuilder
    private var saveButtonSection: some View {
        // Save button - only visible when input OR output has content
        if recordingCoordinator.capturedInputSequence() != nil
            || recordingCoordinator.capturedOutputSequence() != nil
        {
            HStack {
                Spacer()
                Button(
                    action: onSave,
                    label: {
                        HStack {
                            if kanataManager.saveStatus.isActive {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .frame(width: 16, height: 16)
                                Text(kanataManager.saveStatus.message)
                                    .font(.caption)
                            } else {
                                Text("Save")
                            }
                        }
                        .frame(minWidth: 100)
                    }
                )
                .buttonStyle(.borderedProminent)
                .focusable(false) // Prevent keyboard activation on main page
                .disabled(
                    recordingCoordinator.capturedInputSequence() == nil
                        || recordingCoordinator.capturedOutputSequence() == nil
                        || kanataManager.saveStatus.isActive
                )
                .accessibilityIdentifier("save-mapping-button")
                .accessibilityLabel("Save key mapping")
                .accessibilityHint("Save the input and output key mapping to your configuration")
            }
        }
    }

    @ViewBuilder
    private var diagnosticSummarySection: some View {
        // Diagnostic Summary (show critical issues)
        if !kanataManager.diagnostics.isEmpty {
            let criticalIssues = kanataManager.diagnostics.filter {
                $0.severity == .critical || $0.severity == .error
            }
            if !criticalIssues.isEmpty {
                DiagnosticSummaryView(criticalIssues: criticalIssues) {
                    onOpenSystemStatus()
                }
            }
        }
    }
}

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
                    Text("Kanata refused to load the generated config. KeyPath left the previous configuration in place until you fix the issues below.")
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
                    ForEach(Array(normalizedErrors.enumerated()), id: \.offset) { index, error in
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

            // AI Repair status messages
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

                // AI Repair button (only shown if API key is configured)
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

#Preview {
    let manager = RuntimeCoordinator()
    let viewModel = KanataViewModel(manager: manager)
    ContentView()
        .environmentObject(viewModel)
}
