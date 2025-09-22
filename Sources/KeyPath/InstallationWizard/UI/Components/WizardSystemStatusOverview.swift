import SwiftUI

/// Simplified system status overview component for the summary page
struct WizardSystemStatusOverview: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let stateInterpreter: WizardStateInterpreter
    let onNavigateToPage: ((WizardPage) -> Void)?
    // Authoritative signal for service status - ensures consistency with detail page
    let kanataIsRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WizardDesign.Spacing.itemGap) {
            ForEach(statusItems, id: \.id) { item in
                WizardStatusItem(
                    icon: item.icon,
                    title: item.title,
                    subtitle: item.subtitle,
                    status: item.status,
                    isNavigable: item.isNavigable,
                    action: item.isNavigable ? { onNavigateToPage?(item.targetPage) } : nil,
                    isFinalStatus: isFinalKeyPathStatus(item: item),
                    showInitialClock: shouldShowInitialClock(for: item)
                )
                .padding(.horizontal, WizardDesign.Spacing.cardPadding)
                .padding(.vertical, WizardDesign.Spacing.labelGap)
                .background(AppGlassBackground(style: .cardBold, cornerRadius: 10))

                // Show expanded details for failed items
                if item.status == .failed, !item.subItems.isEmpty {
                    VStack(alignment: .leading, spacing: WizardDesign.Spacing.labelGap) {
                        ForEach(item.subItems, id: \.id) { subItem in
                            HStack(spacing: WizardDesign.Spacing.iconGap) {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: WizardDesign.Spacing.indentation)

                                WizardStatusItem(
                                    icon: subItem.icon,
                                    title: subItem.title,
                                    subtitle: subItem.subtitle,
                                    status: subItem.status,
                                    isNavigable: subItem.isNavigable,
                                    action: subItem.isNavigable ? { onNavigateToPage?(subItem.targetPage) } : nil
                                )
                                .padding(.horizontal, WizardDesign.Spacing.cardPadding)
                                .padding(.vertical, WizardDesign.Spacing.labelGap)
                                .background(AppGlassBackground(style: .cardBold, cornerRadius: 8))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Animation Helpers

    private func isFinalKeyPathStatus(item: StatusItemModel) -> Bool {
        // The Communication Server is the final status that should get pulse animation when completed
        item.id == "communication-server" && item.status == .completed
    }

    private func shouldShowInitialClock(for item: StatusItemModel) -> Bool {
        // Show initial clock for all items except those that are truly not started
        // This creates the "all items start checking simultaneously" effect
        item.status == .completed || item.status == .failed
    }

    // MARK: - Status Items Creation

    private var statusItems: [StatusItemModel] {
        var items: [StatusItemModel] = []

        // 1. Full Disk Access (Optional but recommended)
        let hasFullDiskAccess = checkFullDiskAccess()
        let fullDiskAccessStatus: InstallationStatus = {
            if systemState == .initializing {
                return .notStarted
            }
            return hasFullDiskAccess ? .completed : .notStarted
        }()
        items.append(
            StatusItemModel(
                id: "full-disk-access",
                icon: "folder",
                title: "Full Disk Access (Optional)",
                status: fullDiskAccessStatus,
                isNavigable: true,
                targetPage: .fullDiskAccess
            ))

        // 2. System Conflicts
        let hasConflicts = issues.contains { $0.category == .conflicts }
        let conflictStatus: InstallationStatus = {
            if systemState == .initializing {
                return .notStarted
            }
            return hasConflicts ? .failed : .completed
        }()
        items.append(
            StatusItemModel(
                id: "conflicts",
                icon: "exclamationmark.triangle",
                title: "Resolve System Conflicts",
                status: conflictStatus,
                isNavigable: true,
                targetPage: .conflicts
            ))

        // 3. Input Monitoring Permission
        let inputMonitoringStatus = getInputMonitoringStatus()
        items.append(
            StatusItemModel(
                id: "input-monitoring",
                icon: "eye",
                title: "Input Monitoring Permission",
                status: inputMonitoringStatus,
                isNavigable: true,
                targetPage: .inputMonitoring
            ))

        // 4. Accessibility Permission
        let accessibilityStatus = getAccessibilityStatus()
        items.append(
            StatusItemModel(
                id: "accessibility",
                icon: "accessibility",
                title: "Accessibility Permission",
                status: accessibilityStatus,
                isNavigable: true,
                targetPage: .accessibility
            ))

        // 5. Karabiner Driver Setup
        let karabinerStatus = getKarabinerComponentsStatus()
        items.append(
            StatusItemModel(
                id: "karabiner-components",
                icon: "keyboard.macwindow",
                title: "Karabiner Driver Setup",
                status: karabinerStatus,
                isNavigable: true,
                targetPage: .karabinerComponents
            ))

        // Check dependency requirements for remaining items
        let prerequisitesMet = shouldShowDependentItems()

        // 6. Kanata Engine Setup (hidden if Karabiner Driver not completed)
        if prerequisitesMet.showKanataEngineItem {
            let kanataComponentsStatus = getKanataComponentsStatus()
            items.append(
                StatusItemModel(
                    id: "kanata-components",
                    icon: "cpu.fill",
                    title: "Kanata Engine Setup",
                    status: kanataComponentsStatus,
                    isNavigable: true,
                    targetPage: .kanataComponents
                ))
        }

        // 7. Start Keyboard Service (hidden if Kanata Engine Setup not completed)
        if prerequisitesMet.showServiceItem {
            let serviceStatus = getServiceStatus()
            let serviceNavigation = getServiceNavigationTarget()
            items.append(
                StatusItemModel(
                    id: "service",
                    icon: "gearshape.2",
                    title: "Start Keyboard Service",
                    subtitle: serviceStatus == .failed ? "Fix permissions to enable service" : nil,
                    status: serviceStatus,
                    isNavigable: true,
                    targetPage: serviceNavigation.page
                ))
        }

        // 8. Communication Server (hidden if dependencies not met)
        if prerequisitesMet.showCommunicationItem {
            let commServerStatus = getCommunicationServerStatus()
            items.append(
                StatusItemModel(
                    id: "communication-server",
                    icon: "network",
                    title: "Communication Server",
                    subtitle: commServerStatus == .notStarted && !kanataIsRunning ? "Kanata isn't running" : nil,
                    status: commServerStatus,
                    isNavigable: true,
                    targetPage: .communication
                ))
        }

        return items
    }

    // MARK: - Dependency Logic

    private struct DependencyVisibility {
        let showKanataEngineItem: Bool
        let showServiceItem: Bool
        let showCommunicationItem: Bool
    }

    private func shouldShowDependentItems() -> DependencyVisibility {
        // Prerequisites for Kanata Engine Setup:
        // - Karabiner Driver Setup must be completed (Kanata requires VirtualHID driver)
        let karabinerDriverCompleted = getKarabinerComponentsStatus() == .completed
        
        // Prerequisites for Service item:
        // - Kanata Engine Setup must be completed (not failed)
        let kanataEngineCompleted = getKanataComponentsStatus() == .completed
        
        // Prerequisites for Communication Server:
        // - Kanata Engine Setup must be completed AND
        // - Service must be available (either completed or at least not blocked)
        let serviceAvailable = kanataEngineCompleted // Service can only work if Kanata Engine is ready
        
        return DependencyVisibility(
            showKanataEngineItem: karabinerDriverCompleted,
            showServiceItem: kanataEngineCompleted,
            showCommunicationItem: kanataEngineCompleted && serviceAvailable
        )
    }

    // MARK: - Status Helpers

    private func checkFullDiskAccess() -> Bool {
        // Use the same non-invasive check as WizardFullDiskAccessPage to maintain consistency
        // This prevents automatic addition to System Preferences while giving accurate status

        let testPath = "\(NSHomeDirectory())/Library/Preferences/com.apple.finder.plist"

        if FileManager.default.isReadableFile(atPath: testPath) {
            // Try a very light read operation
            if let data = try? Data(contentsOf: URL(fileURLWithPath: testPath), options: .mappedIfSafe) {
                if data.count > 0 {
                    AppLogger.shared.log("🔐 [WizardSystemStatusOverview] FDA detected via non-invasive check")
                    return true
                }
            }
        }

        AppLogger.shared.log("🔐 [WizardSystemStatusOverview] FDA not detected (non-invasive check)")
        return false
    }

    private func getInputMonitoringStatus() -> InstallationStatus {
        // If system is still initializing, don't show completed status
        if systemState == .initializing {
            return .notStarted
        }

        let hasInputMonitoringIssues = issues.contains { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .keyPathInputMonitoring || permissionType == .kanataInputMonitoring
            }
            return false
        }
        return hasInputMonitoringIssues ? .failed : .completed
    }

    private func getAccessibilityStatus() -> InstallationStatus {
        // If system is still initializing, don't show completed status
        if systemState == .initializing {
            return .notStarted
        }

        let hasAccessibilityIssues = issues.contains { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .keyPathAccessibility || permissionType == .kanataAccessibility
            }
            return false
        }
        return hasAccessibilityIssues ? .failed : .completed
    }

    private func getKarabinerComponentsStatus() -> InstallationStatus {
        // Use centralized evaluator (single source of truth)
        return KarabinerComponentsStatusEvaluator.evaluate(
            systemState: systemState,
            issues: issues
        )
    }

    private func getKanataComponentsStatus() -> InstallationStatus {
        // If system is still initializing, don't show completed status
        if systemState == .initializing {
            return .notStarted
        }

        // Check for Kanata-related issues
        let hasKanataIssues = issues.contains { issue in
            if issue.category == .installation {
                switch issue.identifier {
                case .component(.kanataBinaryMissing),
                     .component(.kanataService),
                     .component(.orphanedKanataProcess):
                    return true
                default:
                    return false
                }
            }
            return false
        }

        return hasKanataIssues ? .failed : .completed
    }

    private func getCommunicationServerStatus() -> InstallationStatus {
        // If system is still initializing, don't show status
        if systemState == .initializing {
            return .notStarted
        }

        // NEW BEHAVIOR: If Kanata isn't running, show as not started (empty circle)
        guard kanataIsRunning else {
            return .notStarted
        }

        // Use comprehensive communication testing for accurate status
        // Note: This will be called synchronously, but SystemStatusChecker uses caching
        // so the comprehensive tests run by the shared instance will provide fast results

        // Check for communication server issues in the shared issues array first
        let hasCommServerIssues = issues.contains { issue in
            if case let .component(component) = issue.identifier {
                switch component {
                case .kanataUDPServer,
                     .communicationServerConfiguration, .communicationServerNotResponding,
                     .udpServerConfiguration, .udpServerNotResponding:
                    return true
                default:
                    return false
                }
            }
            return false
        }

        // If there are detected issues in the shared state, show as failed
        if hasCommServerIssues {
            return .failed
        }

        // Additional check: UDP server must be enabled in preferences
        let preferences = PreferencesService.shared
        guard preferences.udpServerEnabled else {
            return .failed // UDP disabled - needs setup
        }

        // If Kanata is running, UDP is enabled, and there are no detected communication issues
        // in the shared state, show as completed. The comprehensive testing results from
        // SystemStatusChecker will be reflected in the issues array.
        return .completed
    }

    private func getServiceStatus() -> InstallationStatus {
        // Use the shared service status evaluator (same logic as detail page)
        let processStatus = ServiceStatusEvaluator.evaluate(
            kanataIsRunning: kanataIsRunning,
            systemState: systemState,
            issues: issues
        )
        return ServiceStatusEvaluator.toInstallationStatus(processStatus, systemState: systemState)
    }

    private func getServiceNavigationTarget() -> (page: WizardPage, reason: String) {
        // When service fails, navigate to the most critical missing permission
        let hasInputMonitoringIssues = issues.contains { issue in
            if case let .permission(permission) = issue.identifier {
                return permission == .kanataInputMonitoring
            }
            return false
        }

        let hasAccessibilityIssues = issues.contains { issue in
            if case let .permission(permission) = issue.identifier {
                return permission == .kanataAccessibility
            }
            return false
        }

        // Navigate to the first blocking permission page
        if hasInputMonitoringIssues {
            return (.inputMonitoring, "Input Monitoring permission required")
        } else if hasAccessibilityIssues {
            return (.accessibility, "Accessibility permission required")
        } else {
            // Default to service page if no specific permission issue
            return (.service, "Check service status")
        }
    }
}

// MARK: - Status Item Model

private struct StatusItemModel {
    let id: String
    let icon: String
    let title: String
    let subtitle: String?
    let status: InstallationStatus
    let isNavigable: Bool
    let targetPage: WizardPage
    let subItems: [StatusItemModel]

    init(
        id: String,
        icon: String,
        title: String,
        subtitle: String? = nil,
        status: InstallationStatus,
        isNavigable: Bool = false,
        targetPage: WizardPage = .summary,
        subItems: [StatusItemModel] = []
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.isNavigable = isNavigable
        self.targetPage = targetPage
        self.subItems = subItems
    }
}

// MARK: - Preview

struct WizardSystemStatusOverview_Previews: PreviewProvider {
    static var previews: some View {
        WizardSystemStatusOverview(
            systemState: .conflictsDetected(conflicts: []),
            issues: [
                WizardIssue(
                    identifier: .conflict(.karabinerGrabberRunning(pid: 123)),
                    severity: .critical,
                    category: .conflicts,
                    title: "Karabiner Conflict",
                    description: "Test conflict",
                    autoFixAction: .terminateConflictingProcesses,
                    userAction: nil
                )
            ],
            stateInterpreter: WizardStateInterpreter(),
            onNavigateToPage: { _ in },
            kanataIsRunning: true // Show running in preview
        )
        .padding()
    }
}
