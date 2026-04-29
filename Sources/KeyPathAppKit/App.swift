import AppKit
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathPluginKit
import KeyPathWizardCore
import ServiceManagement
import Sparkle
import SwiftUI

public struct KeyPathApp: App {
    // Phase 4: MVVM - Use ViewModel instead of Manager directly
    @State private var viewModel: KanataViewModel
    private let kanataManager: RuntimeCoordinator
    private let serviceContainer: ServiceContainer
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let isHeadlessMode: Bool
    private let isOneShotProbeMode: Bool

    public init() {
        let result = CompositionRoot.bootstrap()
        kanataManager = result.kanataManager
        viewModel = result.viewModel
        serviceContainer = result.serviceContainer
        isHeadlessMode = result.isHeadlessMode
        isOneShotProbeMode = result.isOneShotProbeMode

        appDelegate.kanataManager = result.kanataManager
        appDelegate.viewModel = result.viewModel
        appDelegate.serviceContainer = result.serviceContainer
        appDelegate.isHeadlessMode = result.isHeadlessMode
    }

    public var body: some Scene {
        // Note: Main window now managed by AppKit MainWindowController
        // Settings scene for preferences window
        Settings {
            SettingsContainerView()
                .environment(viewModel) // Phase 4: Inject ViewModel
                .environment(\.services, serviceContainer)
                .environment(\.preferencesService, PreferencesService.shared)
                .environment(\.permissionSnapshotProvider, PermissionOracle.shared)
        }
        .commands {
            AppMenuCommands(viewModel: viewModel, appDelegate: appDelegate)
        }
    }
}

// MARK: - Helper Functions

@MainActor
func openConfigInEditor(viewModel: KanataViewModel) {
    let url = URL(fileURLWithPath: viewModel.configPath)
    openFileInPreferredEditor(url)
}

/// Opens a file in Zed if available, otherwise falls back to default application
@MainActor
func openFileInPreferredEditor(_ url: URL) {
    let zedBundleID = "dev.zed.Zed"

    // Try to find Zed
    if let zedURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: zedBundleID) {
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: zedURL, configuration: config) { _, error in
            if let error {
                AppLogger.shared.log("⚠️ Failed to open in Zed: \(error). Falling back to default.")
                NSWorkspace.shared.open(url)
            } else {
                AppLogger.shared.log("📝 Opened config in Zed")
            }
        }
    } else {
        // Zed not installed, use default
        NSWorkspace.shared.open(url)
        AppLogger.shared.log("📝 Opened config with default application (Zed not found)")
    }
}

