import Foundation
import KeyPathCore
import KeyPathWizardCore

/// Adapter to convert SystemSnapshot (new) to SystemStateResult (old wizard format)
/// This allows testing the new SystemValidator in the existing wizard without rewriting all pages
@MainActor
struct SystemSnapshotAdapter {
  /// Convert SystemSnapshot to SystemStateResult for backward compatibility
  static func adapt(_ snapshot: SystemSnapshot) -> SystemStateResult {
    // Convert to wizard system state
    let wizardState = adaptSystemState(snapshot)

    // Convert issues
    let wizardIssues = adaptIssues(snapshot)

    // Determine auto-fix actions
    let autoFixActions = determineAutoFixActions(snapshot)

    return SystemStateResult(
      state: wizardState,
      issues: wizardIssues,
      autoFixActions: autoFixActions,
      detectionTimestamp: snapshot.timestamp
    )
  }

  private static func adaptSystemState(_ snapshot: SystemSnapshot) -> WizardSystemState {
    // Priority order matches wizard logic (SystemStatusChecker.determineSystemState)
    // This ensures main screen shows same status as wizard

    AppLogger.shared.log("📊 [SystemSnapshotAdapter] === ADAPTER STATE DETERMINATION ===")

    // 1. If conflicts exist, that's highest priority
    if snapshot.conflicts.hasConflicts {
      AppLogger.shared.log(
        "📊 [SystemSnapshotAdapter] Decision: CONFLICTS DETECTED (\(snapshot.conflicts.conflicts.count) conflicts)"
      )
      return .conflictsDetected(conflicts: snapshot.conflicts.conflicts)
    }

    // 2. ⭐ Check if Kanata is running FIRST (matches wizard line 674)
    // If kanata is running successfully, show active regardless of sub-component health
    // This is the key fix: daemon/vhid are implementation details
    if snapshot.health.kanataRunning {
      AppLogger.shared.log(
        "📊 [SystemSnapshotAdapter] Decision: ACTIVE (kanata running, ignoring sub-component health)"
      )
      return .active  // Show as active even if daemon/vhid unhealthy
    }

    AppLogger.shared.log("📊 [SystemSnapshotAdapter] Kanata NOT running, checking prerequisites...")

    // 3. Only check permissions if kanata is NOT running
    let missingPerms = getMissingPermissions(snapshot)
    if !missingPerms.isEmpty {
      AppLogger.shared.log(
        "📊 [SystemSnapshotAdapter] Decision: MISSING PERMISSIONS (\(missingPerms.count) missing)")
      for perm in missingPerms {
        AppLogger.shared.log("📊 [SystemSnapshotAdapter]   - Missing: \(perm)")
      }
      return .missingPermissions(missing: missingPerms)
    }

    // 4. Check components
    let missingComponents = getMissingComponents(snapshot)
    if !missingComponents.isEmpty {
      AppLogger.shared.log(
        "📊 [SystemSnapshotAdapter] Decision: MISSING COMPONENTS (\(missingComponents.count) missing)"
      )
      for comp in missingComponents {
        AppLogger.shared.log("📊 [SystemSnapshotAdapter]   - Missing: \(comp)")
      }
      return .missingComponents(missing: missingComponents)
    }

    // 5. Check daemon health
    if !snapshot.health.karabinerDaemonRunning {
      AppLogger.shared.log("📊 [SystemSnapshotAdapter] Decision: DAEMON NOT RUNNING")
      return .daemonNotRunning
    }

    // 6. All components ready but kanata not running
    AppLogger.shared.log(
      "📊 [SystemSnapshotAdapter] Decision: SERVICE NOT RUNNING (everything ready but kanata not started)"
    )
    return .serviceNotRunning
  }

