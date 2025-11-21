import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Karabiner driver and virtual HID components setup page
struct WizardKarabinerComponentsPage: View {
  let systemState: WizardSystemState
  let issues: [WizardIssue]
  let isFixing: Bool
  let onAutoFix: (AutoFixAction) async -> Bool
  let onRefresh: () -> Void
  let kanataManager: KanataManager

  // Track which specific issues are being fixed
  @State private var fixingIssues: Set<UUID> = []
  @State private var showingInstallationGuide = false
  @State private var lastDriverFixNote: String?
  @State private var showAllItems = false
  @State private var isDriverFixLoading = false
  @State private var isServicesFixLoading = false
  @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator

  var body: some View {
    VStack(spacing: 0) {
      // Use experimental hero design when driver is installed
      if !hasKarabinerIssues {
        VStack(spacing: WizardDesign.Spacing.sectionGap) {
          WizardHeroSection.success(
            icon: "keyboard.macwindow",
            title: "Karabiner Driver",
            subtitle: "Virtual keyboard driver is installed & configured for input capture",
            iconTapAction: {
              showAllItems.toggle()
              Task {
                onRefresh()
              }
            }
          )

          // Component details card below the subheading - horizontally centered
          HStack {
            Spacer()
            VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
              // Show Karabiner Driver only if showAllItems OR if it has issues (defensive)
              if showAllItems {
                HStack(spacing: 12) {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                  HStack(spacing: 0) {
                    Text("Karabiner Driver")
                      .font(.headline)
                      .fontWeight(.semibold)
                    Text(" - Virtual keyboard driver for input capture")
                      .font(.headline)
                      .fontWeight(.regular)
                  }
                }
              }

              // Show Background Services only if showAllItems OR if it has issues
              if showAllItems || componentStatus(for: .backgroundServices) != .completed {
                HStack(spacing: 12) {
                  Image(
                    systemName: componentStatus(for: .backgroundServices) == .completed
                      ? "checkmark.circle.fill" : "xmark.circle.fill"
                  )
                  .foregroundColor(
                    componentStatus(for: .backgroundServices) == .completed ? .green : .red)
                  HStack(spacing: 0) {
                    Text("Background Services")
                      .font(.headline)
                      .fontWeight(.semibold)
                    Text(" - Karabiner services in Login Items for startup")
                      .font(.headline)
                      .fontWeight(.regular)
                  }
                }
              }
            }
            .frame(maxWidth: .infinity)
            .padding(WizardDesign.Spacing.cardPadding)
            .background(Color.clear, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, WizardDesign.Spacing.pageVertical)
            .padding(.top, WizardDesign.Spacing.sectionGap)
          }

          Button(nextStepButtonTitle) {
            navigateToNextStep()
          }
          .buttonStyle(WizardDesign.Component.PrimaryButton())
          .padding(.top, WizardDesign.Spacing.sectionGap)
        }
        .heroSectionContainer()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        // Use hero design for error state too, with blue links below
        VStack(spacing: WizardDesign.Spacing.sectionGap) {
          WizardHeroSection.warning(
            icon: "keyboard.macwindow",
            title: "Karabiner Driver Required",
            subtitle:
              "Karabiner virtual keyboard driver needs to be installed & configured for input capture",
            iconTapAction: {
              showAllItems.toggle()
              Task {
                onRefresh()
              }
            }
          )

          // Component details for error state
          VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
            // Show Karabiner Driver only if showAllItems OR if it has issues
            if showAllItems || componentStatus(for: .driver) != .completed {
              HStack(spacing: 12) {
                Image(
                  systemName: componentStatus(for: .driver) == .completed
                    ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundColor(componentStatus(for: .driver) == .completed ? .green : .red)
                HStack(spacing: 0) {
                  Text("Karabiner Driver")
                    .font(.headline)
                    .fontWeight(.semibold)
                  Text(" - Virtual keyboard driver")
                    .font(.headline)
                    .fontWeight(.regular)
                }
                Spacer()
                if componentStatus(for: .driver) != .completed {
                  Button("Fix") {
                    handleKarabinerDriverFix()
                  }
                  .buttonStyle(
                    WizardDesign.Component.SecondaryButton(isLoading: isDriverFixLoading))
                  .scaleEffect(0.8)
                  .disabled(isDriverFixLoading)
                }
              }
              .help(driverIssues.asTooltipText())

              if let note = lastDriverFixNote, componentStatus(for: .driver) != .completed {
                Text("Last fix: \(note)")
                  .font(.footnote)
                  .foregroundColor(.secondary)
                  .padding(.leading, 28)
              }
            }

            // Show Background Services only if showAllItems OR if it has issues
            if showAllItems || componentStatus(for: .backgroundServices) != .completed {
              HStack(spacing: 12) {
                Image(
                  systemName: componentStatus(for: .backgroundServices) == .completed
                    ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundColor(
                  componentStatus(for: .backgroundServices) == .completed ? .green : .red)
                HStack(spacing: 0) {
                  Text("Background Services")
                    .font(.headline)
                    .fontWeight(.semibold)
                  Text(" - Login Items for automatic startup")
                    .font(.headline)
                    .fontWeight(.regular)
                }
                Spacer()
                if componentStatus(for: .backgroundServices) != .completed {
                  Button("Fix") {
                    handleBackgroundServicesFix()
                  }
                  .buttonStyle(
                    WizardDesign.Component.SecondaryButton(isLoading: isServicesFixLoading))
                  .scaleEffect(0.8)
                  .disabled(isServicesFixLoading)
                }
              }
              .help(backgroundServicesIssues.asTooltipText())
            }
          }
          .frame(maxWidth: .infinity)
          .padding(WizardDesign.Spacing.cardPadding)
          .background(Color.clear, in: RoundedRectangle(cornerRadius: 12))
          .padding(.horizontal, WizardDesign.Spacing.pageVertical)
          .padding(.top, WizardDesign.Spacing.sectionGap)
        }
        .heroSectionContainer()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(maxWidth: .infinity)
    .fixedSize(horizontal: false, vertical: true)
    .background(WizardDesign.Colors.wizardBackground)
    .wizardDetailPage()
    .sheet(isPresented: $showingInstallationGuide) {
      KarabinerInstallationGuideSheet(kanataManager: kanataManager)
    }
  }

  // MARK: - Helper Methods

  private var hasKarabinerIssues: Bool {
    // Use centralized evaluator (single source of truth)
    KarabinerComponentsStatusEvaluator.evaluate(
      systemState: systemState,
      issues: issues
    ) != .completed
  }

  private var nextStepButtonTitle: String {
    issues.isEmpty ? "Return to Summary" : "Next Issue"
  }

  private var karabinerRelatedIssues: [WizardIssue] {
    // Use centralized evaluator (single source of truth)
    KarabinerComponentsStatusEvaluator.getKarabinerRelatedIssues(from: issues)
  }

  private var driverIssues: [WizardIssue] {
    // Filter for driver-related issues (VHID, driver extension, etc.)
    issues.filter { issue in
      issue.category == .installation && issue.identifier.isVHIDRelated
    }
  }

  private var backgroundServicesIssues: [WizardIssue] {
    // Filter for background services issues
    issues.filter { issue in
      issue.category == .backgroundServices
    }
  }

  private func componentStatus(for component: KarabinerComponent) -> InstallationStatus {
    // Use centralized evaluator for individual components (single source of truth)
    KarabinerComponentsStatusEvaluator.getIndividualComponentStatus(
      component,
      in: issues
    )
  }

  private var needsManualAction: Bool {
    componentStatus(for: .backgroundServices) == .failed
  }

  private func navigateToNextStep() {
    if issues.isEmpty {
      navigationCoordinator.navigateToPage(.summary)
      return
    }

    if let nextPage = navigationCoordinator.getNextPage(for: systemState, issues: issues),
      nextPage != navigationCoordinator.currentPage
    {
      navigationCoordinator.navigateToPage(nextPage)
    } else {
      navigationCoordinator.navigateToPage(.summary)
    }
  }

  private func getComponentTitle(for issue: WizardIssue) -> String {
    switch issue.title {
    case "VirtualHIDDevice Manager Not Activated":
      "VirtualHIDDevice Manager"
    case "VirtualHIDDevice Daemon":
      "VirtualHIDDevice Daemon"
    case "VirtualHIDDevice Daemon Misconfigured":
      "VirtualHIDDevice Daemon Configuration"
    case "LaunchDaemon Services Not Installed":
      "LaunchDaemon Services"
    case "LaunchDaemon Services Failing":
      "LaunchDaemon Services"
    case "Karabiner Daemon Not Running":
      "Karabiner Daemon"
    case "Driver Extension Disabled":
      "Driver Extension"
    case "Background Services Disabled":
      "Login Items"
    default:
      issue.title
    }
  }

  private func getComponentDescription(for issue: WizardIssue) -> String {
    switch issue.title {
    case "VirtualHIDDevice Manager Not Activated":
      "The VirtualHIDDevice Manager needs to be activated for virtual HID functionality"
    case "VirtualHIDDevice Daemon":
      "Virtual keyboard driver daemon processes required for input capture"
    case "VirtualHIDDevice Daemon Misconfigured":
      "The installed LaunchDaemon points to a legacy path and needs updating"
    case "LaunchDaemon Services Not Installed":
      "System launch services for VirtualHIDDevice daemon and manager"
    case "LaunchDaemon Services Failing":
      "LaunchDaemon services are loaded but crashing or failing and need to be restarted"
    case "Karabiner Daemon Not Running":
      "The Karabiner Virtual HID Device Daemon needs to be running"
    case "Driver Extension Disabled":
      "Karabiner driver extension needs to be enabled in System Settings"
    case "Background Services Disabled":
      "Karabiner services need to be added to Login Items for automatic startup"
    default:
      issue.description
    }
  }

  private func openLoginItemsSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
      NSWorkspace.shared.open(url)
    }
  }

