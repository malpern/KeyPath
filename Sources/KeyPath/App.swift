import AppKit
import SwiftUI

// Note: @main attribute moved to KeyPathCLI/main.swift for proper SPM building
public struct KeyPathApp: App {
    // Phase 4: MVVM - Use ViewModel instead of Manager directly
    @StateObject private var viewModel: KanataViewModel
    private let kanataManager: KanataManager
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let isHeadlessMode: Bool

    public init() {
        // Check if running in headless mode (started by LaunchAgent)
        let args = ProcessInfo.processInfo.arguments
        isHeadlessMode =
            args.contains("--headless") || ProcessInfo.processInfo.environment["KEYPATH_HEADLESS"] == "1"

        AppLogger.shared.log("🔍 [App] Initializing KeyPath - headless: \(isHeadlessMode), args: \(args)")
        let info = BuildInfo.current()
        AppLogger.shared.log("🏷️ [Build] Version: \(info.version) | Build: \(info.build) | Git: \(info.git) | Date: \(info.date)")
        AppLogger.shared.log("📦 [Bundle] Path: \(Bundle.main.bundlePath)")

        // Enable auto-trigger recording when launched with --autotrigger
        if args.contains("--autotrigger") {
            setenv("KEYPATH_AUTOTRIGGER", "1", 1)
            AppLogger.shared.log("🧪 [App] Auto-trigger flag detected (--autotrigger)")
        }

        // Set startup mode to prevent blocking operations during app launch
        setenv("KEYPATH_STARTUP_MODE", "1", 1)
        AppLogger.shared.log("🔍 [App] Startup mode set - IOHIDCheckAccess calls will be skipped")

        // Schedule a fallback clear of startup mode after 5 seconds
        // This ensures the flag doesn't stay set indefinitely if validation fails
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if ProcessInfo.processInfo.environment["KEYPATH_STARTUP_MODE"] == "1" {
                unsetenv("KEYPATH_STARTUP_MODE")
                AppLogger.shared.log("🔍 [App] Startup mode cleared via fallback timer (5s)")
            }
        }

        // Phase 4: MVVM - Initialize KanataManager and ViewModel
        let manager = KanataManager()
        self.kanataManager = manager
        _viewModel = StateObject(wrappedValue: KanataViewModel(manager: manager))
        AppLogger.shared.log("🎯 [Phase 4] MVVM architecture initialized - ViewModel wrapping KanataManager")

        // Set activation policy based on mode
        if isHeadlessMode {
            // Hide from dock in headless mode
            NSApplication.shared.setActivationPolicy(.accessory)
            AppLogger.shared.log("🤖 [App] Running in headless mode (LaunchAgent)")
        } else {
            // Show in dock for normal mode
            NSApplication.shared.setActivationPolicy(.regular)
            AppLogger.shared.log("🪟 [App] Running in normal mode (with UI)")
        }

        appDelegate.kanataManager = manager
        appDelegate.isHeadlessMode = isHeadlessMode