  private static func getMissingPermissions(_ snapshot: SystemSnapshot) -> [PermissionRequirement] {
    var missing: [PermissionRequirement] = []

    AppLogger.shared.log(
      "📊 [SystemSnapshotAdapter] Checking permissions (using isBlocking, not isReady):")

    // Match wizard logic (SystemStatusChecker lines 282-305):
    // Only mark as missing if DEFINITIVELY BLOCKED, not just "not ready"
    // This prevents false errors when status is unknown/inconclusive

    // KeyPath permissions (use isBlocking instead of !isReady)
    if snapshot.permissions.keyPath.inputMonitoring.isBlocking {
      AppLogger.shared.log("📊 [SystemSnapshotAdapter]   KeyPath IM: BLOCKING")
      missing.append(.keyPathInputMonitoring)
    } else {
      AppLogger.shared.log(
        "📊 [SystemSnapshotAdapter]   KeyPath IM: OK (isReady=\(snapshot.permissions.keyPath.inputMonitoring.isReady), isBlocking=false)"
      )
    }

    if snapshot.permissions.keyPath.accessibility.isBlocking {
      AppLogger.shared.log("📊 [SystemSnapshotAdapter]   KeyPath AX: BLOCKING")
      missing.append(.keyPathAccessibility)
    } else {
      AppLogger.shared.log(
        "📊 [SystemSnapshotAdapter]   KeyPath AX: OK (isReady=\(snapshot.permissions.keyPath.accessibility.isReady), isBlocking=false)"
      )
    }

    // Kanata permissions (use isBlocking instead of !isReady)
    if snapshot.permissions.kanata.inputMonitoring.isBlocking {
      AppLogger.shared.log("📊 [SystemSnapshotAdapter]   Kanata IM: BLOCKING")
      missing.append(.kanataInputMonitoring)
    } else {
      AppLogger.shared.log(
        "📊 [SystemSnapshotAdapter]   Kanata IM: OK (isReady=\(snapshot.permissions.kanata.inputMonitoring.isReady), isBlocking=false)"
      )
    }

    if snapshot.permissions.kanata.accessibility.isBlocking {
      AppLogger.shared.log("📊 [SystemSnapshotAdapter]   Kanata AX: BLOCKING")
      missing.append(.kanataAccessibility)
    } else {
      AppLogger.shared.log(
        "📊 [SystemSnapshotAdapter]   Kanata AX: OK (isReady=\(snapshot.permissions.kanata.accessibility.isReady), isBlocking=false)"
      )
    }

    AppLogger.shared.log("📊 [SystemSnapshotAdapter] Total missing permissions: \(missing.count)")
    return missing
  }

  private static func getMissingComponents(_ snapshot: SystemSnapshot) -> [ComponentRequirement] {
    var missing: [ComponentRequirement] = []

    AppLogger.shared.log("📊 [SystemSnapshotAdapter] Checking components:")

    if !snapshot.components.kanataBinaryInstalled {
      AppLogger.shared.log("📊 [SystemSnapshotAdapter]   Kanata binary: MISSING")
      missing.append(.kanataBinaryMissing)
    } else {
      AppLogger.shared.log("📊 [SystemSnapshotAdapter]   Kanata binary: OK")
    }

    if !snapshot.components.karabinerDriverInstalled {
      AppLogger.shared.log("📊 [SystemSnapshotAdapter]   Karabiner driver: MISSING")
      missing.append(.karabinerDriver)
    } else {
      AppLogger.shared.log("📊 [SystemSnapshotAdapter]   Karabiner driver: OK")
    }

    if !snapshot.components.karabinerDaemonRunning {
      AppLogger.shared.log("📊 [SystemSnapshotAdapter]   Karabiner daemon: NOT RUNNING")
      missing.append(.karabinerDaemon)
    } else {
      AppLogger.shared.log("📊 [SystemSnapshotAdapter]   Karabiner daemon: OK")
    }

    // ⭐ Check for driver version mismatch FIRST (before health checks)
    // Version mismatch CAUSES health issues, so fix the root cause first
    if snapshot.components.vhidVersionMismatch {
      AppLogger.shared.log(
        "📊 [SystemSnapshotAdapter]   VHID driver version: MISMATCH (needs v5 for kanata v1.9.0)")
      missing.append(.vhidDriverVersionMismatch)
    } else {
      AppLogger.shared.log("📊 [SystemSnapshotAdapter]   VHID driver version: OK")
    }

    if !snapshot.components.vhidDeviceHealthy {
      AppLogger.shared.log("📊 [SystemSnapshotAdapter]   VHID device: UNHEALTHY")
      missing.append(.vhidDeviceRunning)
    } else {
      AppLogger.shared.log("📊 [SystemSnapshotAdapter]   VHID device: OK")
    }

    if !snapshot.components.launchDaemonServicesHealthy {
      // 🔍 DEBUG: Log the value of vhidDeviceHealthy to understand workaround behavior
      AppLogger.shared.log(
        "📊 [SystemSnapshotAdapter] 🔍 DEBUG: launchDaemonServicesHealthy=false, vhidDeviceHealthy=\(snapshot.components.vhidDeviceHealthy)"
      )

      if snapshot.components.vhidDeviceHealthy {
        AppLogger.shared.log(
          "📊 [SystemSnapshotAdapter]   LaunchDaemon services: UNHEALTHY (but daemon running) - Downgrading to non-blocking"
        )
        // Do NOT add to missing components list if the daemon is actually running
      } else {
        AppLogger.shared.log("📊 [SystemSnapshotAdapter]   LaunchDaemon services: UNHEALTHY")
        missing.append(.launchDaemonServices)
      }
    } else {
      AppLogger.shared.log("📊 [SystemSnapshotAdapter]   LaunchDaemon services: OK")
    }

    AppLogger.shared.log("📊 [SystemSnapshotAdapter] Total missing components: \(missing.count)")
    return missing
  }

