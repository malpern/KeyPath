import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

extension InstallationWizardView {
    // MARK: - UI Components

    // Header removed per design update; pages present their own centered titles.

    public func pageContent() -> some View {
        ZStack {
            switch stateMachine.currentPage {
            case .summary:
                WizardSummaryPage(
                    systemState: stateMachine.wizardState,
                    issues: stateMachine.wizardIssues,
                    stateInterpreter: stateInterpreter,
                    onStartService: startKeyPathRuntime,
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
                    onAutoFix: performAutoFix,
                    onRefresh: { refreshSystemState() },
                    kanataManager: kanataManager!
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
                    kanataManager: kanataManager!
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
                    kanataManager: kanataManager!
                )
            case .karabinerComponents:
                WizardKarabinerComponentsPage(
                    systemState: stateMachine.wizardState,
                    issues: stateMachine.wizardIssues,
                    isFixing: fixInFlight,
                    blockingFixDescription: currentFixDescriptionForUI,
                    onAutoFix: performAutoFix,
                    onRefresh: { refreshSystemState() },
                    kanataManager: kanataManager!
                )
            case .kanataMigration:
                if let factory = WizardDependencies.makeKanataMigrationPage {
                    factory(
                        { hasRunningKanata in
                            // After migration, check if we need to stop external kanata
                            if hasRunningKanata {
                                stateMachine.navigateToPage(.stopExternalKanata)
                            } else {
                                // No running kanata, continue to next step
                                refreshSystemState()
                                stateMachine.navigateToPage(.summary)
                            }
                        },
                        {
                            // Skip migration, continue to next step
                            refreshSystemState()
                            stateMachine.navigateToPage(.summary)
                        }
                    )
                } else {
                    EmptyView()
                }
            case .stopExternalKanata:
                WizardStopKanataPage(
                    onComplete: {
                        // After stopping, refresh state and continue
                        refreshSystemState()
                        stateMachine.navigateToPage(.summary)
                    },
                    onCancel: {
                        // User cancelled, go back to migration
                        stateMachine.navigateToPage(.kanataMigration)
                    }
                )
            case .karabinerImport:
                if let factory = WizardDependencies.makeKarabinerImportPage {
                    factory(
                        {
                            refreshSystemState()
                            stateMachine.nextPage()
                        },
                        {
                            refreshSystemState()
                            stateMachine.nextPage()
                        }
                    )
                } else {
                    EmptyView()
                }
            case .helper:
                WizardHelperPage(
                    systemState: stateMachine.wizardState,
                    issues: stateMachine.wizardIssues,
                    isFixing: fixInFlight,
                    blockingFixDescription: currentFixDescriptionForUI,
                    onAutoFix: performAutoFix,
                    onRefresh: { refreshSystemState() },
                    kanataManager: kanataManager!
                )
            case .communication:
                if let factory = WizardDependencies.makeCommunicationPage {
                    factory(
                        stateMachine.wizardState,
                        stateMachine.wizardIssues,
                        performAutoFix
                    )
                } else {
                    EmptyView()
                }
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

    public func operationProgressOverlay() -> some View {
        WizardOperationProgress(
            operationName: getCurrentOperationName(),
            progress: getCurrentOperationProgress(),
            isIndeterminate: isCurrentOperationIndeterminate()
        )
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}
