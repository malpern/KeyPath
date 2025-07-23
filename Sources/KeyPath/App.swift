import SwiftUI

@main
struct KeyPathApp: App {
    @StateObject private var kanataManager = KanataManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(kanataManager)
        }
        .windowResizability(.contentSize)
        
        Settings {
            SettingsView()
                .environmentObject(kanataManager)
        }
    }
}