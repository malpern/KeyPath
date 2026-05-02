import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

extension InstallationWizardView {
    // MARK: - UI Components

    // Header removed per design update; pages present their own centered titles.

    public func pageContent() -> some View {
        ZStack {
            pageContentInner()
        }
        // Directional page transition based on navigation direction
        .transition(
            stateMachine.isNavigatingForward
                ? WizardDesign.Transition.pageSlideForward
                : WizardDesign.Transition.pageSlideBackward
        )
    }

    @ViewBuilder
    private func pageContentInner() -> some View {
        switch stateMachine.currentPage {
        case .summary:
            WizardSummaryPage(
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
            WizardFullDiskAccessPage()
        case .conflicts:
            if let coordinator = kanataManager {
                WizardConflictsPage(
                    isFixing: fixInFlight,
                    onAutoFix: performAutoFix,
                    onRefresh: { refreshSystemState() },
                    kanataManager: coordinator
                )
            } else {
                unconfiguredView(page: "conflicts")
            }
        case .inputMonitoring:
            if let coordinator = kanataManager {
                WizardInputMonitoringPage(
                    onRefresh: { refreshSystemState() },
                    onNavigateToPage: { page in
                        stateMachine.navigateToPage(page)
                    },
                    onDismiss: {
                        dismissAndRefreshMainScreen()
                    },
                    kanataManager: coordinator
                )
            } else {
                unconfiguredView(page: "inputMonitoring")
            }
        case .accessibility:
            if let coordinator = kanataManager {
                WizardAccessibilityPage(
                    onRefresh: { refreshSystemState() },
                    onNavigateToPage: { page in
                        stateMachine.navigateToPage(page)
                    },
                    onDismiss: {
                        dismissAndRefreshMainScreen()
                    },
                    kanataManager: coordinator
                )
            } else {
                unconfiguredView(page: "accessibility")
            }
        case .karabinerComponents:
            if let coordinator = kanataManager {
                WizardKarabinerComponentsPage(
                    isFixing: fixInFlight,
                    blockingFixDescription: currentFixDescriptionForUI,
                    onAutoFix: performAutoFix,
                    onRefresh: { refreshSystemState() },
                    kanataManager: coordinator
                )
            } else {
                unconfiguredView(page: "karabinerComponents")
            }
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
            if let coordinator = kanataManager {
                WizardHelperPage(
                    isFixing: fixInFlight,
                    blockingFixDescription: currentFixDescriptionForUI,
                    onAutoFix: performAutoFix,
                    onRefresh: { refreshSystemState() },
                    kanataManager: coordinator
                )
            } else {
                unconfiguredView(page: "helper")
            }
        case .communication:
            if let factory = WizardDependencies.makeCommunicationPage {
                factory(
                    performAutoFix
                )
            } else {
                EmptyView()
            }
        case .service:
            WizardKanataServicePage(
                onRefresh: { refreshSystemState() }
            )
        }
    }

    @ViewBuilder
    private func unconfiguredView(page: String) -> some View {
        VStack(spacing: 8) {
            Text("Wizard not fully configured")
                .font(.headline)
            Text("RuntimeCoordinator is unavailable for page: \(page)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            AppLogger.shared.log("⚠️ [Wizard] kanataManager not configured for page: \(page)")
        }
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
