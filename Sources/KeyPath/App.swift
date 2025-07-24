import SwiftUI
import AppKit

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
                            NSApplication.AboutPanelOptionKey.version: "Build 2"
                        ]
                    )
                }
            }
        }
        
        Settings {
            SettingsView()
                .environmentObject(kanataManager)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var kanataManager: KanataManager?

    func applicationWillTerminate(_ notification: Notification) {
        // Ensure Kanata is stopped when the app quits.
        Task {
            await kanataManager?.cleanup()
        }
    }
}