import KeyPathCore
import SwiftUI

/// Consolidates the 5 dialog/sheet/alert presentations from LiveKeyboardOverlayView's body.
struct OverlayDialogsModifier: ViewModifier {
    @Binding var pendingDeleteRule: (keymap: AppKeymap, override: AppKeyOverride)?
    @Binding var appRuleDeleteError: String?
    @Binding var showingRuntimeStoppedAlert: Bool
    @Binding var showingValidationFailureModal: Bool
    @Binding var validationFailureErrors: [String]
    @Binding var showResetAllRulesConfirmation: Bool
    let onDeleteAppRule: (AppKeymap, AppKeyOverride) -> Void
    let onRestartRuntime: () -> Void
    let onCopyValidationErrors: () -> Void
    let onOpenConfig: () -> Void
    let onOpenDiagnostics: () -> Void
    let onResetAllRules: () -> Void
    let configPath: String

    func body(content: Content) -> some View {
        content
            // Confirmation dialog for deleting app rules
            .confirmationDialog(
                "Delete Rule?",
                isPresented: Binding(
                    get: { pendingDeleteRule != nil },
                    set: { if !$0 { pendingDeleteRule = nil } }
                ),
                titleVisibility: .visible,
                actions: {
                    if let pending = pendingDeleteRule {
                        Button("Delete", role: .destructive) {
                            onDeleteAppRule(pending.keymap, pending.override)
                            pendingDeleteRule = nil
                        }
                        .accessibilityIdentifier("overlay-delete-app-rule-confirm-button")
                        Button("Cancel", role: .cancel) {
                            pendingDeleteRule = nil
                        }
                        .accessibilityIdentifier("overlay-delete-app-rule-cancel-button")
                    }
                },
                message: {
                    if let pending = pendingDeleteRule {
                        Text("Delete \(pending.override.inputKey) → \(pending.override.outputAction) for \(pending.keymap.mapping.displayName)?")
                    }
                }
            )
            // Error alert for failed deletions
            .alert(
                "Delete Failed",
                isPresented: Binding(
                    get: { appRuleDeleteError != nil },
                    set: { if !$0 { appRuleDeleteError = nil } }
                ),
                actions: {
                    Button("OK") {
                        appRuleDeleteError = nil
                    }
                },
                message: {
                    if let error = appRuleDeleteError {
                        Text(error)
                    }
                }
            )
            // Alert when the runtime stops unexpectedly
            .alert(
                "KeyPath Runtime Stopped",
                isPresented: $showingRuntimeStoppedAlert,
                actions: {
                    Button("Restart Runtime") {
                        showingRuntimeStoppedAlert = false
                        onRestartRuntime()
                    }
                    .accessibilityIdentifier("overlay-kanata-service-stopped-restart-button")
                    Button("Cancel", role: .cancel) {}
                        .accessibilityIdentifier("overlay-kanata-service-stopped-cancel-button")
                },
                message: {
                    Text("The remapping runtime stopped unexpectedly.")
                }
            )
            // Config validation failure sheet
            .sheet(isPresented: $showingValidationFailureModal, onDismiss: {
                validationFailureErrors = []
            }, content: {
                ValidationFailureDialog(
                    errors: validationFailureErrors,
                    configPath: configPath,
                    onCopyErrors: onCopyValidationErrors,
                    onOpenConfig: onOpenConfig,
                    onOpenDiagnostics: onOpenDiagnostics,
                    onDismiss: {
                        showingValidationFailureModal = false
                    },
                    onRepairWithAI: nil,
                    isRepairing: .constant(false),
                    repairError: nil,
                    backupPath: nil
                )
                .customizeSheetWindow()
            })
            // Confirmation dialog for resetting all custom rules
            .confirmationDialog(
                "Reset All Custom Rules?",
                isPresented: $showResetAllRulesConfirmation,
                titleVisibility: .visible,
                actions: {
                    Button("Reset All", role: .destructive) {
                        onResetAllRules()
                    }
                    .accessibilityIdentifier("overlay-reset-all-custom-rules-confirm-button")
                    Button("Cancel", role: .cancel) {}
                        .accessibilityIdentifier("overlay-reset-all-custom-rules-cancel-button")
                },
                message: {
                    Text("This will remove all custom rules (both global and app-specific). This action cannot be undone.")
                }
            )
    }
}