@MainActor
func openPreferencesTab(_ notification: Notification.Name) {
    AppLogger.shared.log("🎯 [App] Opening preferences tab: \(notification.rawValue)")

    // Post notification first to ensure tab switches when window opens
    NotificationCenter.default.post(name: notification, object: nil)

    // macOS 14+: The Settings menu item is automatically created by SwiftUI
    // Find it in the app menu and trigger it programmatically
    if let appMenu = NSApp.mainMenu?.items.first?.submenu {
        for item in appMenu.items {
            // Look for the "Settings..." menu item (standard name on macOS)
            if item.title.contains("Settings") || item.title.contains("Preferences"),
               let action = item.action
            {
                AppLogger.shared.log("✅ [App] Found Settings menu item, triggering it")
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(action, to: item.target, from: item)
                return
            }
        }
    }

    AppLogger.shared.log("⚠️ [App] Could not find Settings menu item, trying fallback")

    // Fallback: Use the selector method (works on macOS 13 and earlier)
    NSApp.activate(ignoringOtherApps: true)
    if #available(macOS 13, *) {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    } else {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static func isOneShotProbeEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment)
        -> Bool
    {
        OneShotProbeEnvironment.isActive(environment)
    }

    var kanataManager: RuntimeCoordinator?
    var viewModel: KanataViewModel?
    var serviceContainer: ServiceContainer?
    var isHeadlessMode = false
    private var mainWindowController: MainWindowController?
    private var menuBarController: MenuBarController?
    private var initialMainWindowShown = false
    private var pendingReopenShow = false
    private var suppressLaunchSplashAutoHide = false
    private var keyboardCapture: KeyboardCapture?

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        AppLogger.shared.log("🔍 [AppDelegate] applicationShouldTerminate called")
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        AppLogger.shared.log("🔍 [AppDelegate] applicationShouldTerminateAfterLastWindowClosed called")
        return !GlobalHotkeyService.shared.isEnabled
    }

    func applicationWillHide(_: Notification) {
        AppLogger.shared.debug("🔍 [AppDelegate] applicationWillHide called")
    }

    func applicationDidBecomeActive(_: Notification) {
        AppLogger.shared.debug(
            "🔍 [AppDelegate] applicationDidBecomeActive called (initialShown=\(initialMainWindowShown))"
        )

        if !initialMainWindowShown {
            handleFirstActivation()
        } else {
            handleSubsequentActivation()
        }
    }

    func applicationDidFinishLaunching(_: Notification) {
        AppLogger.shared.info("🔍 [AppDelegate] applicationDidFinishLaunching called")

        #if DEBUG
            AppLogger.shared.info("[AppDelegate] Build configuration: DEBUG")
        #else
            AppLogger.shared.info("[AppDelegate] Build configuration: RELEASE")
        #endif

        let info = BuildInfo.current()
        AppLogger.shared.info(
            "🏷️ [Build] Version: \(info.version) | Build: \(info.build) | Git: \(info.git) | Date: \(info.date)"
        )

        // Set smart default keyboard layout on first launch
        setSmartKeyboardLayoutDefault()

        // Handle one-shot probe modes (diagnostics, bridge prep, repair, etc.)
        if OneShotProbeHandler.handleIfNeeded() {
            return
        }

        // Single-instance guard
        if !isHeadlessMode, !ProcessInfo.processInfo.arguments.contains("--headless"),
           let bundleIdentifier = Bundle.main.bundleIdentifier,
           SingleInstanceCoordinator.activateExistingAndTerminateIfNeeded(
               bundleIdentifier: bundleIdentifier
           )
        {
            AppLogger.shared.info("🪟 [AppDelegate] Duplicate normal app launch detected; exiting early")
            return
        }

        AppLogger.shared.debug("📡 [AppDelegate] TCP communication mode - no auth token needed")

        if !isHeadlessMode {
            setupMenuBarController()
            SplashView.PosterCache.warmIfNeeded()
        }

        // Check for pending service bounce (skip on fresh install)
        Task { @MainActor in
            await handleServiceBounceIfNeeded()
        }

        if isHeadlessMode {
            handleHeadlessAutoStart()
        }

        // Register all notification observers
        AppNotificationWiring.registerAll(on: self)

        // Start emergency-stop monitoring once permissions are already granted
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            await self.startEmergencyMonitoringIfPermitted()
        }

        // Set up main window and overlay (normal mode only)
        if !isHeadlessMode {
            setupMainWindowAndOverlay()
        } else {
            AppLogger.shared.debug("🤖 [AppDelegate] Headless mode - skipping window management")
        }
    }

    func applicationWillResignActive(_: Notification) {
        AppLogger.shared.log("🔍 [AppDelegate] applicationWillResignActive called")
    }

    func applicationWillTerminate(_: Notification) {
        AppLogger.shared.info(
            "🚪 [AppDelegate] Application will terminate - performing synchronous cleanup"
        )
        kanataManager?.cleanupSync()
        AppLogger.shared.info("✅ [AppDelegate] Cleanup complete, app terminating")
    }

    // MARK: - URL Scheme Handling (keypath://)

    func application(_: NSApplication, open urls: [URL]) {
        DeepLinkRouter.handle(urls)
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppLogger.shared.debug(
            "🔍 [AppDelegate] applicationShouldHandleReopen (hasVisibleWindows=\(flag))"
        )

        if mainWindowController == nil {
            if NSApplication.shared.activationPolicy() != .regular {
                NSApplication.shared.setActivationPolicy(.regular)
                AppLogger.shared.debug(
                    "🪟 [AppDelegate] Escalated activation policy to .regular for UI reopen"
                )
            }

            if let vm = viewModel {
                mainWindowController = MainWindowController(viewModel: vm, serviceContainer: serviceContainer)
                AppLogger.shared.debug("🪟 [AppDelegate] Created main window controller on reopen")
                mainWindowController?.primeForActivation()
            } else {
                AppLogger.shared.error(
                    "❌ [AppDelegate] Cannot create window on reopen: ViewModel is nil"
                )
            }
        }

        suppressLaunchSplashAutoHide = true
        pendingReopenShow = false
        if NSApp.isHidden {
            NSApp.unhide(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindowController?.show(focus: true)
        initialMainWindowShown = true
        AppLogger.shared.debug("🪟 [AppDelegate] User-initiated reopen - showing main window immediately")

        return true
    }

    // MARK: - Public Window Access

    /// Bring the main window (splash) to the front. Used by menu actions that present sheets.
    @MainActor
    func showMainWindow() {
        showKeyPathFromStatusItem()
    }

    // MARK: - Notification Handlers (must be @objc for selector-based observers)

    @objc func handleShowWizardNotification(_ notification: Notification) {
        let targetRaw = (notification.userInfo?["targetPage"] as? WizardPage)?.rawValue
        Task { @MainActor in
            let targetPage = targetRaw.flatMap(WizardPage.init(rawValue:))
            self.showWizard(targetPage: targetPage)
        }
    }

    @objc func handleOpenInstallationWizardNotification(_: Notification) {
        Task { @MainActor in
            self.showWizard(targetPage: nil)
        }
    }

    // MARK: - Private: First Activation

    private func handleFirstActivation() {
        let suppressAutoHideBecauseReopen = pendingReopenShow

        let appActive = NSApp.isActive
        let appHidden = NSApp.isHidden
        AppLogger.shared.debug(
            "🔍 [AppDelegate] First activation diagnostics: isActive=\(appActive), isHidden=\(appHidden)"
        )

        if NSApp.isHidden {
            NSApp.unhide(nil)
            AppLogger.shared.debug("🪟 [AppDelegate] App was hidden, unhiding")
        }

        initialMainWindowShown = true
        suppressLaunchSplashAutoHide = false
        mainWindowController?.show(focus: true)

        Task { @MainActor in
            #if DEBUG
                let splashDelayMs = Int(ProcessInfo.processInfo.environment["KEYPATH_SPLASH_DELAY_MS"] ?? "")
                    ?? 650
            #else
                let splashDelayMs = 420
            #endif
            AppLogger.shared.info("[AppDelegate] Launch splash delay: \(splashDelayMs)ms")
            try? await Task.sleep(for: .milliseconds(splashDelayMs))

            LiveKeyboardOverlayController.shared.showForStartup(bypassHiddenCheck: true)
            AppLogger.shared.info("🪟 [AppDelegate] First activation - overlay shown")

            if !self.suppressLaunchSplashAutoHide, !suppressAutoHideBecauseReopen {
                self.mainWindowController?.window?.orderOut(nil)
                AppLogger.shared.info("🪟 [AppDelegate] Auto-hid launch splash window")
            } else {
                AppLogger.shared.info("🪟 [AppDelegate] Splash auto-hide suppressed (suppressAutoHide=\(self.suppressLaunchSplashAutoHide), reopen=\(suppressAutoHideBecauseReopen))")
            }
        }

        AppLogger.shared.info("🪟 [AppDelegate] First activation complete (splash shown briefly)")

        if pendingReopenShow {
            AppLogger.shared.debug(
                "🪟 [AppDelegate] Applying pending reopen show after first activation"
            )
            pendingReopenShow = false
            mainWindowController?.show(focus: true)
        }
    }

    private func handleSubsequentActivation() {
        if !LiveKeyboardOverlayController.shared.isVisible,
           LiveKeyboardOverlayController.shared.canAutoShow
        {
            LiveKeyboardOverlayController.shared.showForStartup()
            AppLogger.shared.debug("🪟 [AppDelegate] Subsequent activation - showing overlay")
        } else if !LiveKeyboardOverlayController.shared.isVisible {
            AppLogger.shared.debug("🪟 [AppDelegate] Subsequent activation - overlay hidden by user, not auto-showing")
        } else {
            AppLogger.shared.debug("🪟 [AppDelegate] Subsequent activation - overlay already visible")
        }
    }

    // MARK: - Private: Service Bounce

    private func handleServiceBounceIfNeeded() async {
        let isFreshInstall = Self.checkIsFreshInstall()
        if isFreshInstall {
            AppLogger.shared.info("🆕 [AppDelegate] Fresh install detected - skipping service bounce")
            PermissionGrantCoordinator.shared.clearServiceBounceFlag()
            return
        }

        let (shouldBounce, timeSince) = PermissionGrantCoordinator.shared.checkServiceBounceNeeded()

        if shouldBounce {
            if let timeSince {
                AppLogger.shared.info(
                    "🔄 [AppDelegate] Service bounce requested \(Int(timeSince))s ago - performing bounce"
                )
            } else {
                AppLogger.shared.info("🔄 [AppDelegate] Service bounce requested - performing bounce")
            }

            let bounceSuccess = await PermissionGrantCoordinator.shared.performServiceBounce()
            if bounceSuccess {
                AppLogger.shared.info("✅ [AppDelegate] Service bounce completed successfully")
                PermissionGrantCoordinator.shared.clearServiceBounceFlag()
            } else {
                AppLogger.shared.warn("❌ [AppDelegate] Service bounce failed - flag remains for retry")
            }
        }
    }

    // MARK: - Private: Headless Auto-Start

    private func handleHeadlessAutoStart() {
        AppLogger.shared.info("🤖 [AppDelegate] Headless mode - starting KeyPath runtime automatically")

        Task {
            try? await Task.sleep(for: .seconds(2))

            if let manager = self.kanataManager {
                let started = await manager.startKanata(reason: "Headless auto-start")
                if !started {
                    AppLogger.shared.error("❌ [AppDelegate] Headless auto-start failed via runtime coordinator")
                }
            } else {
                AppLogger.shared.error("❌ [AppDelegate] Headless auto-start failed: RuntimeCoordinator unavailable")
            }
        }
    }

    // MARK: - Private: Main Window & Overlay Setup

    private func setupMainWindowAndOverlay() {
        AppLogger.shared.debug("🪟 [AppDelegate] Setting up main window controller")

        guard let vm = viewModel else {
            AppLogger.shared.error("❌ [AppDelegate] ViewModel is nil, cannot create window")
            return
        }
        mainWindowController = MainWindowController(viewModel: vm, serviceContainer: serviceContainer)
        AppLogger.shared.debug(
            "🪟 [AppDelegate] Main window controller created (deferring show until activation)"
        )
        mainWindowController?.primeForActivation()
        AppLogger.shared.debug(
            "🪟 [AppDelegate] Primed main window so Finder launches have a visible surface to activate"
        )

        LiveKeyboardOverlayController.shared.configure(
            kanataViewModel: vm,
            ruleCollectionsManager: kanataManager?.rulesManager
        )

        _ = ContextHUDController.shared

        // Watch frontmost-app changes and auto-hide the overlay for apps
        // the user has listed in Settings → Experimental (default: Figma).
        OverlayAppSuppressor.shared.start()

        // Mirror KindaVim pack state into the KindaVim mode monitor —
        // start watching kindaVim's environment.json when the pack is on,
        // stop when it's off.
        KindaVimPackController.shared.start()

        // Sequential startup: regenerate config, auto-launch, validate, auto-wizard
        Task { @MainActor in
            do {
                try await AppConfigGenerator.regenerateFromStore()
                AppLogger.shared.log("✅ [AppDelegate] App-specific config regenerated")
            } catch {
                AppLogger.shared.error(
                    "❌ [AppDelegate] Failed to regenerate app-specific config: \(error)"
                )
            }

            let result = PermissionGrantCoordinator.shared.checkForPendingPermissionGrant()
            if !result.shouldRestart {
                AppLogger.shared.log("🚀 [AppDelegate] Starting auto-launch sequence (simple)")
                if let manager = self.kanataManager {
                    let started = await manager.startKanata(reason: "AppDelegate auto-launch")
                    if started {
                        AppLogger.shared.log("✅ [AppDelegate] Auto-launch sequence completed (simple)")
                        MainAppStateController.shared.invalidateValidationCooldown()
                    } else {
                        AppLogger.shared.error("❌ [AppDelegate] Auto-launch failed via runtime coordinator")
                    }
                } else {
                    AppLogger.shared.error(
                        "❌ [AppDelegate] Auto-launch requested but RuntimeCoordinator unavailable"
                    )
                }
            } else {
                AppLogger.shared.log(
                    "⏭️ [AppDelegate] Skipping auto-launch (returning from permission grant)"
                )
            }

            NotificationCenter.default.post(name: .kp_startupRevalidate, object: nil)

            let helperFunctional = await HelperManager.shared.testHelperFunctionality()
            AppLogger.shared.info("🆕 [AppDelegate] Helper functional check: \(helperFunctional)")
            if !helperFunctional {
                AppLogger.shared.info("🆕 [AppDelegate] Helper not functional - auto-launching wizard")
                try? await Task.sleep(for: .seconds(1))
                NotificationCenter.default.post(name: NSNotification.Name("ShowWizard"), object: nil)
            }
        }
    }

    // MARK: - Private: Fresh Install Check

    private static func checkIsFreshInstall() -> Bool {
        let helperStatus = SMAppService.daemon(plistName: "com.keypath.helper.plist").status
        let daemonStatus = SMAppService.daemon(plistName: "com.keypath.kanata.plist").status

        let isFresh = helperStatus == .notRegistered && daemonStatus == .notRegistered
        AppLogger.shared.log(
            "🔍 [AppDelegate] Fresh install check: helper=\(helperStatus), daemon=\(daemonStatus), isFresh=\(isFresh)"
        )
        return isFresh
    }

    // MARK: - Private: Menu Bar

    private func setupMenuBarController() {
        guard menuBarController == nil else { return }
        menuBarController = MenuBarController(
            bringToFrontHandler: { [weak self] in
                self?.showKeyPathFromStatusItem()
            },
            showWizardHandler: { targetPage in
                NotificationCenter.default.post(
                    name: NSNotification.Name("ShowWizard"),
                    object: nil,
                    userInfo: targetPage.map { ["targetPage": $0] }
                )
            },
            openSettingsHandler: {
                NotificationCenter.default.post(name: .openSettingsGeneral, object: nil)
            },
            openSettingsRulesHandler: {
                NotificationCenter.default.post(name: .openSettingsRules, object: nil)
            },
            quitHandler: {
                for window in NSApplication.shared.windows {
                    window.close()
                }
                NSApplication.shared.terminate(nil)
            }
        )

        if let rulesManager = kanataManager?.rulesManager {
            menuBarController?.configure(
                appStateController: MainAppStateController.shared,
                ruleCollectionsManager: rulesManager
            )
        }

        AppLogger.shared.debug("☰ [MenuBar] Status item initialized")
    }

    private func showKeyPathFromStatusItem() {
        AppLogger.shared.debug("☰ [MenuBar] Show KeyPath requested from status item")

        if mainWindowController == nil {
            if let vm = viewModel {
                mainWindowController = MainWindowController(viewModel: vm, serviceContainer: serviceContainer)
                AppLogger.shared.debug("🪟 [MenuBar] Created main window controller for status item request")
            } else {
                AppLogger.shared.error("❌ [MenuBar] Cannot show KeyPath: ViewModel unavailable")
                return
            }
        }

        suppressLaunchSplashAutoHide = true

        if NSApp.isHidden {
            NSApp.unhide(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        mainWindowController?.show(focus: true)
        initialMainWindowShown = true
        pendingReopenShow = false
    }

    // MARK: - Private: Wizard

    @MainActor
    private func showWizard(targetPage: WizardPage?) {
        guard let vm = viewModel else {
            AppLogger.shared.error("❌ [AppDelegate] Cannot show wizard: ViewModel unavailable")
            return
        }

        let initialPage = targetPage ?? resolveWizardInitialPage()
        WizardWindowController.shared.showWindow(
            initialPage: initialPage,
            kanataViewModel: vm,
            onDismiss: { [weak self] in
                Task { @MainActor in
                    await self?.viewModel?.updateStatus()
                    await MainAppStateController.shared.revalidate()
                }
            }
        )
    }

    @MainActor
    private func resolveWizardInitialPage() -> WizardPage? {
        if let restorePoint = UserDefaults.standard.string(forKey: "KeyPath.WizardRestorePoint") {
            let restoreTime = UserDefaults.standard.double(forKey: "KeyPath.WizardRestoreTime")
            let timeSinceRestore = Date().timeIntervalSince1970 - restoreTime

            UserDefaults.standard.removeObject(forKey: "KeyPath.WizardRestorePoint")
            UserDefaults.standard.removeObject(forKey: "KeyPath.WizardRestoreTime")

            if timeSinceRestore < 300 {
                let page = WizardPage.allCases.first { $0.rawValue == restorePoint }
                    ?? WizardPage.allCases.first { String(describing: $0) == restorePoint }
                if let page {
                    AppLogger.shared.log("🔄 [AppDelegate] Restoring wizard to \(page.displayName) after app restart")
                    return page
                }
            } else {
                AppLogger.shared.log("⏱️ [AppDelegate] Wizard restore point expired (\(Int(timeSinceRestore))s old)")
            }
        }

        if UserDefaults.standard.bool(forKey: "wizard_return_to_summary") {
            UserDefaults.standard.removeObject(forKey: "wizard_return_to_summary")
            AppLogger.shared.log("✅ [AppDelegate] Permissions granted - returning to Summary")
            return .summary
        } else if UserDefaults.standard.bool(forKey: "wizard_return_to_input_monitoring") {
            UserDefaults.standard.removeObject(forKey: "wizard_return_to_input_monitoring")
            return .inputMonitoring
        } else if UserDefaults.standard.bool(forKey: "wizard_return_to_accessibility") {
            UserDefaults.standard.removeObject(forKey: "wizard_return_to_accessibility")
            return .accessibility
        }

        return nil
    }

    // MARK: - Private: Keyboard Layout Detection

    /// Sets a default keyboard layout on first launch.
    /// Uses ANSI as the synchronous default. Actual HID-based detection is deferred
    /// to `CompositionRoot.scheduleDeferredStartupServices()` where we can check
    /// Input Monitoring permission first (IOHIDManagerOpen triggers a prompt without it).
    private func setSmartKeyboardLayoutDefault() {
        let key = LayoutPreferences.layoutIdKey

        if UserDefaults.standard.string(forKey: key) != nil {
            AppLogger.shared.debug("⌨️ [AppDelegate] Keyboard layout already set by user, skipping auto-detect")
            return
        }

        // Set ANSI as default; will be refined in deferred startup if Input Monitoring is granted
        UserDefaults.standard.set(LayoutPreferences.defaultLayoutId, forKey: key)
        AppLogger.shared.info("⌨️ [AppDelegate] First launch - set default layout: \(LayoutPreferences.defaultLayoutId) (HID detection deferred)")
    }

    // MARK: - Private: Emergency Stop

    @MainActor
    private func startEmergencyMonitoringIfPermitted() async {
        let snapshot = await PermissionOracle.shared.currentSnapshot()
        guard snapshot.keyPath.accessibility.isReady else {
            AppLogger.shared.debug("🛑 [EmergencyStop] Skipping monitor start (Accessibility not granted)")
            return
        }

        if keyboardCapture == nil {
            keyboardCapture = KeyboardCapture()
            AppLogger.shared.log("🎹 [AppDelegate] KeyboardCapture initialized for emergency monitoring")
        }

        guard let capture = keyboardCapture else { return }

        capture.startEmergencyMonitoring {
            Task { @MainActor in
                let stopped = await self.viewModel?.stopKanata(reason: "Emergency stop hotkey") ?? false
                if stopped {
                    AppLogger.shared.log("🛑 [EmergencyStop] Kanata service stopped via facade")
                } else {
                    AppLogger.shared.warn("⚠️ [EmergencyStop] Failed to stop Kanata service via facade")
                }

                self.viewModel?.emergencyStopActivated = true

                UserNotificationService.shared.notifyConfigEvent(
                    "Emergency stop activated",
                    body: "Remapping paused. Open Settings -> Status to start the service again.",
                    key: "emergency.stop.activated"
                )

                if NSApp.isActive, !NSApp.isHidden {
                    self.showMainWindow()
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ShowEmergencyStop"),
                        object: nil
                    )
                }
            }
        }
    }
}

#if DEBUG

    // MARK: - SMAppService Dev Utilities

    @MainActor
    private func showSMAppServiceStatus(plistName: String) {
        let svc = SMAppService.daemon(plistName: plistName)
        let status = svc.status
        AppLogger.shared.info(
            "🔧 [SM] \(plistName) status=\(status.rawValue) (0=notRegistered,1=enabled,2=requiresApproval,3=notFound)"
        )
    }

    @MainActor
    private func registerSMAppService(plistName: String) {
        let svc = SMAppService.daemon(plistName: plistName)
        do {
            try svc.register()
            AppLogger.shared.info("✅ [SM] register() ok for \(plistName)")
        } catch {
            AppLogger.shared.error("❌ [SM] register() failed for \(plistName): \(error)")
        }
        showSMAppServiceStatus(plistName: plistName)
    }

    private func unregisterSMAppService(plistName: String) {
        let svc = SMAppService.daemon(plistName: plistName)
        if #available(macOS 13, *) {
            Task { @MainActor in
                do {
                    try await svc.unregister()
                    AppLogger.shared.info("✅ [SM] unregister() ok for \(plistName)")
                } catch {
                    AppLogger.shared.error("❌ [SM] unregister() failed for \(plistName): \(error)")
                }
                showSMAppServiceStatus(plistName: plistName)
            }
        } else {
            AppLogger.shared.warn("⚠️ [SM] unregister requires macOS 13+")
        }
    }
#endif