  // MARK: - Smart Fix Handlers

  /// Smart handler for Karabiner Driver Fix button
  /// Detects if Karabiner is installed vs needs installation
  private func handleKarabinerDriverFix() {
    guard !isDriverFixLoading else { return }
    isDriverFixLoading = true
    let isInstalled = kanataManager.isKarabinerDriverInstalled()

    Task { @MainActor in
      defer { isDriverFixLoading = false }

      if isInstalled {
        AppLogger.shared.log(
          "🔧 [Karabiner Fix] Driver installed but having issues - attempting repair")
        performAutomaticDriverRepair()
        return
      }

      AppLogger.shared.log(
        "🔧 [Karabiner Fix] Driver not installed - attempting automatic install via helper (up to 2 attempts)"
      )
      let ok = await attemptAutoInstallDriver(maxAttempts: 2)
      if ok {
        AppLogger.shared.log("✅ [Karabiner Fix] Automatic driver install succeeded")
        lastDriverFixNote = formattedStatus(success: true)
        onRefresh()
      } else {
        AppLogger.shared.log(
          "❌ [Karabiner Fix] Automatic driver install failed twice - showing manual guide")
        lastDriverFixNote = formattedStatus(success: false)
        showingInstallationGuide = true
      }
    }
  }

  /// Try helper-based driver installation up to N attempts before falling back to manual sheet
  @MainActor
  private func attemptAutoInstallDriver(maxAttempts: Int) async -> Bool {
    let attempts = max(1, maxAttempts)
    for i in 1...attempts {
      AppLogger.shared.log("🧪 [Karabiner Fix] Auto-install attempt #\(i)")
      let ok = await performAutoFix(.installCorrectVHIDDriver)
      if ok { return true }
      // Small delay before retry to allow systemextensionsctl to settle
      try? await Task.sleep(nanoseconds: 400_000_000)
    }

    // If installation failed but SMAppService is merely awaiting approval, prompt the user
    // instead of sending them to the manual Karabiner-Elements flow (which is for true install failures).
    let smState = KanataDaemonManager.determineServiceManagementState()
    if smState == .smappservicePending {
      AppLogger.shared.log(
        "💡 [Karabiner Fix] Auto-install blocked by SMAppService approval; prompting user instead of showing manual guide"
      )
      toastApprovalNeeded()
      return true  // Do not treat as fatal failure
    }

    return false
  }

