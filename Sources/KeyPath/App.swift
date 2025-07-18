import SwiftUI

@main
struct KeyPathApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        
        Settings {
            SettingsView()
        }
    }
}