  private static func adaptIssues(_ snapshot: SystemSnapshot) -> [WizardIssue] {
    snapshot.blockingIssues.map { issue in
      switch issue {
      case .permissionMissing(let app, let permission, let action):
        let req: PermissionRequirement =
          if app == "KeyPath", permission == "Input Monitoring" {
            .keyPathInputMonitoring
          } else if app == "KeyPath", permission == "Accessibility" {
            .keyPathAccessibility
          } else if app == "Kanata", permission == "Input Monitoring" {
            .kanataInputMonitoring
          } else {
            .kanataAccessibility
          }

        return WizardIssue(
          identifier: .permission(req),
          severity: .error,
          category: .permissions,
          title: issue.title,
          description: action,
          autoFixAction: nil,
          userAction: action
        )

      case .componentMissing(let name, let autoFix):
        // Map component name to ComponentRequirement
        let comp: ComponentRequirement
        let fixAction: AutoFixAction?

        if name.contains("Privileged Helper") {
          comp = .privilegedHelper
          fixAction = autoFix ? .installPrivilegedHelper : nil
        } else if name.contains("Kanata") {
          comp = .kanataBinaryMissing
          fixAction = autoFix ? .installMissingComponents : nil
        } else if name.contains("Karabiner driver") {
          comp = .karabinerDriver
          fixAction = autoFix ? .installMissingComponents : nil
        } else {
          comp = .vhidDeviceRunning
          fixAction = autoFix ? .installMissingComponents : nil
        }

        return WizardIssue(
          identifier: .component(comp),
          severity: .error,
          category: .installation,
          title: issue.title,
          description: "Install \(name)",
          autoFixAction: fixAction,
          userAction: "Install via wizard"
        )

      case .componentUnhealthy(let name, let autoFix):
        // Map component name to ComponentRequirement and appropriate fix
        let comp: ComponentRequirement
        let fixAction: AutoFixAction?

        if name.contains("Privileged Helper") {
          comp = .privilegedHelperUnhealthy
          fixAction = autoFix ? .reinstallPrivilegedHelper : nil
        } else {
          // Default to VirtualHID for other components
          comp = .vhidDeviceRunning
          // Use verified restart to avoid user-mode duplicates when LaunchDaemon exists
          fixAction = autoFix ? .restartVirtualHIDDaemon : nil
        }

        return WizardIssue(
          identifier: .component(comp),
          severity: .error,
          category: .installation,
          title: issue.title,
          description: "Restart \(name)",
          autoFixAction: fixAction,
          userAction: "Restart component"
        )

      case .componentVersionMismatch(let name, let autoFix):
        return WizardIssue(
          identifier: .component(.vhidDriverVersionMismatch),
          severity: .error,
          category: .installation,
          title: issue.title,
          description: "Install correct version for \(name)",
          autoFixAction: autoFix ? .fixDriverVersionMismatch : nil,
          userAction: "Install correct version"
        )

      case .serviceNotRunning(let name, let autoFix):
        return WizardIssue(
          identifier: .daemon,
          severity: .error,
          category: .daemon,
          title: issue.title,
          description: "Start \(name)",
          autoFixAction: autoFix ? .startKarabinerDaemon : nil,
          userAction: "Start service"
        )

      case .conflict(let systemConflict):
        return WizardIssue(
          identifier: .conflict(systemConflict),
          severity: .error,
          category: .conflicts,
          title: issue.title,
          description: "Terminate conflicting process",
          autoFixAction: .terminateConflictingProcesses,
          userAction: "Terminate process"
        )
      }
    }
  }

  private static func determineAutoFixActions(_ snapshot: SystemSnapshot) -> [AutoFixAction] {
    // Convert SystemSnapshot to SystemContext for use with ActionDeterminer
    // This removes duplication - ActionDeterminer now centralizes all action determination logic
    let context = convertToSystemContext(snapshot)
    
    // Use ActionDeterminer for repair actions (SystemSnapshotAdapter is used for general auto-fix)
    return ActionDeterminer.determineRepairActions(context: context)
  }
  
  /// Convert SystemSnapshot to SystemContext for compatibility with ActionDeterminer
  /// SystemSnapshot is missing EngineSystemInfo, so we create a minimal one
  private static func convertToSystemContext(_ snapshot: SystemSnapshot) -> SystemContext {
    // Get system info (minimal - SystemSnapshotAdapter doesn't have SystemRequirements)
    let systemInfo = EngineSystemInfo(
      macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      driverCompatible: true // Assume compatible - SystemSnapshot doesn't track this
    )
    
    return SystemContext(
      permissions: snapshot.permissions,
      services: snapshot.health,
      conflicts: snapshot.conflicts,
      components: snapshot.components,
      helper: snapshot.helper,
      system: systemInfo,
      timestamp: snapshot.timestamp
    )
  }
}