  private func formattedStatus(success: Bool) -> String {
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    return success ? "succeeded at \(ts)" : "failed at \(ts) — see Logs"
  }

  private func toastApprovalNeeded() {
    if let nav = NSApplication.shared.keyWindow {
      nav.makeKeyAndOrderFront(nil)
    }
    Task { @MainActor in
      AppLogger.shared.log("💡 [Karabiner Fix] Showing approval-needed toast for Login Items")
      openLoginItemsSettings()
    }
  }

  /// Smart handler for Background Services Fix button
  /// Attempts repair first, falls back to system settings
  private func handleBackgroundServicesFix() {
    guard !isServicesFixLoading else { return }
    let driverHealthy = componentStatus(for: .driver) == .completed
    if !driverHealthy {
      AppLogger.shared.log(
        "💡 [Background Services Fix] Driver not healthy; redirecting to driver fix first")
      handleKarabinerDriverFix()
      return
    }
    // If Login Items approval is pending, prompt once and skip repeated installs
    let kanataState = KanataDaemonManager.determineServiceManagementState()
    if kanataState == .smappservicePending {
      AppLogger.shared.log(
        "💡 [Background Services Fix] SMAppService pending approval - prompting user")
      toastApprovalNeeded()
      return
    }
    isServicesFixLoading = true
    let isInstalled = kanataManager.isKarabinerDriverInstalled()

    if isInstalled {
      // Try automatic repair first
      AppLogger.shared.log("🔧 [Background Services Fix] Attempting automatic service repair")
      performAutomaticServiceRepair()
    } else {
      // No driver installed - open system settings for manual configuration
      AppLogger.shared.log("💡 [Background Services Fix] No driver - opening Login Items settings")
      openLoginItemsSettings()
      isServicesFixLoading = false
    }
  }

