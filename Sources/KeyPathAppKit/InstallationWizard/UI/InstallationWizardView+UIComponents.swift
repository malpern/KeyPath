import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

extension InstallationWizardView {
    // MARK: - UI Components

    // Header removed per design update; pages present their own centered titles.

    @ViewBuilder
    func pageContent() -> some View {
        ZStack {
            switch stateMachine.currentPage {
            case .summary:
                WizardSummaryPage(
                    systemState: stateMachine.wizardState,
                    issues: stateMachine.wizardIssues,
                    stateInterpreter: stateInterpreter,
                    onStartService: startKanataService,
                    onDismiss: { dismissAndRefreshMainScreen() },
                    onNavigateToPage: { page in
                        stateMachine.navigateToPage(page)
                    },
                    isValidating: isValidating,
                    showAllItems: $showAllSummaryItems,
                    navSequence: $navSequence
                )
            case .fullDiskAccess:
                WizardFullDiskAccessPage(
                    systemState: stateMachine.wizardState,
                    issues: stateMachine.wizardIssues
                )
            case .conflicts:
                WizardConflictsPage(
                    systemState: stateMachine.wizardState,
                    issues: stateMachine.wizardIssues.filter { $0.category == .conflicts },
                    allIssues: stateMachine.wizardIssues,
                    isFixing: fixInFlight,
                    onRefresh: { refreshSystemState() },
                    kanataManager: kanataManager
                )
            case .inputMonitoring:
                WizardInputMonitoringPage(
                    systemState: stateMachine.wizardState,
                    issues: stateMachine.wizardIssues.filter { $0.category == .permissions },
                    allIssues: stateMachine.wizardIssues,
                    stateInterpreter: stateInterpreter,
                    onRefresh: { refreshSystemState() },
                    onNavigateToPage: { page in
                        stateMachine.navigateToPage(page)
                    },
                    onDismiss: {
                        dismissAndRefreshMainScreen()
                    },
                    kanataManager: kanataManager
                )
            case .accessibility:
                WizardAccessibilityPage(
                    systemState: stateMachine.wizardState,
                    issues: stateMachine.wizardIssues.filter { $0.category == .permissions },
                    allIssues: stateMachine.wizardIssues,
                    onRefresh: { refreshSystemState() },
                    onNavigateToPage: { page in
                        stateMachine.navigateToPage(page)
                    },
                    onDismiss: {
                        dismissAndRefreshMainScreen()
                    },
                    kanataManager: kanataManager
                )
            case .karabinerComponents:
                WizardKarabinerComponentsPage(
                    systemState: stateMachine.wizardState,
                    issues: stateMachine.wizardIssues,
                    isFixing: fixInFlight,
                    blockingFixDescription: currentFixDescriptionForUI,
                    onAutoFix: performAutoFix,
                    onRefresh: { refreshSystemState() },
                    kanataManager: kanataManager
                )
            case .kanataComponents:
                WizardKanataComponentsPage(
                    systemState: stateMachine.wizardState,
                    issues: stateMachine.wizardIssues,
                    isFixing: fixInFlight,
                    blockingFixDescription: currentFixDescriptionForUI,
                    onAutoFix: performAutoFix,
                    onRefresh: { refreshSystemState() },
                    kanataManager: kanataManager
                )
            case .kanataMigration:
                WizardKanataMigrationPage(
                    onMigrationComplete: { hasRunningKanata in
                        // After migration, check if we need to stop external kanata
                        if hasRunningKanata {
                            stateMachine.navigateToPage(.stopExternalKanata)
                        } else {
                            // No running kanata, continue to next step
                            refreshSystemState()
                            if stateMachine.wizardIssues.contains(where: { $0.category == .installation && $0.identifier == .component(.kanataBinaryMissing) }) {
                                stateMachine.navigateToPage(.kanataComponents)
                            } else {
                                stateMachine.navigateToPage(.summary)
                            }
                        }
                    },
                    onSkip: {
                        // Skip migration, continue to next step
                        refreshSystemState()
                        stateMachine.navigateToPage(.summary)
                    }
                )
            case .stopExternalKanata:
                WizardStopKanataPage(
                    onComplete: {
                        // After stopping, refresh state and continue
                        refreshSystemState()
                        if stateMachine.wizardIssues.contains(where: { $0.category == .installation && $0.identifier == .component(.kanataBinaryMissing) }) {
                            stateMachine.navigateToPage(.kanataComponents)
                        } else {
                            stateMachine.navigateToPage(.summary)
                        }
                    },
                    onCancel: {
                        // User cancelled, go back to migration
                        stateMachine.navigateToPage(.kanataMigration)
                    }
                )
            case .helper:
                WizardHelperPage(
                    systemState: stateMachine.wizardState,
                    issues: stateMachine.wizardIssues,
                    isFixing: fixInFlight,
                    blockingFixDescription: currentFixDescriptionForUI,
                    onAutoFix: performAutoFix,
                    onRefresh: { refreshSystemState() },
                    kanataManager: kanataManager
                )
            case .communication:
                WizardCommunicationPage(
                    systemState: stateMachine.wizardState,
                    issues: stateMachine.wizardIssues,
                    onAutoFix: performAutoFix
                )
            case .service:
                WizardKanataServicePage(
                    systemState: stateMachine.wizardState,
                    issues: stateMachine.wizardIssues,
                    onRefresh: { refreshSystemState() }
                )
            }
        }
        // Directional page transition based on navigation direction
        .transition(
            stateMachine.isNavigatingForward
                ? WizardDesign.Transition.pageSlideForward
                : WizardDesign.Transition.pageSlideBackward
        )
    }

    @ViewBuilder
    func operationProgressOverlay() -> some View {
        let operationName = getCurrentOperationName()

        // Minimal overlay for system state detection - just progress indicator
        if operationName.contains("System State Detection") {
            ProgressView()
                .scaleEffect(1.0)
        } else {
            // Enhanced overlay with cancellation support
            VStack(spacing: 16) {
                WizardOperationProgress(
                    operationName: operationName,
                    progress: getCurrentOperationProgress(),
                    isIndeterminate: isCurrentOperationIndeterminate()
                )

                // No cancel button - use X in top-right instead
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

}
