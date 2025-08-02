import AppKit
import SwiftUI

@main
struct KeyPathApp: App {
    @StateObject private var kanataManager = KanataManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Ensure app shows properly in dock and menu bar
        NSApplication.shared.setActivationPolicy(.regular)
        appDelegate.kanataManager = kanataManager
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(kanataManager)
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
            }
        }

        Settings {
            SettingsView()
                .environmentObject(kanataManager)
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

        // Note: Kanata is already started in KanataManager.init() if requirements are met
        // No need to start it again here
    }

    func applicationWillResignActive(_: Notification) {
        print("🔍 [AppDelegate] applicationWillResignActive called")
    }

    func applicationWillTerminate(_: Notification) {
        // Ensure Kanata is stopped when the app quits.
        Task {
            await kanataManager?.cleanup()
        }
    }
}
