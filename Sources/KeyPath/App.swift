import AppKit
import SwiftUI

// Note: @main attribute moved to KeyPathCLI/main.swift for proper SPM building
public struct KeyPathApp: App {
    @StateObject private var kanataManager = KanataManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showingEmergencyStopDialog = false

    private let isHeadlessMode: Bool

    public init() {
        // Check if running in headless mode (started by LaunchAgent)
        let args = ProcessInfo.processInfo.arguments
        isHeadlessMode =
            args.contains("--headless") || ProcessInfo.processInfo.environment["KEYPATH_HEADLESS"] == "1"

        // Initialize KanataManager
        let manager = KanataManager()
        _kanataManager = StateObject(wrappedValue: manager)

        // Set activation policy based on mode
        if isHeadlessMode {
            // Hide from dock in headless mode
            NSApplication.shared.setActivationPolicy(.accessory)
            AppLogger.shared.log("🤖 [App] Running in headless mode (LaunchAgent)")
        } else {
            // Show in dock for normal mode
            NSApplication.shared.setActivationPolicy(.regular)
        }

        appDelegate.kanataManager = manager
        appDelegate.isHeadlessMode = isHeadlessMode
    }

    public var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(kanataManager)
                .environment(\.preferencesService, PreferencesService.shared)
                .environment(\.permissionService, PermissionService.shared)
                .sheet(isPresented: $showingEmergencyStopDialog) {
                    EmergencyStopDialog()
                        .interactiveDismissDisabled(false)
                }
        }
        .windowResizability(.contentSize)
        .commands {
            // Replace default "AppName" menu with "KeyPath" menu
            CommandGroup(replacing: .appInfo) {
                Button("About KeyPath") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                                string: "A powerful keyboard remapping tool for macOS",
                                attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 11)]
                            ),
                            NSApplication.AboutPanelOptionKey.applicationName: "KeyPath",
                            NSApplication.AboutPanelOptionKey.applicationVersion: "1.1",
                            NSApplication.AboutPanelOptionKey.version: "Build 2",
                        ]
                    )
                }
            }

            // Add File menu with Open Config
            CommandGroup(replacing: .newItem) {
                Button("Open Config") {
                    openConfigInEditor(kanataManager: kanataManager)
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Show Installation Wizard") {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowWizard"), object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("How to Emergency Stop") {
                    showingEmergencyStopDialog = true
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(kanataManager)
                .environment(\.preferencesService, PreferencesService.shared)
                .environment(\.permissionService, PermissionService.shared)
        }
    }
}

// MARK: - Helper Functions

@MainActor
func openConfigInEditor(kanataManager: KanataManager) {
    let configPath = kanataManager.configPath

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

class AppDelegate: NSObject, NSApplicationDelegate {
    var kanataManager: KanataManager?
    var isHeadlessMode = false

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        print("🔍 [AppDelegate] applicationShouldTerminate called")
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        print("🔍 [AppDelegate] applicationShouldTerminateAfterLastWindowClosed called")
        return true
    }

    func applicationWillHide(_: Notification) {
        print("🔍 [AppDelegate] applicationWillHide called")
    }

    func applicationDidBecomeActive(_: Notification) {
        print("🔍 [AppDelegate] applicationDidBecomeActive called")
    }

    func applicationDidFinishLaunching(_: Notification) {
        print("🔍 [AppDelegate] applicationDidFinishLaunching called")
        AppLogger.shared.log("🔍 [AppDelegate] applicationDidFinishLaunching called")

        // Check for pending service bounce first
        Task { @MainActor in
            let (shouldBounce, timeSince) = await PermissionGrantCoordinator.shared.checkServiceBounceNeeded()

            if shouldBounce {
                if let timeSince {
                    AppLogger.shared.log("🔄 [AppDelegate] Service bounce requested \(Int(timeSince))s ago - performing bounce")
                } else {
                    AppLogger.shared.log("🔄 [AppDelegate] Service bounce requested - performing bounce")
                }

                let bounceSuccess = await PermissionGrantCoordinator.shared.performServiceBounce()
                if bounceSuccess {
                    AppLogger.shared.log("✅ [AppDelegate] Service bounce completed successfully")
                    await PermissionGrantCoordinator.shared.clearServiceBounceFlag()
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
    }

    func applicationWillResignActive(_: Notification) {
        print("🔍 [AppDelegate] applicationWillResignActive called")
    }

    func applicationWillTerminate(_: Notification) {
        AppLogger.shared.log(
            "🚪 [AppDelegate] Application will terminate - performing synchronous cleanup")

        // Use synchronous cleanup to ensure kanata is stopped before app exits
        kanataManager?.cleanupSync()

        AppLogger.shared.log("✅ [AppDelegate] Cleanup complete, app terminating")
    }
}