        // Request user notification authorization on first launch
        UserNotificationService.shared.requestAuthorizationIfNeeded()
    }

    public var body: some Scene {
        // Note: Main window now managed by AppKit MainWindowController
        // Settings scene for preferences window
        Settings {
            SettingsView()
                .environmentObject(viewModel)  // Phase 4: Inject ViewModel
                .environment(\.preferencesService, PreferencesService.shared)
                .environment(\.permissionSnapshotProvider, PermissionOracle.shared)
        }
        .commands {
            // Replace default "AppName" menu with "KeyPath" menu
            CommandGroup(replacing: .appInfo) {
                Button("About KeyPath") {
                    let info = BuildInfo.current()
                    let details = "Build \(info.build) • \(info.git) • \(info.date)"
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                                string: details,
                                attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 11)]
                            ),
                            NSApplication.AboutPanelOptionKey.applicationName: "KeyPath",
                            NSApplication.AboutPanelOptionKey.applicationVersion: info.version,
                            NSApplication.AboutPanelOptionKey.version: "Build \(info.build)"
                        ]
                    )
                }
            }

            // Add File menu with Open Config
            CommandGroup(replacing: .newItem) {
                Button("Open Config") {
                    openConfigInEditor(viewModel: viewModel)
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Show Installation Wizard") {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowWizard"), object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("How to Emergency Stop") {
                    // Emergency stop dialog will be handled by main window controller
                    NotificationCenter.default.post(name: NSNotification.Name("ShowEmergencyStop"), object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - Helper Functions

@MainActor
func openConfigInEditor(viewModel: KanataViewModel) {
    let configPath = viewModel.configPath

    // Try to open with Zed first
    let zedProcess = Process()
    zedProcess.launchPath = "/usr/local/bin/zed"
    zedProcess.arguments = [configPath]

    do {
        try zedProcess.run()
        AppLogger.shared.log("📝 Opened config in Zed")
        return
    } catch {
        // Try Homebrew path for Zed
        let homebrewZedProcess = Process()
        homebrewZedProcess.launchPath = "/opt/homebrew/bin/zed"
        homebrewZedProcess.arguments = [configPath]

        do {
            try homebrewZedProcess.run()
            AppLogger.shared.log("📝 Opened config in Zed (Homebrew)")
            return
        } catch {
            // Try using 'open' command with Zed
            let openZedProcess = Process()
            openZedProcess.launchPath = "/usr/bin/open"
            openZedProcess.arguments = ["-a", "Zed", configPath]

            do {
                try openZedProcess.run()
                AppLogger.shared.log("📝 Opened config in Zed (via open)")
                return
            } catch {
                // Fallback: open with default text editor
                let fallbackProcess = Process()
                fallbackProcess.launchPath = "/usr/bin/open"
                fallbackProcess.arguments = ["-t", configPath]

                do {
                    try fallbackProcess.run()
                    AppLogger.shared.log("📝 Opened config in default text editor")
                } catch {
                    // Last resort: open containing folder
                    let folderPath = (configPath as NSString).deletingLastPathComponent
                    NSWorkspace.shared.open(URL(fileURLWithPath: folderPath))
                    AppLogger.shared.log("📁 Opened config folder")
                }
            }
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var kanataManager: KanataManager?
    var isHeadlessMode = false
    private var mainWindowController: MainWindowController?
    private var initialMainWindowShown = false
    private var pendingReopenShow = false

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        AppLogger.shared.log("🔍 [AppDelegate] applicationShouldTerminate called")
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        AppLogger.shared.log("🔍 [AppDelegate] applicationShouldTerminateAfterLastWindowClosed called")
        return true
    }

    func applicationWillHide(_: Notification) {
        AppLogger.shared.log("🔍 [AppDelegate] applicationWillHide called")
    }

    func applicationDidBecomeActive(_: Notification) {
        AppLogger.shared.log("🔍 [AppDelegate] applicationDidBecomeActive called (initialShown=\(initialMainWindowShown))")
        
        // One-shot first activation: unconditionally show window on first activation
        if !initialMainWindowShown {
            // Log diagnostic state at first activation for future debugging
            let appActive = NSApp.isActive
            let appHidden = NSApp.isHidden
            let windowOcclusion = mainWindowController?.window?.occlusionState ?? []
            AppLogger.shared.log("🔍 [AppDelegate] First activation diagnostics: isActive=\(appActive), isHidden=\(appHidden), windowOcclusion=\(windowOcclusion.rawValue)")
            
            // Check if app was hidden and unhide if needed
            if NSApp.isHidden {
                NSApp.unhide(nil)
                AppLogger.shared.log("🪟 [AppDelegate] App was hidden, unhiding")
            }
            
            // Unconditionally show and focus the main window on first activation
            mainWindowController?.show(focus: true)
            initialMainWindowShown = true
            AppLogger.shared.log("🪟 [AppDelegate] First activation - main window shown and focused")
            if pendingReopenShow {
                AppLogger.shared.log("🪟 [AppDelegate] Applying pending reopen show after first activation")
                pendingReopenShow = false
                mainWindowController?.show(focus: true)
            }
        } else {
            // Subsequent activations: only show if window not visible
            if mainWindowController?.isWindowVisible != true {
                mainWindowController?.show(focus: true)
                AppLogger.shared.log("🪟 [AppDelegate] Subsequent activation - showing hidden window")
            } else {
                AppLogger.shared.log("🪟 [AppDelegate] Subsequent activation - window already visible")
            }
        }
    }

    func applicationDidFinishLaunching(_: Notification) {
        AppLogger.shared.log("🔍 [AppDelegate] applicationDidFinishLaunching called")

        // Log build information for traceability
        let info = BuildInfo.current()
        AppLogger.shared.log("🏷️ [Build] Version: \(info.version) | Build: \(info.build) | Git: \(info.git) | Date: \(info.date)")

        // Phase 2/3: Ensure shared UDP token exists for cross-platform compatibility
        Task { @MainActor in
            do {
                _ = try await UDPAuthTokenManager.shared.ensureToken()
                await UDPAuthTokenManager.shared.migrateExistingTokens()
                AppLogger.shared.log("🔐 [AppDelegate] UDP auth token ready")
            } catch {
                AppLogger.shared.log("❌ [AppDelegate] Failed to setup UDP auth token: \(error)")
            }
        }

        // Check for pending service bounce first
        Task { @MainActor in
            let (shouldBounce, timeSince) = PermissionGrantCoordinator.shared.checkServiceBounceNeeded()

            if shouldBounce {
                if let timeSince {
                    AppLogger.shared.log("🔄 [AppDelegate] Service bounce requested \(Int(timeSince))s ago - performing bounce")
                } else {
                    AppLogger.shared.log("🔄 [AppDelegate] Service bounce requested - performing bounce")
                }

                let bounceSuccess = await PermissionGrantCoordinator.shared.performServiceBounce()
                if bounceSuccess {
                    AppLogger.shared.log("✅ [AppDelegate] Service bounce completed successfully")
                    PermissionGrantCoordinator.shared.clearServiceBounceFlag()
                } else {
                    AppLogger.shared.log("❌ [AppDelegate] Service bounce failed - flag remains for retry")
                }
            }
        }

        if isHeadlessMode {
            AppLogger.shared.log("🤖 [AppDelegate] Headless mode - starting kanata service automatically")

            // In headless mode, ensure kanata starts
            Task {
                // Small delay to let system settle
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

                // Start kanata if not already running
                if let manager = kanataManager, !manager.isRunning {
                    await manager.startKanata()
                }
            }
        }
        // Note: In normal mode, kanata is already started in KanataManager.init() if requirements are met

        // Create main window controller (defer fronting until first activation)
        if !isHeadlessMode {
            AppLogger.shared.log("🪟 [AppDelegate] Setting up main window controller")
            
            guard let manager = kanataManager else {
                AppLogger.shared.log("❌ [AppDelegate] KanataManager is nil, cannot create window")
                return
            }
            
            mainWindowController = MainWindowController(kanataManager: manager)
            AppLogger.shared.log("🪟 [AppDelegate] Main window controller created (deferring show until activation)")

            // Defer all window fronting until the first applicationDidBecomeActive event
            // to avoid AppKit display-cycle reentrancy during initial layout.

            // Kick off boring, phased startup once the window is created.
            StartupCoordinator.shared.start()
        } else {
            AppLogger.shared.log("🤖 [AppDelegate] Headless mode - skipping window management")
        }

        // Observe notification action events
        NotificationCenter.default.addObserver(forName: .retryStartService, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let manager = self?.kanataManager else { return }
                await manager.manualStart()
                await manager.updateStatus()
            }
        }

        NotificationCenter.default.addObserver(forName: .openInputMonitoringSettings, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.kanataManager?.openInputMonitoringSettings()
            }
        }

        NotificationCenter.default.addObserver(forName: .openAccessibilitySettings, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.kanataManager?.openAccessibilitySettings()
            }
        }
    }

    func applicationWillResignActive(_: Notification) {
        AppLogger.shared.log("🔍 [AppDelegate] applicationWillResignActive called")
    }

    func applicationWillTerminate(_: Notification) {
        AppLogger.shared.log(
            "🚪 [AppDelegate] Application will terminate - performing synchronous cleanup")

        // Use synchronous cleanup to ensure kanata is stopped before app exits
        kanataManager?.cleanupSync()

        AppLogger.shared.log("✅ [AppDelegate] Cleanup complete, app terminating")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppLogger.shared.log("🔍 [AppDelegate] applicationShouldHandleReopen (hasVisibleWindows=\(flag))")

        // If UI hasn’t been set up yet (e.g., app was started in headless mode by LaunchAgent),
        // escalate to a regular app and create the main window on demand.
        if mainWindowController == nil {
            if NSApplication.shared.activationPolicy() != .regular {
                NSApplication.shared.setActivationPolicy(.regular)
                AppLogger.shared.log("🪟 [AppDelegate] Escalated activation policy to .regular for UI reopen")
            }

            if let manager = kanataManager {
                mainWindowController = MainWindowController(kanataManager: manager)
                AppLogger.shared.log("🪟 [AppDelegate] Created main window controller on reopen")
            } else {
                AppLogger.shared.log("❌ [AppDelegate] Cannot create window on reopen: KanataManager is nil")
            }
        }

        // During early startup, defer showing until first activation completed to avoid layout reentrancy
        if !initialMainWindowShown {
            pendingReopenShow = true
            AppLogger.shared.log("🪟 [AppDelegate] Reopen received before first activation; deferring show")
        } else {
            mainWindowController?.show(focus: true)
            AppLogger.shared.log("🪟 [AppDelegate] User-initiated reopen - showing main window")
        }

        return true
    }
}
