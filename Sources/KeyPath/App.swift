import SwiftUI

@main
struct KeyPathApp: App {
    @StateObject private var kanataManager = KanataManager()
    
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
        
        Settings {
            SettingsView()
                .environmentObject(kanataManager)
        }
    }
}