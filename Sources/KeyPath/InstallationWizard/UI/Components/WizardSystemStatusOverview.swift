import SwiftUI

/// Simplified system status overview component for the summary page
struct WizardSystemStatusOverview: View {
  let systemState: WizardSystemState
  let issues: [WizardIssue]
  let stateInterpreter: WizardStateInterpreter
  let onNavigateToPage: ((WizardPage) -> Void)?
  
  var body: some View {
    VStack(alignment: .leading, spacing: WizardDesign.Spacing.itemGap) {
      ForEach(statusItems, id: \.id) { item in
        WizardStatusItem(
          icon: item.icon,
          title: item.title,
          status: item.status,
          isNavigable: item.isNavigable,
          action: item.isNavigable ? { onNavigateToPage?(item.targetPage) } : nil
        )
        
        // Show expanded details for failed items
        if item.status == .failed && !item.subItems.isEmpty {
          VStack(alignment: .leading, spacing: WizardDesign.Spacing.labelGap) {
            ForEach(item.subItems, id: \.id) { subItem in
              HStack(spacing: WizardDesign.Spacing.iconGap) {
                Rectangle()
                  .fill(Color.clear)
                  .frame(width: WizardDesign.Spacing.indentation)
                
                WizardStatusItem(
                  icon: subItem.icon,
                  title: subItem.title,
                  status: subItem.status,
                  isNavigable: subItem.isNavigable,
                  action: subItem.isNavigable ? { onNavigateToPage?(subItem.targetPage) } : nil
                )
              }
            }
          }
        }
      }
    }
  }
  
  // MARK: - Status Items Creation
  
  private var statusItems: [StatusItemModel] {
    var items: [StatusItemModel] = []
    
    // 1. Conflicts Check
    let hasConflicts = issues.contains { $0.category == .conflicts }
    items.append(StatusItemModel(
      id: "conflicts",
      icon: "exclamationmark.triangle",
      title: "No Conflicts",
      status: hasConflicts ? .failed : .completed,
      isNavigable: true,
      targetPage: .conflicts
    ))
    
    // 2. System Permissions (with expandable sub-items when failed)
    let permissionStatus = getPermissionStatus()
    let permissionSubItems = permissionStatus == .failed ? getPermissionSubItems() : []
    items.append(StatusItemModel(
      id: "permissions",
      icon: "lock.shield",
      title: "System Permissions",
      status: permissionStatus,
      isNavigable: true,
      targetPage: getPermissionTargetPage(),
      subItems: permissionSubItems
    ))
    
    // 3. Binary Installation
    let hasInstallationIssues = issues.contains { $0.category == .installation }
    items.append(StatusItemModel(
      id: "installation",
      icon: "keyboard",
      title: "Binary Installation",
      status: hasInstallationIssues ? .failed : .completed,
      isNavigable: true,
      targetPage: .installation
    ))
    
    // 4. System Service
    items.append(StatusItemModel(
      id: "service",
      icon: "play",
      title: "Kanata Service",
      status: getServiceStatus(),
      isNavigable: true,
      targetPage: .service
    ))
    
    return items
  }
  
  // MARK: - Status Helpers
  
  private func getPermissionStatus() -> InstallationStatus {
    let hasPermissionIssues = stateInterpreter.hasAnyPermissionIssues(in: issues)
    let hasBackgroundServiceIssues = !stateInterpreter.areBackgroundServicesEnabled(in: issues)
    
    return (hasPermissionIssues || hasBackgroundServiceIssues) ? .failed : .completed
  }
  
  private func getPermissionSubItems() -> [StatusItemModel] {
    var subItems: [StatusItemModel] = []
    
    // Input Monitoring
    let inputStatus = getInputMonitoringStatus()
    if inputStatus == .failed {
      subItems.append(StatusItemModel(
        id: "input-monitoring",
        icon: "eye",
        title: "Input Monitoring",
        status: inputStatus,
        isNavigable: true,
        targetPage: .inputMonitoring
      ))
    }
    
    // Accessibility
    let accessibilityStatus = getAccessibilityStatus()
    if accessibilityStatus == .failed {
      subItems.append(StatusItemModel(
        id: "accessibility",
        icon: "accessibility",
        title: "Accessibility",
        status: accessibilityStatus,
        isNavigable: true,
        targetPage: .accessibility
      ))
    }
    
    // Background Services
    if !stateInterpreter.areBackgroundServicesEnabled(in: issues) {
      subItems.append(StatusItemModel(
        id: "background-services",
        icon: "gear.badge",
        title: "Background Services",
        status: .failed,
        isNavigable: true,
        targetPage: .backgroundServices
      ))
    }
    
    return subItems
  }
  
  private func getInputMonitoringStatus() -> InstallationStatus {
    let keyPathStatus = stateInterpreter.getPermissionStatus(.keyPathInputMonitoring, in: issues)
    let kanataStatus = stateInterpreter.getPermissionStatus(.kanataInputMonitoring, in: issues)
    return (keyPathStatus == .failed || kanataStatus == .failed) ? .failed : .completed
  }
  
  private func getAccessibilityStatus() -> InstallationStatus {
    let keyPathStatus = stateInterpreter.getPermissionStatus(.keyPathAccessibility, in: issues)
    let kanataStatus = stateInterpreter.getPermissionStatus(.kanataAccessibility, in: issues)
    return (keyPathStatus == .failed || kanataStatus == .failed) ? .failed : .completed
  }
  
  private func getPermissionTargetPage() -> WizardPage {
    if getInputMonitoringStatus() == .failed {
      return .inputMonitoring
    } else if getAccessibilityStatus() == .failed {
      return .accessibility
    } else if !stateInterpreter.areBackgroundServicesEnabled(in: issues) {
      return .backgroundServices
    }
    return .inputMonitoring
  }
  
  private func getServiceStatus() -> InstallationStatus {
    switch systemState {
    case .active:
      return .completed
    case .serviceNotRunning, .ready:
      return .failed
    case .initializing:
      return .inProgress
    default:
      return .notStarted
    }
  }
}

// MARK: - Status Item Model

private struct StatusItemModel {
  let id: String
  let icon: String
  let title: String
  let status: InstallationStatus
  let isNavigable: Bool
  let targetPage: WizardPage
  let subItems: [StatusItemModel]
  
  init(
    id: String,
    icon: String,
    title: String,
    status: InstallationStatus,
    isNavigable: Bool = false,
    targetPage: WizardPage = .summary,
    subItems: [StatusItemModel] = []
  ) {
    self.id = id
    self.icon = icon
    self.title = title
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
      onNavigateToPage: { _ in }
    )
    .padding()
  }
}