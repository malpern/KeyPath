import SwiftUI
import AppKit

@main
struct KeyPathApp: App {
    @StateObject private var kanataManager = KanataManager()
    
    init() {
        // Ensure app shows properly in dock and menu bar
        NSApplication.shared.setActivationPolicy(.regular)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(kanataManager)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    // Seamlessly stop Kanata when KeyPath quits (like Karabiner-Elements)
                    Task {
                        await kanataManager.cleanup()
                    }
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
                            NSApplication.AboutPanelOptionKey.applicationVersion: "1.0",
                            NSApplication.AboutPanelOptionKey.version: "Build 1"
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