  /// Attempts automatic repair of Karabiner driver issues
  private func performAutomaticDriverRepair() {
    Task { @MainActor in
      // Fix Session envelope for traceability
      let session = UUID().uuidString
      let t0 = Date()
      AppLogger.shared.log("🧭 [FIX-VHID \(session)] START Karabiner driver repair")

      // Determine issues involved
      let vhidIssues = issues.filter(\.identifier.isVHIDRelated)
      AppLogger.shared.log(
        "🧭 [FIX-VHID \(session)] Issues: \(vhidIssues.map { String(describing: $0.identifier) }.joined(separator: ", "))"
      )

      var success = false

      // Always fix version mismatch and daemon misconfig first (structural), then perform a verified restart.
      if vhidIssues.contains(where: { $0.identifier == .component(.vhidDriverVersionMismatch) }) {
        AppLogger.shared.log("🧭 [FIX-VHID \(session)] Action: fixDriverVersionMismatch")
        success = await performAutoFix(.fixDriverVersionMismatch)
      } else if vhidIssues.contains(where: { $0.identifier == .component(.vhidDaemonMisconfigured) }
      ) {
        AppLogger.shared.log("🧭 [FIX-VHID \(session)] Action: repairVHIDDaemonServices")
        success = await performAutoFix(.repairVHIDDaemonServices)
      } else if vhidIssues.contains(where: { $0.identifier == .component(.launchDaemonServices) }) {
        AppLogger.shared.log("🧭 [FIX-VHID \(session)] Action: installLaunchDaemonServices")
        success = await performAutoFix(.installLaunchDaemonServices)
      }

      // Always run a verified restart last to ensure single-owner state
      AppLogger.shared.log("🧭 [FIX-VHID \(session)] Action: restartVirtualHIDDaemon (verified)")
      let restartOk = await performAutoFix(.restartVirtualHIDDaemon)
      success = success || restartOk

      // Post-repair diagnostic
      let detail = kanataManager.getVirtualHIDBreakageSummary()
      AppLogger.shared.log("🧭 [FIX-VHID \(session)] Diagnostic after repair:\n\(detail)")

      let elapsed = String(format: "%.3f", Date().timeIntervalSince(t0))
      AppLogger.shared.log("🧭 [FIX-VHID \(session)] END (success=\(success)) in \(elapsed)s")

      if success {
        // Run a fresh validation synchronously before leaving the page to avoid stale summary red states.
        await refreshAndWait()
      } else {
        showingInstallationGuide = true
      }
      isDriverFixLoading = false
    }
  }

  /// Attempts automatic repair of background services
  private func performAutomaticServiceRepair() {
    Task { @MainActor in
      // Use the wizard's auto-fix capability

      AppLogger.shared.log("🔧 [Service Repair] Installing/repairing LaunchDaemon services")
      let success = await performAutoFix(.installLaunchDaemonServices)

      if success {
        AppLogger.shared.log("✅ [Service Repair] Service repair succeeded")
        await refreshAndWait()
      } else {
        AppLogger.shared.log("❌ [Service Repair] Service repair failed - opening system settings")
        openLoginItemsSettings()
      }
      isServicesFixLoading = false
    }
  }

  /// Perform auto-fix using the wizard's auto-fix capability
  private func performAutoFix(_ action: AutoFixAction) async -> Bool {
    await onAutoFix(action)
  }

  /// Refresh wizard state and wait for completion before returning control to caller UI.
  @MainActor
  private func refreshAndWait() async {
    // Bridge the existing synchronous callback into an async confirmation by invoking and then
    // yielding to the runloop briefly. The underlying refresh path updates wizard state via
    // WizardStateManager → InstallerEngine → SystemValidator.
    onRefresh()
    // Give the refresh task a short window to complete before the user is bounced to summary.
    // This avoids showing stale red items when the fix actually succeeded.
    try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

    // If everything else is healthy but the service isn’t running yet, try to start it now so
    // the summary doesn’t bounce back with a “Start Kanata Service” error.
    if !kanataManager.isRunning {
      AppLogger.shared.log("🔄 [Karabiner Fix] Post-fix: Kanata not running, attempting start")
      _ = await kanataManager.startKanata()
    }
  }
}
