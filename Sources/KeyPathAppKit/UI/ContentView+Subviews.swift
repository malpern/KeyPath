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

// ValidationFailureDialog moved to UI/Dialogs/ValidationFailureDialog.swift
